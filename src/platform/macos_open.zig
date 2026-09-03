//! macOS folder-open Apple Events (`open -a Orbit.app /project`).

const std = @import("std");
const builtin = @import("builtin");

const Mac = if (builtin.os.tag == .macos) struct {
    extern fn orbit_macos_install_open_handler() void;
    extern fn orbit_macos_take_open_path(out: [*]u8, cap: usize) c_int;
} else struct {};

pub fn install() void {
    if (comptime builtin.os.tag == .macos) {
        Mac.orbit_macos_install_open_handler();
    }
}

/// Pop one pending folder path. `buf` must be at least 1 byte.
pub fn take(buf: []u8) ?[]u8 {
    if (comptime builtin.os.tag != .macos) return null;
    if (buf.len == 0) return null;
    const n = Mac.orbit_macos_take_open_path(buf.ptr, buf.len);
    if (n <= 0) return null;
    return buf[0..@intCast(n)];
}
