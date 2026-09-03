//! `orbit ide-setup` — register Orbit as the external terminal in Cursor / VS Code / others.

const std = @import("std");
const builtin = @import("builtin");
const jsonc = @import("jsonc.zig");
const paths = @import("../platform/paths.zig");
const dev_root = @import("../dev_root.zig");

const Pair = jsonc.Pair;

const EditorId = enum {
    cursor,
    vscode,
    vscode_insiders,
    vscodium,
    windsurf,
    all,
};

pub fn run(allocator: std.mem.Allocator, io: std.Io, editor_arg: ?[]const u8) !void {
    const which = parseEditor(editor_arg) orelse {
        std.debug.print("error: unknown editor `{s}` (try cursor|code|codium|windsurf|all)\n", .{editor_arg.?});
        std.process.exit(2);
    };

    const linux_exec = try writeIdeWrapper(allocator, io);
    defer if (linux_exec) |p| allocator.free(p);
    const windows_exec = linux_exec;

    const osx_exec: []const u8 = "Orbit.app";
    const linux_val: []const u8 = linux_exec orelse "orbit";
    const win_val: []const u8 = windows_exec orelse "orbit.exe";

    const pairs = [_]Pair{
        .{ .k = "terminal.external.osxExec", .v = osx_exec },
        .{ .k = "terminal.external.linuxExec", .v = linux_val },
        .{ .k = "terminal.external.windowsExec", .v = win_val },
        .{ .k = "terminal.explorerKind", .v = "both" },
    };

    var patched: usize = 0;
    var targets = editorTargets(which);

    std.debug.print("Orbit IDE setup\n", .{});
    for (&targets) |*t| {
        if (!t.active) continue;
        const settings = try t.settingsPath(allocator);
        defer allocator.free(settings);
        patchSettings(allocator, io, settings, &pairs) catch |err| {
            switch (err) {
                error.FileTooLarge => std.debug.print(
                    "  {s}: skip (settings.json > 512 KiB, file left unchanged)\n",
                    .{t.name},
                ),
                error.ReadFailed => std.debug.print(
                    "  {s}: skip (could not read settings.json, file left unchanged)\n",
                    .{t.name},
                ),
                else => std.debug.print("  {s}: skip ({s})\n", .{ t.name, @errorName(err) }),
            }
            continue;
        };
        std.debug.print("  {s}: {s}\n", .{ t.name, settings });
        patched += 1;
    }

    const ext_n = installExtensions(allocator, io, which);
    maybeRegisterMacApp(allocator, io);

    std.debug.print("\nPatched {d} editor settings, installed {d} extension(s).\n", .{ patched, ext_n });
    std.debug.print("Reload the editor window, then:\n", .{});
    std.debug.print("  • Explorer → right-click a folder → Open in Orbit Terminal\n", .{});
    std.debug.print("  • Command Palette → “Open in Orbit Terminal”\n", .{});
    std.debug.print("  • Explorer gear → Open in External Terminal (uses Orbit)\n", .{});
    if (builtin.os.tag == .macos) {
        std.debug.print("\nmacOS: keep Orbit.app available (zig build / zig build setup).\n", .{});
        std.debug.print("`open -a Orbit.app` must resolve — copy to ~/Applications if needed.\n", .{});
    }
}

fn parseEditor(arg: ?[]const u8) ?EditorId {
    const s = arg orelse return .all;
    if (std.mem.eql(u8, s, "all")) return .all;
    if (std.mem.eql(u8, s, "cursor")) return .cursor;
    if (std.mem.eql(u8, s, "code") or std.mem.eql(u8, s, "vscode") or std.mem.eql(u8, s, "vs-code")) return .vscode;
    if (std.mem.eql(u8, s, "insiders") or std.mem.eql(u8, s, "vscode-insiders")) return .vscode_insiders;
    if (std.mem.eql(u8, s, "codium") or std.mem.eql(u8, s, "vscodium")) return .vscodium;
    if (std.mem.eql(u8, s, "windsurf")) return .windsurf;
    return null;
}

