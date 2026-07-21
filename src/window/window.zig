const std = @import("std");
const c = @import("../c.zig").c;

pub const Window = struct {
    handle: ?*c.GLFWwindow = null,
    width: i32 = 800,
    height: i32 = 500,
    fb_width: i32 = 800,
    fb_height: i32 = 500,
    resized: bool = false,

    /// User pointer for input callbacks (set by App).
    pub var active: ?*anyopaque = null;
    pub var on_char: ?*const fn (*anyopaque, u32) void = null;
    pub var on_key: ?*const fn (*anyopaque, c_int, c_int, c_int, c_int) void = null;

    pub fn init(title: [:0]const u8, width: i32, height: i32) !Window {
        if (c.glfwInit() == c.GLFW_FALSE) return error.GlfwInitFailed;
        errdefer c.glfwTerminate();

        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
        c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
        c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GLFW_TRUE);

        const handle = c.glfwCreateWindow(width, height, title, null, null);
        if (handle == null) return error.WindowCreateFailed;

        c.glfwMakeContextCurrent(handle);
        c.glfwSwapInterval(1);

        var self: Window = .{
            .handle = handle,
            .width = width,
            .height = height,
        };
        self.updateFramebufferSize();

        _ = c.glfwSetFramebufferSizeCallback(handle, framebufferSizeCallback);
        _ = c.glfwSetCharCallback(handle, charCallback);
        _ = c.glfwSetKeyCallback(handle, keyCallback);

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

    pub fn poll() void {
        c.glfwPollEvents();
    }

    pub fn swap(self: *Window) void {
        c.glfwSwapBuffers(self.handle);
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

    fn framebufferSizeCallback(win: ?*c.GLFWwindow, w: c_int, h: c_int) callconv(.c) void {
        _ = win;
        _ = w;
        _ = h;
        // App polls size each frame; mark via global by storing on window user pointer if needed.
        // For Phase 1 we re-query each frame.
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
};
