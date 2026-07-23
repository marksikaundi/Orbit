//! Allowed shells for Orbit sessions (config + workspace restore).

const std = @import("std");
const builtin = @import("builtin");
const paths = @import("paths.zig");

const allowed_basenames = if (builtin.os.tag == .windows) [_][]const u8{
    "powershell.exe",
    "powershell",
    "pwsh.exe",
    "pwsh",
    "cmd.exe",
    "cmd",
} else [_][]const u8{
    "zsh",
    "bash",
    "sh",
    "fish",
    "dash",
};

const unix_prefixes = [_][]const u8{
    "/bin/",
    "/usr/bin/",
    "/usr/local/bin/",
    "/opt/homebrew/bin/",
    "/opt/local/bin/",
};

/// True when `path` is a safe interactive shell Orbit may launch.
pub fn isAllowed(path: []const u8) bool {
    if (path.len == 0) return false;
    if (std.mem.indexOf(u8, path, "..") != null) return false;
    for (path) |ch| {
        if (ch < 32 or ch == '"' or ch == '\'' or ch == ';' or ch == '|' or ch == '&' or ch == '<' or ch == '>' or ch == '`') {
            return false;
        }
    }

    // User login shell / Windows COMSPEC are always trusted.
    if (builtin.os.tag != .windows) {
        if (std.c.getenv("SHELL")) |env| {
            if (std.mem.eql(u8, std.mem.span(env), path)) return true;
        }
    } else {
        if (std.c.getenv("COMSPEC")) |env| {
            if (std.ascii.eqlIgnoreCase(std.mem.span(env), path)) return true;
        }
    }

    const base = basename(path);
    if (!basenameAllowed(base)) return false;

    if (builtin.os.tag == .windows) {
        // Bare names (resolved via PATH by CreateProcess).
        if (std.mem.indexOfScalar(u8, path, '\\') == null and std.mem.indexOfScalar(u8, path, '/') == null) {
            return true;
        }
        // Absolute paths under common install roots.
        return windowsPathLooksTrusted(path);
    }

    if (path[0] != '/') return false;
    for (unix_prefixes) |prefix| {
        if (std.mem.startsWith(u8, path, prefix)) return true;
    }
    return false;
}

/// Return `path` when allowed, otherwise the platform default shell.
pub fn sanitize(path: ?[]const u8) []const u8 {
    if (path) |p| {
        if (p.len > 0 and isAllowed(p)) {
            // Bare Windows names are OK without a pre-check; Unix needs the binary.
            if (builtin.os.tag == .windows) {
                if (std.mem.indexOfScalar(u8, p, '\\') == null and std.mem.indexOfScalar(u8, p, '/') == null) {
                    return p;
                }
            }
            if (paths.pathExecutable(p)) return p;
        }
    }
    return paths.defaultShell();
}

fn basename(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfAny(u8, path, "/\\")) |i| return path[i + 1 ..];
    return path;
}

fn basenameAllowed(base: []const u8) bool {
    for (allowed_basenames) |b| {
        if (builtin.os.tag == .windows) {
            if (std.ascii.eqlIgnoreCase(base, b)) return true;
        } else if (std.mem.eql(u8, base, b)) {
            return true;
        }
    }
    return false;
}

fn windowsPathLooksTrusted(path: []const u8) bool {
    // Accept System32 / SysWOW64 / PowerShell / Git usr\bin style installs.
    const needles = [_][]const u8{
        "\\system32\\",
        "\\syswow64\\",
        "\\powershell\\",
        "\\powershell\\7\\",
        "\\git\\bin\\",
        "\\git\\usr\\bin\\",
    };
    var lower_buf: [std.fs.max_path_bytes]u8 = undefined;
    if (path.len >= lower_buf.len) return false;
    for (path, 0..) |ch, i| {
        lower_buf[i] = std.ascii.toLower(ch);
    }
    const lower = lower_buf[0..path.len];
    for (needles) |n| {
        if (std.mem.indexOf(u8, lower, n) != null) return true;
    }
    return false;
}

test "rejects traversal and shell metacharacters" {
    try std.testing.expect(!isAllowed("../bin/zsh"));
    try std.testing.expect(!isAllowed("/bin/zsh;id"));
    try std.testing.expect(!isAllowed("/tmp/evil"));
    try std.testing.expect(!isAllowed(""));
}

test "allows standard unix shells when present" {
    if (builtin.os.tag == .windows) return;
    if (paths.pathExecutable("/bin/zsh")) {
        try std.testing.expect(isAllowed("/bin/zsh"));
    }
    if (paths.pathExecutable("/bin/bash")) {
        try std.testing.expect(isAllowed("/bin/bash"));
    }
    try std.testing.expectEqualStrings(sanitize("/tmp/not-a-shell"), paths.defaultShell());
}