const Target = struct {
    id: EditorId,
    name: []const u8,
    /// Relative to the OS editor config root (Application Support / .config / APPDATA).
    support_dir: []const u8,
    /// `~/.cursor/extensions` style home-relative folder (unix + windows).
    ext_home: []const u8,
    active: bool = true,

    fn settingsPath(self: *const Target, allocator: std.mem.Allocator) ![]u8 {
        const root = try editorSupportRoot(allocator, self.support_dir);
        defer allocator.free(root);
        return std.fmt.allocPrint(allocator, "{s}{c}User{c}settings.json", .{ root, std.fs.path.sep, std.fs.path.sep });
    }

    fn extensionDir(self: *const Target, allocator: std.mem.Allocator) ![]u8 {
        const home = paths.homeDir() orelse return error.NoHome;
        return std.fmt.allocPrint(allocator, "{s}{c}{s}{c}extensions{c}orbit.orbit-terminal-0.1.0", .{
            home,
            std.fs.path.sep,
            self.ext_home,
            std.fs.path.sep,
            std.fs.path.sep,
        });
    }
};

fn editorTargets(which: EditorId) [5]Target {
    var all = [_]Target{
        .{ .id = .cursor, .name = "Cursor", .support_dir = "Cursor", .ext_home = ".cursor" },
        .{ .id = .vscode, .name = "VS Code", .support_dir = "Code", .ext_home = ".vscode" },
        .{ .id = .vscode_insiders, .name = "VS Code Insiders", .support_dir = "Code - Insiders", .ext_home = ".vscode-insiders" },
        .{ .id = .vscodium, .name = "VSCodium", .support_dir = "VSCodium", .ext_home = ".vscode-oss" },
        .{ .id = .windsurf, .name = "Windsurf", .support_dir = "Windsurf", .ext_home = ".windsurf" },
    };
    if (which == .all) return all;
    for (&all) |*t| {
        t.active = t.id == which;
    }
    return all;
}

fn editorSupportRoot(allocator: std.mem.Allocator, support_dir: []const u8) ![]u8 {
    const home = paths.homeDir() orelse return error.NoHome;
    if (builtin.os.tag == .macos) {
        return std.fmt.allocPrint(allocator, "{s}/Library/Application Support/{s}", .{ home, support_dir });
    }
    if (builtin.os.tag == .windows) {
        if (std.c.getenv("APPDATA")) |appdata| {
            const span = std.mem.span(appdata);
            if (span.len > 0) {
                return std.fmt.allocPrint(allocator, "{s}\\{s}", .{ span, support_dir });
            }
        }
        return std.fmt.allocPrint(allocator, "{s}\\AppData\\Roaming\\{s}", .{ home, support_dir });
    }
    return std.fmt.allocPrint(allocator, "{s}/.config/{s}", .{ home, support_dir });
}

fn patchSettings(
    allocator: std.mem.Allocator,
    io: std.Io,
    settings_path: []const u8,
    pairs: []const Pair,
) !void {
    const parent = std.fs.path.dirname(settings_path) orelse return error.NoDir;
    paths.ensureDir(parent);

    const existing = readFile(allocator, io, settings_path) catch |err| switch (err) {
        error.NotFound => "",
        else => return err,
    };
    defer if (existing.len > 0) allocator.free(existing);

    const next = try jsonc.upsertMany(allocator, existing, pairs);
    defer allocator.free(next);

    try writeFileAtomic(allocator, io, settings_path, next);
}

const max_settings_bytes: usize = 512 * 1024;

fn readFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    return readFileLimited(allocator, io, path, max_settings_bytes);
}

fn readFileLimited(allocator: std.mem.Allocator, io: std.Io, path: []const u8, limit: usize) ![]u8 {
    const file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return error.NotFound;
    defer file.close(io);
    var buf: [4096]u8 = undefined;
    var reader = file.reader(io, &buf);
    return reader.interface.allocRemaining(allocator, .limited(limit)) catch |err| switch (err) {
        error.StreamTooLong => return error.FileTooLarge,
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.ReadFailed,
    };
}

fn writeFileAtomic(allocator: std.mem.Allocator, io: std.Io, path: []const u8, data: []const u8) !void {
    const tmp = try std.fmt.allocPrint(allocator, "{s}.orbit-tmp", .{path});
    defer allocator.free(tmp);
    errdefer std.Io.Dir.deleteFileAbsolute(io, tmp) catch {};

    {
        const file = try std.Io.Dir.createFileAbsolute(io, tmp, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, data);
    }
    try std.Io.Dir.renameAbsolute(tmp, path, io);
}

