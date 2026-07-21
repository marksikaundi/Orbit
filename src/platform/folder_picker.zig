//! Native folder picker — choose a project directory from the filesystem.

const std = @import("std");
const builtin = @import("builtin");

/// Shows a native folder chooser. Returns an owned absolute path, or `null` if
/// the user cancelled. Caller must free the returned slice.
pub fn pickFolder(allocator: std.mem.Allocator, io: std.Io) !?[]u8 {
    return switch (builtin.os.tag) {
        .macos => pickMacos(allocator, io),
        .linux => pickLinux(allocator, io),
        else => error.UnsupportedPlatform,
    };
}

fn pickMacos(allocator: std.mem.Allocator, io: std.Io) !?[]u8 {
    // NSOpenPanel via AppleScript — no ObjC bridge required.
    const script =
        \\POSIX path of (choose folder with prompt "Open Workspace")
    ;
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "/usr/bin/osascript", "-e", script },
        .stdout_limit = .limited(std.fs.max_path_bytes + 16),
        .stderr_limit = .limited(4096),
    }) catch return error.PickerFailed;
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    switch (result.term) {
        .exited => |code| {
            if (code != 0) return null; // cancel / user dismissed
        },
        else => return null,
    }

    return try normalizePath(allocator, result.stdout);
}

fn pickLinux(allocator: std.mem.Allocator, io: std.Io) !?[]u8 {
    // Prefer zenity, then kdialog.
    if (try runChooser(allocator, io, &.{
        "zenity",
        "--file-selection",
        "--directory",
        "--title=Open Workspace",
    })) |path| return path;

    return runChooser(allocator, io, &.{
        "kdialog",
        "--getexistingdirectory",
        ".",
        "--title",
        "Open Workspace",
    });
}

fn runChooser(allocator: std.mem.Allocator, io: std.Io, argv: []const []const u8) !?[]u8 {
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

fn normalizePath(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var path = std.mem.trim(u8, raw, " \t\r\n");
    while (path.len > 1 and path[path.len - 1] == '/') {
        path = path[0 .. path.len - 1];
    }
    if (path.len == 0) return error.EmptyPath;
    return try allocator.dupe(u8, path);
}

/// Last path component suitable for a tab / workspace title.
pub fn folderBasename(path: []const u8) []const u8 {
    var p = path;
    while (p.len > 1 and p[p.len - 1] == '/') p = p[0 .. p.len - 1];
    if (std.mem.lastIndexOfScalar(u8, p, '/')) |i| {
        if (i + 1 < p.len) return p[i + 1 ..];
    }
    return p;
}

test "folderBasename" {
    try std.testing.expectEqualStrings("Orbit", folderBasename("/Users/me/Orbit"));
    try std.testing.expectEqualStrings("Orbit", folderBasename("/Users/me/Orbit/"));
    try std.testing.expectEqualStrings("tmp", folderBasename("/tmp"));
}
