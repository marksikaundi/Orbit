//! Best-effort desktop notification when Orbit is in the background.

const std = @import("std");
const builtin = @import("builtin");
const c = @import("../c.zig").c;

pub fn isFocused(window: ?*c.GLFWwindow) bool {
    if (window == null) return true;
    return c.glfwGetWindowAttrib(window, c.GLFW_FOCUSED) == c.GLFW_TRUE;
}

pub fn send(allocator: std.mem.Allocator, io: std.Io, title: []const u8, body: []const u8) void {
    if (builtin.os.tag == .macos) {
        macNotify(allocator, io, title, body);
    } else if (builtin.os.tag == .linux) {
        linuxNotify(allocator, io, title, body);
    }
}

fn macNotify(allocator: std.mem.Allocator, io: std.Io, title: []const u8, body: []const u8) void {
    var tbuf: [80]u8 = undefined;
    var bbuf: [80]u8 = undefined;
    const t = sanitize(title, &tbuf);
    const b = sanitize(body, &bbuf);
    var script: [200]u8 = undefined;
    const line = std.fmt.bufPrint(
        &script,
        "display notification \"{s}\" with title \"{s}\"",
        .{ b, t },
    ) catch return;
    fire(allocator, io, &.{ "/usr/bin/osascript", "-e", line });
}

fn linuxNotify(allocator: std.mem.Allocator, io: std.Io, title: []const u8, body: []const u8) void {
    var tbuf: [80]u8 = undefined;
    var bbuf: [80]u8 = undefined;
    const t = sanitize(title, &tbuf);
    const b = sanitize(body, &bbuf);
    fire(allocator, io, &.{ "notify-send", t, b });
}

fn fire(allocator: std.mem.Allocator, io: std.Io, argv: []const []const u8) void {
    const result = std.process.run(allocator, io, .{
        .argv = argv,
        .stdout_limit = .limited(64),
        .stderr_limit = .limited(64),
    }) catch return;
    allocator.free(result.stdout);
    allocator.free(result.stderr);
}

fn sanitize(s: []const u8, buf: []u8) []const u8 {
    var n: usize = 0;
    for (s) |ch| {
        if (n >= buf.len) break;
        if (ch == '"' or ch == '\\' or ch == '\'' or ch < 32) continue;
        buf[n] = ch;
        n += 1;
    }
    return buf[0..n];
}
