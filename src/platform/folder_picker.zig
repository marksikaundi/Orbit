//! Native folder picker — choose a project directory from the filesystem.

const std = @import("std");
const builtin = @import("builtin");

pub const PumpFn = *const fn () void;

/// Shows a native folder chooser. Returns an owned absolute path, or `null` if
/// the user cancelled. Caller must free the returned slice.
///
/// When `pump` is provided it is called while waiting so the UI event loop
/// keeps ticking (avoids macOS "Application Not Responding" during the dialog).
pub fn pickFolder(allocator: std.mem.Allocator, io: std.Io, pump: ?PumpFn) !?[]u8 {
    return switch (builtin.os.tag) {
        .macos => pickMacos(allocator, io, pump),
        .linux => pickLinux(allocator, io, pump),
        .windows => pickWindows(allocator, io, pump),
        else => error.UnsupportedPlatform,
    };
}

fn pickMacos(allocator: std.mem.Allocator, io: std.Io, pump: ?PumpFn) !?[]u8 {
    // NSOpenPanel via AppleScript — no ObjC bridge required.
    const script =
        \\POSIX path of (choose folder with prompt "Open Workspace")
    ;
    return runChooser(allocator, io, &.{ "/usr/bin/osascript", "-e", script }, pump);
}

fn pickLinux(allocator: std.mem.Allocator, io: std.Io, pump: ?PumpFn) !?[]u8 {
    // Prefer zenity, then kdialog.
    if (try runChooser(allocator, io, &.{
        "zenity",
        "--file-selection",
        "--directory",
        "--title=Open Workspace",
    }, pump)) |path| return path;

    return runChooser(allocator, io, &.{
        "kdialog",
        "--getexistingdirectory",
        ".",
        "--title",
        "Open Workspace",
    }, pump);
}

fn pickWindows(allocator: std.mem.Allocator, io: std.Io, pump: ?PumpFn) !?[]u8 {
    // FolderBrowserDialog via PowerShell (no extra Win32 COM glue required).
    const script =
        \\Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.FolderBrowserDialog; $f.Description = 'Open Workspace'; $f.ShowNewFolderButton = $true; if ($f.ShowDialog() -eq 'OK') { Write-Output $f.SelectedPath }
    ;
    return runChooser(allocator, io, &.{
        "powershell",
        "-NoProfile",
        "-STA",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        script,
    }, pump);
}

fn runChooser(allocator: std.mem.Allocator, io: std.Io, argv: []const []const u8, pump: ?PumpFn) !?[]u8 {
    if (pump == null) {
        return runChooserBlocking(allocator, io, argv);
    }
    return runChooserPumped(allocator, io, argv, pump.?);
}

fn runChooserBlocking(allocator: std.mem.Allocator, io: std.Io, argv: []const []const u8) !?[]u8 {
    const result = std.process.run(allocator, io, .{
        .argv = argv,
        .stdout_limit = .limited(std.fs.max_path_bytes + 16),
        .stderr_limit = .limited(4096),
    }) catch return null;
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    switch (result.term) {
        .exited => |code| {
            if (code != 0) return null;
        },
        else => return null,
    }
    if (result.stdout.len == 0) return null;
    return try normalizePath(allocator, result.stdout);
}

/// Run the chooser on a worker thread so we can pump GLFW on the main thread.
fn runChooserPumped(allocator: std.mem.Allocator, io: std.Io, argv: []const []const u8, pump: PumpFn) !?[]u8 {
    const Slot = struct {
        allocator: std.mem.Allocator,
        io: std.Io,
        argv: []const []const u8,
        stdout: ?[]u8 = null,
        stderr: ?[]u8 = null,
        code: ?u8 = null,
        failed: bool = false,
        done: std.atomic.Value(bool) = .init(false),
    };

    // argv must outlive the worker — caller passes string literals / stable slices.
    var slot: Slot = .{
        .allocator = allocator,
        .io = io,
        .argv = argv,
    };

    const thr = try std.Thread.spawn(.{}, struct {
        fn work(s: *Slot) void {
            defer s.done.store(true, .release);
            const result = std.process.run(s.allocator, s.io, .{
                .argv = s.argv,
                .stdout_limit = .limited(std.fs.max_path_bytes + 16),
                .stderr_limit = .limited(4096),
            }) catch {
                s.failed = true;
                return;
            };
            s.stdout = result.stdout;
            s.stderr = result.stderr;
            s.code = switch (result.term) {
                .exited => |code| code,
                else => null,
            };
        }
    }.work, .{&slot});

    while (!slot.done.load(.acquire)) {
        pump();
        sleepMs(10);
    }
    thr.join();

    if (slot.failed) return error.PickerFailed;
    if (slot.stderr) |e| allocator.free(e);
    const stdout = slot.stdout orelse return null;
    defer allocator.free(stdout);
    const code = slot.code orelse return null;
    if (code != 0 or stdout.len == 0) return null;
    return try normalizePath(allocator, stdout);
}

fn sleepMs(ms: u64) void {
    if (builtin.os.tag == .windows) {
        const Sleep = struct {
            extern "kernel32" fn Sleep(dwMilliseconds: u32) callconv(.winapi) void;
        };
        Sleep.Sleep(@intCast(ms));
        return;
    }
    const c = @import("../c.zig").c;
    var req = c.struct_timespec{
        .tv_sec = @intCast(ms / 1000),
        .tv_nsec = @intCast((ms % 1000) * std.time.ns_per_ms),
    };
    _ = c.nanosleep(&req, null);
}

fn normalizePath(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var path = std.mem.trim(u8, raw, " \t\r\n");
    while (path.len > 1 and (path[path.len - 1] == '/' or path[path.len - 1] == '\\')) {
        path = path[0 .. path.len - 1];
    }
    if (path.len == 0) return error.EmptyPath;
    return try allocator.dupe(u8, path);
}

/// Last path component suitable for a tab / workspace title.
pub fn folderBasename(path: []const u8) []const u8 {
    var p = path;
    while (p.len > 1 and (p[p.len - 1] == '/' or p[p.len - 1] == '\\')) p = p[0 .. p.len - 1];
    if (std.mem.lastIndexOfAny(u8, p, "/\\")) |i| {
        if (i + 1 < p.len) return p[i + 1 ..];
    }
    return p;
}

test "folderBasename" {
    try std.testing.expectEqualStrings("Orbit", folderBasename("/Users/me/Orbit"));
    try std.testing.expectEqualStrings("Orbit", folderBasename("/Users/me/Orbit/"));
    try std.testing.expectEqualStrings("Orbit", folderBasename("C:\\Users\\me\\Orbit"));
    try std.testing.expectEqualStrings("tmp", folderBasename("/tmp"));
}