fn writeIdeWrapper(allocator: std.mem.Allocator, io: std.Io) !?[]u8 {
    const orbit_bin = resolveOrbitLaunchPath(allocator, io) orelse return null;
    defer allocator.free(orbit_bin);

    if (builtin.os.tag == .windows) {
        const dir = try std.fmt.allocPrint(allocator, "{s}\\Orbit\\bin", .{
            if (std.c.getenv("LOCALAPPDATA")) |v| std.mem.span(v) else return null,
        });
        defer allocator.free(dir);
        paths.ensureDir(dir);
        const dest = try std.fmt.allocPrint(allocator, "{s}\\orbit-ide.cmd", .{dir});
        const body = try std.fmt.allocPrint(allocator,
            \\@echo off
            \\REM Orbit IDE launcher — VS Code/Cursor spawn this with cwd = project folder
            \\"{s}" --working-directory "%CD%" %*
            \\
        , .{orbit_bin});
        defer allocator.free(body);
        const file = try std.Io.Dir.createFileAbsolute(io, dest, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, body);
        std.debug.print("  wrapper: {s}\n", .{dest});
        return dest;
    }

    const home = paths.homeDir() orelse return null;
    const dir = try std.fmt.allocPrint(allocator, "{s}/.local/bin", .{home});
    defer allocator.free(dir);
    paths.ensureDir(dir);
    const dest = try std.fmt.allocPrint(allocator, "{s}/orbit-ide", .{dir});
    const body = try std.fmt.allocPrint(allocator,
        \\#!/usr/bin/env bash
        \\# Orbit IDE launcher — VS Code/Cursor spawn this with cwd = project folder.
        \\set -euo pipefail
        \\exec "{s}" --working-directory "$PWD" "$@"
        \\
    , .{orbit_bin});
    defer allocator.free(body);
    const file = try std.Io.Dir.createFileAbsolute(io, dest, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, body);
    chmod755(dest);
    std.debug.print("  wrapper: {s}\n", .{dest});
    return dest;
}

fn resolveOrbitLaunchPath(allocator: std.mem.Allocator, io: std.Io) ?[]u8 {
    if (dev_root.resolve(allocator, io)) |root| {
        defer allocator.free(root);
        if (builtin.os.tag == .macos) {
            const app = std.fmt.allocPrint(allocator, "{s}/zig-out/Orbit.app/Contents/MacOS/orbit", .{root}) catch return null;
            if (paths.pathExecutable(app)) return app;
            allocator.free(app);
        }
        const plain = std.fmt.allocPrint(allocator, "{s}{c}zig-out{c}bin{c}{s}", .{
            root,
            std.fs.path.sep,
            std.fs.path.sep,
            std.fs.path.sep,
            if (builtin.os.tag == .windows) "orbit.exe" else "orbit",
        }) catch return null;
        if (paths.pathExecutable(plain)) return plain;
        allocator.free(plain);
    }

    if (builtin.os.tag != .windows) {
        const home = paths.homeDir() orelse return null;
        const local = std.fmt.allocPrint(allocator, "{s}/.local/bin/orbit", .{home}) catch return null;
        if (paths.pathExists(local)) return local;
        allocator.free(local);
    }
    return allocator.dupe(u8, if (builtin.os.tag == .windows) "orbit.exe" else "orbit") catch null;
}

fn installExtensions(allocator: std.mem.Allocator, io: std.Io, which: EditorId) usize {
    const src_root = dev_root.resolve(allocator, io) orelse {
        std.debug.print("  extension: skipped (Orbit source tree not found — run zig build setup)\n", .{});
        return 0;
    };
    defer allocator.free(src_root);

    const src_dir = std.fmt.allocPrint(allocator, "{s}{c}editors{c}vscode", .{ src_root, std.fs.path.sep, std.fs.path.sep }) catch return 0;
    defer allocator.free(src_dir);
    if (!paths.pathExists(src_dir)) {
        std.debug.print("  extension: skipped (missing {s})\n", .{src_dir});
        return 0;
    }

    var n: usize = 0;
    var targets = editorTargets(which);
    for (&targets) |*t| {
        if (!t.active) continue;
        const dest = t.extensionDir(allocator) catch continue;
        defer allocator.free(dest);
        copyExtension(allocator, io, src_dir, dest) catch |err| {
            std.debug.print("  {s} extension: skip ({s})\n", .{ t.name, @errorName(err) });
            continue;
        };
        std.debug.print("  {s} extension: {s}\n", .{ t.name, dest });
        n += 1;
    }
    return n;
}

