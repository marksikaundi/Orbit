//! Portable home / config paths and filesystem helpers.

const std = @import("std");
const builtin = @import("builtin");

/// User home directory (`HOME`, or `USERPROFILE` on Windows).
pub fn homeDir() ?[]const u8 {
    if (std.c.getenv("HOME")) |h| {
        const span = std.mem.span(h);
        if (span.len > 0) return span;
    }
    if (builtin.os.tag == .windows) {
        if (std.c.getenv("USERPROFILE")) |u| {
            const span = std.mem.span(u);
            if (span.len > 0) return span;
        }
    }
    return null;
}

/// Orbit config root:
/// - Unix: `$HOME/.config/orbit`
/// - Windows: `%APPDATA%\orbit` (falls back to `%USERPROFILE%\.config\orbit`)
pub fn configDir(allocator: std.mem.Allocator) ![]u8 {
    if (builtin.os.tag == .windows) {
        if (std.c.getenv("APPDATA")) |appdata| {
            const span = std.mem.span(appdata);
            if (span.len > 0) {
                return try std.fmt.allocPrint(allocator, "{s}\\orbit", .{span});
            }
        }
    }
    const home = homeDir() orelse return error.NoHome;
    if (builtin.os.tag == .windows) {
        return try std.fmt.allocPrint(allocator, "{s}\\.config\\orbit", .{home});
    }
    return try std.fmt.allocPrint(allocator, "{s}/.config/orbit", .{home});
}

pub fn joinConfig(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    const root = try configDir(allocator);
    defer allocator.free(root);
    if (parts.len == 0) return try allocator.dupe(u8, root);

    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try list.appendSlice(allocator, root);
    for (parts) |part| {
        try list.append(allocator, sep());
        try list.appendSlice(allocator, part);
    }
    return try list.toOwnedSlice(allocator);
}

fn sep() u8 {
    return if (builtin.os.tag == .windows) '\\' else '/';
}

/// Create nested directories (absolute path). Best-effort; ignores existing dirs.
pub fn ensureDir(path: []const u8) void {
    if (path.len == 0) return;
    var buf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= buf.len) return;

    var start: usize = 0;
    if (builtin.os.tag == .windows) {
        if (path.len >= 2 and path[1] == ':') {
            start = 2;
            if (path.len >= 3 and isSep(path[2])) start = 3;
        } else if (path.len >= 2 and isSep(path[0]) and isSep(path[1])) {
            start = 2;
        }
    } else if (isSep(path[0])) {
        start = 1;
    }

    var i = start;
    while (i <= path.len) : (i += 1) {
        if (i < path.len and !isSep(path[i])) continue;
        if (i == 0) continue;
        @memcpy(buf[0..i], path[0..i]);
        buf[i] = 0;
        if (builtin.os.tag == .windows) {
            _ = win.CreateDirectoryA(buf[0..i :0].ptr, null);
        } else {
            _ = std.c.mkdir(buf[0..i :0], 0o755);
        }
        if (i == path.len) break;
    }
}

fn isSep(ch: u8) bool {
    return ch == '/' or ch == '\\';
}

pub fn pathExists(path: []const u8) bool {
    if (path.len == 0) return false;
    var buf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= buf.len) return false;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    if (builtin.os.tag == .windows) {
        const INVALID: u32 = 0xFFFFFFFF;
        return win.GetFileAttributesA(buf[0..path.len :0].ptr) != INVALID;
    }
    return std.c.access(buf[0..path.len :0], 0) == 0; // F_OK
}

/// True if `path` exists and looks runnable (Unix: X_OK; Windows: file exists / PATH name).
pub fn pathExecutable(path: []const u8) bool {
    if (path.len == 0) return false;
    if (builtin.os.tag == .windows) {
        if (pathExists(path)) return true;
        // Bare names like `powershell.exe` are resolved by CreateProcess via PATH.
        if (std.mem.indexOfScalar(u8, path, '\\') == null and std.mem.indexOfScalar(u8, path, '/') == null) {
            if (std.mem.indexOfScalar(u8, path, '.')) |_| return true;
        }
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        if (path.len + 4 < buf.len and !std.ascii.endsWithIgnoreCase(path, ".exe")) {
            @memcpy(buf[0..path.len], path);
            @memcpy(buf[path.len..][0..4], ".exe");
            return pathExists(buf[0 .. path.len + 4]);
        }
        return false;
    }
    var buf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= buf.len) return false;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    return std.c.access(buf[0..path.len :0], 1) == 0; // X_OK
}

/// Default interactive shell path for new sessions.
pub fn defaultShell() []const u8 {
    if (builtin.os.tag == .windows) {
        if (std.c.getenv("COMSPEC")) |c| {
            const span = std.mem.span(c);
            if (span.len > 0) return span;
        }
        return "powershell.exe";
    }
    if (std.c.getenv("SHELL")) |s| {
        const span = std.mem.span(s);
        if (span.len > 0) return span;
    }
    return "/bin/zsh";
}

/// Fallback cwd when none is configured.
pub fn defaultCwd() []const u8 {
    if (homeDir()) |h| return h;
    return if (builtin.os.tag == .windows) "C:\\" else "/";
}

const win = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn SetEnvironmentVariableA(
        lpName: [*:0]const u8,
        lpValue: ?[*:0]const u8,
    ) callconv(.winapi) std.os.windows.BOOL;
    extern "kernel32" fn CreateDirectoryA(
        lpPathName: [*:0]const u8,
        lpSecurityAttributes: ?*anyopaque,
    ) callconv(.winapi) std.os.windows.BOOL;
    extern "kernel32" fn GetFileAttributesA(
        lpFileName: [*:0]const u8,
    ) callconv(.winapi) u32;
} else struct {};

/// Set a process environment variable (inherited by child shells / ConPTY).
pub fn setEnv(key: []const u8, value: []const u8) void {
    var key_buf: [256:0]u8 = undefined;
    var val_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (key.len >= key_buf.len or value.len >= val_buf.len) return;
    @memcpy(key_buf[0..key.len], key);
    key_buf[key.len] = 0;
    @memcpy(val_buf[0..value.len], value);
    val_buf[value.len] = 0;
    if (builtin.os.tag == .windows) {
        _ = win.SetEnvironmentVariableA(
            key_buf[0..key.len :0].ptr,
            val_buf[0..value.len :0].ptr,
        );
        return;
    }
    // Prefer Orbit's @cImport bindings (stdlib.h) over std.c, which may omit setenv.
    const c = @import("../c.zig").c;
    _ = c.setenv(key_buf[0..key.len :0], val_buf[0..value.len :0], 1);
}

test "folder path separators helper" {
    try std.testing.expect(isSep('/'));
    try std.testing.expect(isSep('\\'));
    try std.testing.expect(!isSep('a'));
}
