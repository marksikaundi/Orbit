const std = @import("std");
const c = @import("../c.zig").c;
const Window = @import("../window/window.zig").Window;
const Pty = @import("../pty/pty.zig").Pty;
const Screen = @import("../terminal/screen.zig").Screen;
const Parser = @import("../terminal/parser.zig").Parser;
const Renderer = @import("../renderer/renderer.zig").Renderer;
const bitmap = @import("../font/bitmap.zig");

pub const App = struct {
    allocator: std.mem.Allocator,
    window: Window,
    pty: Pty,
    screen: Screen,
    parser: Parser,
    renderer: Renderer,
    read_buf: [8192]u8 = undefined,

    pub fn create(allocator: std.mem.Allocator) !*App {
        const self = try allocator.create(App);
        errdefer allocator.destroy(self);

        const win_w: i32 = 800;
        const win_h: i32 = 500;
        var window = try Window.init("Orbit", win_w, win_h);
        errdefer window.deinit();

        const cols: u16 = @intCast(@max(1, @divTrunc(window.fb_width, @as(i32, @intCast(bitmap.glyph_width)))));
        const rows: u16 = @intCast(@max(1, @divTrunc(window.fb_height, @as(i32, @intCast(bitmap.glyph_height)))));

        var pty = try Pty.create(cols, rows);
        errdefer pty.deinit();

        var screen = try Screen.init(allocator, cols, rows);
        errdefer screen.deinit();

        var renderer = try Renderer.init(allocator);
        errdefer renderer.deinit();
        renderer.setFramebufferSize(window.fb_width, window.fb_height);

        self.* = .{
            .allocator = allocator,
            .window = window,
            .pty = pty,
            .screen = screen,
            .parser = Parser.init(),
            .renderer = renderer,
        };

        Window.active = self;
        Window.on_char = onChar;
        Window.on_key = onKey;

        return self;
    }

    pub fn destroy(self: *App) void {
        Window.active = null;
        Window.on_char = null;
        Window.on_key = null;
        self.renderer.deinit();
        self.screen.deinit();
        self.pty.deinit();
        self.window.deinit();
        self.allocator.destroy(self);
    }

    pub fn run(self: *App) !void {
        while (!self.window.shouldClose()) {
            Window.poll();
            self.handleResize();

            const n = self.pty.read(&self.read_buf);
            if (n > 0) {
                self.parser.feed(&self.screen, self.read_buf[0..n]);
            }

            try self.renderer.draw(&self.screen);
            self.screen.clearDirty();
            self.window.swap();
        }
    }

    fn handleResize(self: *App) void {
        const prev_w = self.window.fb_width;
        const prev_h = self.window.fb_height;
        self.window.updateFramebufferSize();
        if (self.window.fb_width == prev_w and self.window.fb_height == prev_h) return;

        self.renderer.setFramebufferSize(self.window.fb_width, self.window.fb_height);

        const cols: u16 = @intCast(@max(1, @divTrunc(self.window.fb_width, @as(i32, @intCast(bitmap.glyph_width)))));
        const rows: u16 = @intCast(@max(1, @divTrunc(self.window.fb_height, @as(i32, @intCast(bitmap.glyph_height)))));
        if (cols == self.screen.cols and rows == self.screen.rows) return;

        self.screen.resize(cols, rows) catch return;
        self.pty.resize(cols, rows);
    }

    fn onChar(ptr: *anyopaque, codepoint: u32) void {
        const self: *App = @ptrCast(@alignCast(ptr));
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(codepoint), &buf) catch return;
        self.pty.write(buf[0..len]);
    }

    fn onKey(ptr: *anyopaque, key: c_int, scancode: c_int, action: c_int, mods: c_int) void {
        _ = scancode;
        _ = mods;
        if (action != c.GLFW_PRESS and action != c.GLFW_REPEAT) return;
        const self: *App = @ptrCast(@alignCast(ptr));

        switch (key) {
            c.GLFW_KEY_ENTER, c.GLFW_KEY_KP_ENTER => self.pty.write("\r"),
            c.GLFW_KEY_BACKSPACE => self.pty.write(&.{0x7F}),
            c.GLFW_KEY_TAB => self.pty.write("\t"),
            c.GLFW_KEY_ESCAPE => self.pty.write("\x1b"),
            c.GLFW_KEY_UP => self.pty.write("\x1b[A"),
            c.GLFW_KEY_DOWN => self.pty.write("\x1b[B"),
            c.GLFW_KEY_RIGHT => self.pty.write("\x1b[C"),
            c.GLFW_KEY_LEFT => self.pty.write("\x1b[D"),
            c.GLFW_KEY_HOME => self.pty.write("\x1b[H"),
            c.GLFW_KEY_END => self.pty.write("\x1b[F"),
            c.GLFW_KEY_DELETE => self.pty.write("\x1b[3~"),
            else => {},
        }
    }
};
