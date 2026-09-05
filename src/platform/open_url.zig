//! Open an http(s) URL in the system browser.

const std = @import("std");
const builtin = @import("builtin");

pub fn open(allocator: std.mem.Allocator, io: std.Io, url: []const u8) void {
    if (!(std.mem.startsWith(u8, url, "https://") or std.mem.startsWith(u8, url, "http://"))) return;
    if (url.len > 512) return;

    const argv: []const []const u8 = if (builtin.os.tag == .macos)
        &.{ "open", url }
    else if (builtin.os.tag == .linux)
        &.{ "xdg-open", url }
    else if (builtin.os.tag == .windows)
        &.{ "cmd", "/c", "start", "", url }
    else
        return;

    const result = std.process.run(allocator, io, .{
        .argv = argv,
        .stdout_limit = .limited(64),
        .stderr_limit = .limited(64),
    }) catch return;
    allocator.free(result.stdout);
    allocator.free(result.stderr);
}