fn copyExtension(allocator: std.mem.Allocator, io: std.Io, src_dir: []const u8, dest_dir: []const u8) !void {
    paths.ensureDir(dest_dir);
    const files = [_][]const u8{ "package.json", "extension.js", "README.md" };
    for (files) |name| {
        const from = try std.fmt.allocPrint(allocator, "{s}{c}{s}", .{ src_dir, std.fs.path.sep, name });
        defer allocator.free(from);
        const to = try std.fmt.allocPrint(allocator, "{s}{c}{s}", .{ dest_dir, std.fs.path.sep, name });
        defer allocator.free(to);
        const data = readFile(allocator, io, from) catch continue;
        defer allocator.free(data);
        const file = try std.Io.Dir.createFileAbsolute(io, to, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, data);
    }
}

fn maybeRegisterMacApp(allocator: std.mem.Allocator, io: std.Io) void {
    if (builtin.os.tag != .macos) return;
    const root = dev_root.resolve(allocator, io) orelse return;
    defer allocator.free(root);
    const app = std.fmt.allocPrint(allocator, "{s}/zig-out/Orbit.app", .{root}) catch return;
    defer allocator.free(app);
    if (!paths.pathExists(app)) return;

    const home = paths.homeDir() orelse return;
    const dest = std.fmt.allocPrint(allocator, "{s}/Applications/Orbit.app", .{home}) catch return;
    defer allocator.free(dest);
    if (!std.mem.startsWith(u8, dest, home)) return;
    if (!std.mem.endsWith(u8, dest, "Orbit.app")) return;
    if (std.fs.path.dirname(dest)) |dir| paths.ensureDir(dir);

    // Copy so `open -a Orbit.app` (Cursor / VS Code) resolves by name.
    if (std.process.run(allocator, io, .{
        .argv = &.{ "/bin/rm", "-rf", dest },
        .stdout_limit = .limited(64),
        .stderr_limit = .limited(256),
    })) |rm| {
        allocator.free(rm.stdout);
        allocator.free(rm.stderr);
    } else |_| {}
    const copied = std.process.run(allocator, io, .{
        .argv = &.{ "/bin/cp", "-R", app, dest },
        .stdout_limit = .limited(64),
        .stderr_limit = .limited(1024),
    }) catch return;
    allocator.free(copied.stdout);
    allocator.free(copied.stderr);
    std.debug.print("  macOS app: {s}\n", .{dest});
}

fn chmod755(path: []const u8) void {
    if (builtin.os.tag == .windows) return;
    var buf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= buf.len) return;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    _ = std.c.chmod(buf[0..path.len :0], 0o755);
}

test "readFile missing is NotFound" {
    const io = std.testing.io;
    try std.testing.expectError(
        error.NotFound,
        readFile(std.testing.allocator, io, "/this/orbit-ide-setup-missing-settings.json"),
    );
}

test "readFileLimited rejects oversized files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    {
        const file = try tmp.dir.createFile(io, "big.json", .{});
        defer file.close(io);
        try file.writeStreamingAll(io, "0123456789");
    }
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPathFile(io, "big.json", &buf);
    try std.testing.expectError(
        error.FileTooLarge,
        readFileLimited(std.testing.allocator, io, buf[0..n], 4),
    );
}

test "patchSettings merges without dropping existing keys" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    {
        const file = try tmp.dir.createFile(io, "settings.json", .{});
        defer file.close(io);
        try file.writeStreamingAll(io, "{\n    \"editor.fontSize\": 14\n}\n");
    }
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPathFile(io, "settings.json", &buf);
    const pairs = [_]Pair{
        .{ .k = "terminal.explorerKind", .v = "both" },
    };
    try patchSettings(allocator, io, buf[0..n], &pairs);
    const data = try readFile(allocator, io, buf[0..n]);
    defer allocator.free(data);
    try std.testing.expect(std.mem.indexOf(u8, data, "editor.fontSize") != null);
    try std.testing.expect(std.mem.indexOf(u8, data, "terminal.explorerKind") != null);
}
