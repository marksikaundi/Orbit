//! Orbit source-tree path used for global `zig build run` / `orbit` launcher.
//! Written to ~/.config/orbit/source_root on launch; also set as ORBIT_SOURCE_ROOT in PTYs.

const std = @import("std");
const build_options = @import("build_options");

pub const compiled_source_root: []const u8 = build_options.source_root;

/// Absolute Orbit repo path when configured (compile-time path if still valid).
pub fn resolve(allocator: std.mem.Allocator, io: std.Io) ?[]u8 {
    if (compiled_source_root.len > 0 and buildZigExists(compiled_source_root)) {
        return allocator.dupe(u8, compiled_source_root) catch null;
    }
    const home = std.c.getenv("HOME") orelse return null;
    const path = std.fmt.allocPrint(allocator, "{s}/.config/orbit/source_root", .{std.mem.span(home)}) catch return null;
    defer allocator.free(path);
    const file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return null;
    defer file.close(io);
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    var reader = file.reader(io, &buf);
    const data = reader.interface.allocRemaining(allocator, .limited(std.fs.max_path_bytes)) catch return null;
    defer allocator.free(data);
    const trimmed = std.mem.trim(u8, data, " \t\r\n");
    if (trimmed.len == 0 or !buildZigExists(trimmed)) return null;
    return allocator.dupe(u8, trimmed) catch null;
}

/// Persist the compile-time source root so shell integration works outside Orbit.
pub fn ensureRecorded(allocator: std.mem.Allocator, io: std.Io) void {
    if (compiled_source_root.len == 0 or !buildZigExists(compiled_source_root)) return;
    const home = std.c.getenv("HOME") orelse return;
    const home_slice = std.mem.span(home);
    const dir_path = std.fmt.allocPrint(allocator, "{s}/.config/orbit", .{home_slice}) catch return;
    defer allocator.free(dir_path);
    ensureDir(dir_path);

    const file_path = std.fmt.allocPrint(allocator, "{s}/source_root", .{dir_path}) catch return;
    defer allocator.free(file_path);
    const file = std.Io.Dir.createFileAbsolute(io, file_path, .{}) catch return;
    defer file.close(io);
    file.writeStreamingAll(io, compiled_source_root) catch {};
    file.writeStreamingAll(io, "\n") catch {};
}

fn buildZigExists(dir: []const u8) bool {
    var path_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    const suffix = "/build.zig";
    if (dir.len + suffix.len >= path_buf.len) return false;
    @memcpy(path_buf[0..dir.len], dir);
    @memcpy(path_buf[dir.len..][0..suffix.len], suffix);
    const total = dir.len + suffix.len;
    path_buf[total] = 0;
    return std.c.access(path_buf[0..total :0], 0) == 0; // F_OK
}

fn ensureDir(path: []const u8) void {
    var buf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= buf.len) return;
    var i: usize = 1;
    while (i <= path.len) : (i += 1) {
        if (i < path.len and path[i] != '/') continue;
        @memcpy(buf[0..i], path[0..i]);
        buf[i] = 0;
        _ = std.c.mkdir(buf[0..i :0], 0o755);
    }
}
