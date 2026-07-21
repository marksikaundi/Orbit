const std = @import("std");
const c = @import("../c.zig").c;
const Window = @import("../window/window.zig").Window;
const Renderer = @import("../renderer/renderer.zig").Renderer;
const Session = @import("../terminal/session.zig").Session;
const Tabs = @import("../ui/tabs.zig").Tabs;
const layout_mod = @import("../ui/layout.zig");
const Rect = layout_mod.Rect;
const Search = @import("../ui/search.zig").Search;
const Config = @import("../config/config.zig").Config;
const clipboard = @import("../clipboard/clipboard.zig");
const bitmap = @import("../font/bitmap.zig");
const Color = @import("../terminal/cell.zig").Color;

pub const App = struct {
    allocator: std.mem.Allocator,
    window: Window,
    renderer: Renderer,
    tabs: Tabs,
    config: Config,
    search: Search = .{},
    mouse_x: f64 = 0,
    mouse_y: f64 = 0,

    pub fn create(allocator: std.mem.Allocator, io: std.Io) !*App {
        const self = try allocator.create(App);
        errdefer allocator.destroy(self);

        var config = Config.load(allocator, io);
        const theme = config.theme();

        var window = try Window.init("Orbit", config.window_width, config.window_height, config.opacity);
        errdefer window.deinit();

        var renderer = try Renderer.init(allocator);
        errdefer renderer.deinit();
        renderer.setFramebufferSize(window.fb_width, window.fb_height);
        renderer.setTheme(theme);
        renderer.opacity = config.opacity;

        var tabs = Tabs.init(allocator);
        errdefer tabs.deinit();

        const content = contentRect(window.fb_width, window.fb_height);
        const cols, const rows = gridSize(content.w, content.h);
        const session = try Session.create(allocator, cols, rows, "Shell");
        session.setTheme(theme.foreground, theme.background);
        session.setScrollback(config.scrollback);
        try tabs.add("Shell", session);

        self.* = .{
            .allocator = allocator,
            .window = window,
            .renderer = renderer,
            .tabs = tabs,
            .config = config,
        };

        Window.active = self;
        Window.on_char = onChar;
        Window.on_key = onKey;
        Window.on_mouse_button = onMouseButton;
        Window.on_cursor_pos = onCursorPos;
        Window.on_scroll = onScroll;

        return self;
    }

    pub fn destroy(self: *App) void {
        Window.active = null;
        Window.on_char = null;
        Window.on_key = null;
        Window.on_mouse_button = null;
        Window.on_cursor_pos = null;
        Window.on_scroll = null;
        self.tabs.deinit();
        self.renderer.deinit();
        self.window.deinit();
        self.config.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn run(self: *App) !void {
        while (!self.window.shouldClose()) {
            Window.poll();
            self.handleResize();
            self.tabs.tickAll();
            try self.draw();
            self.window.swap();
        }
    }

    fn contentRect(fb_w: i32, fb_h: i32) Rect {
        return .{
            .x = 0,
            .y = Tabs.bar_height,
            .w = fb_w,
            .h = @max(1, fb_h - Tabs.bar_height),
        };
    }

    fn gridSize(w: i32, h: i32) struct { u16, u16 } {
        const cols: u16 = @intCast(@max(1, @divTrunc(w, @as(i32, @intCast(bitmap.glyph_width)))));
        const rows: u16 = @intCast(@max(1, @divTrunc(h, @as(i32, @intCast(bitmap.glyph_height)))));
        return .{ cols, rows };
    }

    fn handleResize(self: *App) void {
        const prev_w = self.window.fb_width;
        const prev_h = self.window.fb_height;
        self.window.updateFramebufferSize();
        if (self.window.fb_width == prev_w and self.window.fb_height == prev_h) return;

        self.renderer.setFramebufferSize(self.window.fb_width, self.window.fb_height);
        self.resizeAllSessions();
    }

    fn resizeAllSessions(self: *App) void {
        const tab = self.tabs.current() orelse return;
        const bounds = contentRect(self.window.fb_width, self.window.fb_height);
        const Ctx = struct {
            fn cb(_: void, session: *Session, r: Rect) void {
                const cols, const rows = gridSize(r.w, r.h);
                if (cols != session.screen.cols or rows != session.screen.rows) {
                    session.resize(cols, rows);
                }
            }
        };
        tab.layout.forEachLeaf(bounds, void, {}, Ctx.cb);
    }

    fn draw(self: *App) !void {
        self.renderer.clearBackground();

        // Tab bar
        try self.renderer.drawRect(0, 0, self.window.fb_width, Tabs.bar_height, Color.rgb(28, 32, 40), 1.0);
        var x: i32 = 8;
        for (self.tabs.items.items, 0..) |tab, i| {
            const active = i == self.tabs.active;
            const bg = if (active) Color.rgb(50, 70, 100) else Color.rgb(35, 40, 50);
            const label_w: i32 = @intCast(@min(tab.title.len, 16) * bitmap.glyph_width + 16);
            try self.renderer.drawRect(x, 4, label_w, Tabs.bar_height - 8, bg, 1.0);
            const fg = if (active) Color.rgb(240, 245, 255) else Color.rgb(160, 170, 180);
            try self.renderer.drawText(x + 8, 8, tab.title[0..@min(tab.title.len, 16)], fg);
            x += label_w + 4;
        }

        const tab = self.tabs.current() orelse return;
        const bounds = contentRect(self.window.fb_width, self.window.fb_height);

        const DrawCtx = struct {
            app: *App,
            fn cb(ctx: *@This(), session: *Session, r: Rect) void {
                const cols, const rows = gridSize(r.w, r.h);
                if (cols != session.screen.cols or rows != session.screen.rows) {
                    session.resize(cols, rows);
                }
                var hl_row: ?u16 = null;
                var hl_col: ?u16 = null;
                var hl_len: u16 = 0;
                if (ctx.app.search.active and session == ctx.app.tabs.focusedSession()) {
                    hl_row = ctx.app.search.match_row;
                    hl_col = ctx.app.search.match_col;
                    hl_len = @intCast(ctx.app.search.query_len);
                }
                ctx.app.renderer.drawScreen(
                    &session.screen,
                    &session.selection,
                    r.x,
                    r.y,
                    hl_row,
                    hl_col,
                    hl_len,
                ) catch {};

                // Pane border if split / focused
                if (session == ctx.app.tabs.focusedSession()) {
                    ctx.app.renderer.drawRect(r.x, r.y, r.w, 2, Color.rgb(80, 140, 220), 0.8) catch {};
                }
            }
        };
        var dctx: DrawCtx = .{ .app = self };
        tab.layout.forEachLeaf(bounds, *DrawCtx, &dctx, DrawCtx.cb);

        // Search bar
        if (self.search.active) {
            const bar_y = self.window.fb_height - 32;
            try self.renderer.drawRect(0, bar_y, self.window.fb_width, 32, Color.rgb(30, 40, 55), 0.95);
            var label_buf: [160]u8 = undefined;
            const label = std.fmt.bufPrint(&label_buf, "Search: {s}", .{self.search.querySlice()}) catch "Search:";
            try self.renderer.drawText(8, bar_y + 8, label, Color.rgb(230, 235, 240));
        }
    }

    fn focused(self: *App) ?*Session {
        return self.tabs.focusedSession();
    }

    fn onChar(ptr: *anyopaque, codepoint: u32) void {
        const self: *App = @ptrCast(@alignCast(ptr));
        if (self.search.active) {
            self.search.inputChar(codepoint);
            if (self.focused()) |s| self.search.findNext(&s.screen);
            return;
        }
        const session = self.focused() orelse return;
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(codepoint), &buf) catch return;
        session.write(buf[0..len]);
    }

    fn onKey(ptr: *anyopaque, key: c_int, scancode: c_int, action: c_int, mods: c_int) void {
        _ = scancode;
        if (action != c.GLFW_PRESS and action != c.GLFW_REPEAT) return;
        const self: *App = @ptrCast(@alignCast(ptr));
        const ctrl = (mods & c.GLFW_MOD_CONTROL) != 0;
        const shift = (mods & c.GLFW_MOD_SHIFT) != 0;
        const super = (mods & c.GLFW_MOD_SUPER) != 0;

        // Search mode keys
        if (self.search.active) {
            if (key == c.GLFW_KEY_ESCAPE) {
                self.search.close();
                return;
            }
            if (key == c.GLFW_KEY_BACKSPACE) {
                self.search.backspace();
                return;
            }
            if (key == c.GLFW_KEY_ENTER) {
                if (self.focused()) |s| self.search.findNext(&s.screen);
                return;
            }
            return;
        }

        // App shortcuts
        if (ctrl and shift) {
            switch (key) {
                c.GLFW_KEY_T => {
                    self.newTab() catch {};
                    return;
                },
                c.GLFW_KEY_W => {
                    self.tabs.closeActive();
                    return;
                },
                c.GLFW_KEY_D => {
                    self.splitPane(.horizontal) catch {};
                    return;
                },
                c.GLFW_KEY_E => {
                    self.splitPane(.vertical) catch {};
                    return;
                },
                c.GLFW_KEY_RIGHT_BRACKET => {
                    self.tabs.next();
                    return;
                },
                c.GLFW_KEY_LEFT_BRACKET => {
                    self.tabs.prev();
                    return;
                },
                c.GLFW_KEY_F => {
                    self.search.open();
                    return;
                },
                else => {},
            }
        }

        if (ctrl and key == c.GLFW_KEY_TAB) {
            if (shift) self.tabs.prev() else self.tabs.next();
            return;
        }

        if ((ctrl or super) and key == c.GLFW_KEY_C and shift) {
            self.copySelection();
            return;
        }
        if ((ctrl or super) and key == c.GLFW_KEY_V and shift) {
            self.pasteClipboard();
            return;
        }

        // Focus next pane
        if (ctrl and key == c.GLFW_KEY_PAGE_DOWN) {
            if (self.tabs.current()) |tab| tab.layout.focusNext();
            return;
        }

        const session = self.focused() orelse return;
        switch (key) {
            c.GLFW_KEY_ENTER, c.GLFW_KEY_KP_ENTER => session.write("\r"),
            c.GLFW_KEY_BACKSPACE => session.write(&.{0x7F}),
            c.GLFW_KEY_TAB => session.write("\t"),
            c.GLFW_KEY_ESCAPE => session.write("\x1b"),
            c.GLFW_KEY_UP => session.write("\x1b[A"),
            c.GLFW_KEY_DOWN => session.write("\x1b[B"),
            c.GLFW_KEY_RIGHT => session.write("\x1b[C"),
            c.GLFW_KEY_LEFT => session.write("\x1b[D"),
            c.GLFW_KEY_HOME => session.write("\x1b[H"),
            c.GLFW_KEY_END => session.write("\x1b[F"),
            c.GLFW_KEY_DELETE => session.write("\x1b[3~"),
            c.GLFW_KEY_PAGE_UP => session.screen.scrollView(10),
            c.GLFW_KEY_PAGE_DOWN => session.screen.scrollView(-10),
            else => {},
        }
    }

    fn newTab(self: *App) !void {
        const bounds = contentRect(self.window.fb_width, self.window.fb_height);
        const cols, const rows = gridSize(bounds.w, bounds.h);
        const theme = self.config.theme();
        var title_buf: [32]u8 = undefined;
        const title = std.fmt.bufPrint(&title_buf, "Shell {d}", .{self.tabs.items.items.len + 1}) catch "Shell";
        const session = try Session.create(self.allocator, cols, rows, title);
        session.setTheme(theme.foreground, theme.background);
        session.setScrollback(self.config.scrollback);
        try self.tabs.add(title, session);
    }

    fn splitPane(self: *App, dir: layout_mod.Dir) !void {
        const tab = self.tabs.current() orelse return;
        const bounds = contentRect(self.window.fb_width, self.window.fb_height);
        // Approximate half size for new pane
        const half = if (dir == .horizontal)
            Rect{ .x = 0, .y = 0, .w = @divTrunc(bounds.w, 2), .h = bounds.h }
        else
            Rect{ .x = 0, .y = 0, .w = bounds.w, .h = @divTrunc(bounds.h, 2) };
        const cols, const rows = gridSize(half.w, half.h);
        const theme = self.config.theme();
        const session = try Session.create(self.allocator, cols, rows, "Split");
        session.setTheme(theme.foreground, theme.background);
        session.setScrollback(self.config.scrollback);
        try tab.layout.splitFocused(dir, session);
        self.resizeAllSessions();
    }

    fn copySelection(self: *App) void {
        const session = self.focused() orelse return;
        var buf: [64 * 1024]u8 = undefined;
        const n = session.selection.copyText(&session.screen, &buf);
        if (n > 0) clipboard.set(self.window.handle, buf[0..n]);
    }

    fn pasteClipboard(self: *App) void {
        const session = self.focused() orelse return;
        const text = clipboard.get(self.window.handle) orelse return;
        session.write(text);
    }

    fn onMouseButton(ptr: *anyopaque, button: c_int, action: c_int, mods: c_int) void {
        _ = mods;
        const self: *App = @ptrCast(@alignCast(ptr));
        const tab = self.tabs.current() orelse return;
        const bounds = contentRect(self.window.fb_width, self.window.fb_height);
        const fb = self.window.windowToFb(self.mouse_x, self.mouse_y);

        if (button == c.GLFW_MOUSE_BUTTON_LEFT) {
            if (action == c.GLFW_PRESS) {
                if (tab.layout.sessionAt(bounds, fb.x, fb.y)) |session| {
                    tab.layout.focused = session;
                    const local_x = fb.x - bounds.x; // approximate — need pane origin
                    // Use hit rect properly
                    const Hit = struct {
                        px: i32,
                        py: i32,
                        session: ?*Session = null,
                        rect: Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
                        fn cb(ctx: *@This(), s: *Session, r: Rect) void {
                            if (ctx.px >= r.x and ctx.px < r.x + r.w and ctx.py >= r.y and ctx.py < r.y + r.h) {
                                ctx.session = s;
                                ctx.rect = r;
                            }
                        }
                    };
                    var hit: Hit = .{ .px = fb.x, .py = fb.y };
                    tab.layout.forEachLeaf(bounds, *Hit, &hit, Hit.cb);
                    if (hit.session) |s| {
                        tab.layout.focused = s;
                        const col: u16 = @intCast(@max(0, @divTrunc(fb.x - hit.rect.x, @as(i32, @intCast(bitmap.glyph_width)))));
                        const row: u16 = @intCast(@max(0, @divTrunc(fb.y - hit.rect.y, @as(i32, @intCast(bitmap.glyph_height)))));
                        _ = local_x;
                        s.selection.begin(@min(col, s.screen.cols -| 1), @min(row, s.screen.rows -| 1));
                    }
                }
            } else if (action == c.GLFW_RELEASE) {
                if (self.focused()) |s| {
                    s.selection.finish();
                    // Auto-copy on selection
                    if (s.selection.active) self.copySelection();
                }
            }
        }
    }

    fn onCursorPos(ptr: *anyopaque, x: f64, y: f64) void {
        const self: *App = @ptrCast(@alignCast(ptr));
        self.mouse_x = x;
        self.mouse_y = y;
        const session = self.focused() orelse return;
        if (!session.selection.selecting) return;

        const tab = self.tabs.current() orelse return;
        const bounds = contentRect(self.window.fb_width, self.window.fb_height);
        const fb = self.window.windowToFb(x, y);

        const Hit = struct {
            px: i32,
            py: i32,
            target: *Session,
            rect: ?Rect = null,
            fn cb(ctx: *@This(), s: *Session, r: Rect) void {
                if (s == ctx.target) ctx.rect = r;
            }
        };
        var hit: Hit = .{ .px = fb.x, .py = fb.y, .target = session };
        tab.layout.forEachLeaf(bounds, *Hit, &hit, Hit.cb);
        if (hit.rect) |r| {
            const col: u16 = @intCast(@max(0, @divTrunc(fb.x - r.x, @as(i32, @intCast(bitmap.glyph_width)))));
            const row: u16 = @intCast(@max(0, @divTrunc(fb.y - r.y, @as(i32, @intCast(bitmap.glyph_height)))));
            session.selection.update(@min(col, session.screen.cols -| 1), @min(row, session.screen.rows -| 1));
            session.screen.dirty = true;
        }
    }

    fn onScroll(ptr: *anyopaque, xoff: f64, yoff: f64) void {
        _ = xoff;
        const self: *App = @ptrCast(@alignCast(ptr));
        const session = self.focused() orelse return;
        const lines: i32 = @intFromFloat(yoff * 3.0);
        session.screen.scrollView(lines);
    }
};
