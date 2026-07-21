const c = @import("../c.zig").c;

pub fn set(window: ?*c.GLFWwindow, text: []const u8) void {
    if (window == null) return;
    // GLFW expects null-terminated; copy to stack if small, else truncate.
    var tmp: [8192]u8 = undefined;
    const n = @min(text.len, tmp.len - 1);
    @memcpy(tmp[0..n], text[0..n]);
    tmp[n] = 0;
    c.glfwSetClipboardString(window, &tmp);
}

pub fn get(window: ?*c.GLFWwindow) ?[:0]const u8 {
    if (window == null) return null;
    const ptr = c.glfwGetClipboardString(window);
    if (ptr == null) return null;
    return std.mem.span(ptr);
}

const std = @import("std");
