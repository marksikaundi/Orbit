//! Application icon helpers (Dock on macOS, window icon elsewhere).

const std = @import("std");
const builtin = @import("builtin");
const c = @import("../c.zig").c;

const icon_png = @embedFile("orbit-icon-256.png");

extern fn orbit_set_dock_icon_png(data: [*]const u8, len: usize) void;

/// Apply Orbit branding to the running process / window (best-effort).
pub fn apply(window: ?*c.GLFWwindow) void {
    if (builtin.os.tag == .macos) {
        orbit_set_dock_icon_png(icon_png.ptr, icon_png.len);
    }
    _ = window;
    // Window title-bar icons via glfwSetWindowIcon need decoded RGBA pixels;
    // the macOS Dock icon above is what replaces the generic "exec" mark.
}
