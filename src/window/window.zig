const std = @import("std");
const c = @import("../c.zig").c;
const app_icon = @import("../platform/app_icon.zig");

pub const Window = struct {
    handle: ?*c.GLFWwindow = null,
    width: i32 = 800,
    height: i32 = 500,
    fb_width: i32 = 800,
    fb_height: i32 = 500,
    resized: bool = false,

    pub var active: ?*anyopaque = null;
    pub var on_char: ?*const fn (*anyopaque, u32) void = null;
    pub var on_key: ?*const fn (*anyopaque, c_int, c_int, c_int, c_int) void = null;
    pub var on_mouse_button: ?*const fn (*anyopaque, c_int, c_int, c_int) void = null;
    pub var on_cursor_pos: ?*const fn (*anyopaque, f64, f64) void = null;
    pub var on_scroll: ?*const fn (*anyopaque, f64, f64) void = null;

    pub fn init(title: [:0]const u8, width: i32, height: i32, opacity: f32) !Window {
        if (c.glfwInit() == c.GLFW_FALSE) return error.GlfwInitFailed;
        errdefer c.glfwTerminate();

        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
        c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
        c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GLFW_TRUE);
        if (opacity < 0.999) {
            c.glfwWindowHint(c.GLFW_TRANSPARENT_FRAMEBUFFER, c.GLFW_TRUE);
        }

        const handle = c.glfwCreateWindow(width, height, title, null, null);
        if (handle == null) return error.WindowCreateFailed;

        c.glfwMakeContextCurrent(handle);
        c.glfwSwapInterval(1);
        if (opacity < 0.999) {
            c.glfwSetWindowOpacity(handle, opacity);
        }

        // Replace the generic macOS "exec" Dock icon with Orbit's.
        app_icon.apply(handle);

        var self: Window = .{
            .handle = handle,
            .width = width,
            .height = height,
        };
        self.updateFramebufferSize();

        _ = c.glfwSetFramebufferSizeCallback(handle, framebufferSizeCallback);
        _ = c.glfwSetCharCallback(handle, charCallback);
        _ = c.glfwSetKeyCallback(handle, keyCallback);
        _ = c.glfwSetMouseButtonCallback(handle, mouseButtonCallback);
        _ = c.glfwSetCursorPosCallback(handle, cursorPosCallback);
        _ = c.glfwSetScrollCallback(handle, scrollCallback);

        return self;
    }

    pub fn deinit(self: *Window) void {
        if (self.handle) |h| {
            c.glfwDestroyWindow(h);
        }
        c.glfwTerminate();
        self.* = undefined;
    }

    pub fn shouldClose(self: *const Window) bool {
        return c.glfwWindowShouldClose(self.handle) == c.GLFW_TRUE;
    }

    /// Ask the window to close (Cmd+Q / Quit). Honors the red traffic-light button path.
    pub fn requestClose(self: *Window) void {
        if (self.handle) |h| {
            c.glfwSetWindowShouldClose(h, c.GLFW_TRUE);
        }
    }

    pub fn poll() void {
        c.glfwPollEvents();
    }

    pub fn swap(self: *Window) void {
        c.glfwSwapBuffers(self.handle);
    }

    pub fn setTitle(self: *Window, title: [:0]const u8) void {
        c.glfwSetWindowTitle(self.handle, title);
    }

    pub fn updateFramebufferSize(self: *Window) void {
        var w: c_int = 0;
        var h: c_int = 0;
        c.glfwGetFramebufferSize(self.handle, &w, &h);
        self.fb_width = w;
        self.fb_height = h;
        var ww: c_int = 0;
        var wh: c_int = 0;
        c.glfwGetWindowSize(self.handle, &ww, &wh);
        self.width = ww;
        self.height = wh;
    }

    /// Convert window coords to framebuffer coords.
    pub fn contentScale(self: *const Window) f32 {
        if (self.width <= 0) return 1.0;
        return @as(f32, @floatFromInt(self.fb_width)) / @as(f32, @floatFromInt(self.width));
    }

    pub fn windowToFb(self: *const Window, wx: f64, wy: f64) struct { x: i32, y: i32 } {
        const sx = if (self.width > 0) @as(f64, @floatFromInt(self.fb_width)) / @as(f64, @floatFromInt(self.width)) else 1.0;
        const sy = if (self.height > 0) @as(f64, @floatFromInt(self.fb_height)) / @as(f64, @floatFromInt(self.height)) else 1.0;
        return .{
            .x = @intFromFloat(wx * sx),
            .y = @intFromFloat(wy * sy),
        };
    }

    fn framebufferSizeCallback(win: ?*c.GLFWwindow, w: c_int, h: c_int) callconv(.c) void {
        _ = win;
        _ = w;
        _ = h;
    }

    fn charCallback(win: ?*c.GLFWwindow, codepoint: c_uint) callconv(.c) void {
        _ = win;
        if (active) |ptr| {
            if (on_char) |cb| cb(ptr, codepoint);
        }
    }

    fn keyCallback(win: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.c) void {
        _ = win;
        if (active) |ptr| {
            if (on_key) |cb| cb(ptr, key, scancode, action, mods);
        }
    }

    fn mouseButtonCallback(win: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.c) void {
        _ = win;
        if (active) |ptr| {
            if (on_mouse_button) |cb| cb(ptr, button, action, mods);
        }
    }

    fn cursorPosCallback(win: ?*c.GLFWwindow, x: f64, y: f64) callconv(.c) void {
        _ = win;
        if (active) |ptr| {
            if (on_cursor_pos) |cb| cb(ptr, x, y);
        }
    }

    fn scrollCallback(win: ?*c.GLFWwindow, xoff: f64, yoff: f64) callconv(.c) void {
        _ = win;
        if (active) |ptr| {
            if (on_scroll) |cb| cb(ptr, xoff, yoff);
        }
    }
};
