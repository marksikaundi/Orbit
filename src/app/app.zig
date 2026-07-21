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
const WsManager = @import("../workspace/workspace.zig").Manager;
const clipboard = @import("../clipboard/clipboard.zig");
const bitmap = @import("../font/bitmap.zig");
const Color = @import("../terminal/cell.zig").Color;

const UiMode = enum { normal, search, ws_picker, ws_save };

pub const App = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    window: Window,
    renderer: Renderer,
    tabs: Tabs,
    config: Config,
    workspaces: WsManager,
    search: Search = .{},
    ui: UiMode = .normal,
    picker_index: usize = 0,
    save_name: [64]u8 = undefined,
    save_name_len: usize = 0,
    status_msg: [96]u8 = undefined,
    status_len: usize = 0,
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

        var workspaces = try WsManager.init(allocator, io);
        errdefer workspaces.deinit();

        const content = contentRect(window.fb_width, window.fb_height);
        const cols, const rows = gridSize(content.w, content.h);
        const session = try Session.create(allocator, cols, rows, "Shell");
        session.setTheme(theme.foreground, theme.background);
        session.setScrollback(config.scrollback);
        try tabs.add("Shell", session);

        self.* = .{
            .allocator = allocator,
            .io = io,
            .window = window,
            .renderer = renderer,
            .tabs = tabs,
            .config = config,
            .workspaces = workspaces,
        };

        Window.active = self;
        Window.on_char = onChar;
        Window.on_key = onKey;
        Window.on_mouse_button = onMouseButton;
        Window.on_cursor_pos = onCursorPos;
        Window.on_scroll = onScroll;

        self.updateWindowTitle();
        return self;
    }

    pub fn destroy(self: *App) void {
        Window.active = null;
        Window.on_char = null;
        Window.on_key = null;
        Window.on_mouse_button = null;
        Window.on_cursor_pos = null;
        Window.on_scroll = null;
        self.workspaces.deinit();
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

    fn setStatus(self: *App, msg: []const u8) void {
        const n = @min(msg.len, self.status_msg.len);
        @memcpy(self.status_msg[0..n], msg[0..n]);
        self.status_len = n;
    }

    fn updateWindowTitle(self: *App) void {
        var buf: [128]u8 = undefined;
        const title = if (self.workspaces.current_name) |n|
            std.fmt.bufPrint(&buf, "Orbit — {s}", .{n}) catch "Orbit"
        else
            "Orbit";
        var zbuf: [129]u8 = undefined;
        const n = @min(title.len, zbuf.len - 1);
        @memcpy(zbuf[0..n], title[0..n]);
        zbuf[n] = 0;
        self.window.setTitle(zbuf[0..n :0]);
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

        // Workspace badge on the right
        if (self.workspaces.current_name) |wn| {
            const label = wn[0..@min(wn.len, 20)];
            const lw: i32 = @intCast(label.len * bitmap.glyph_width + 16);
            const bx = self.window.fb_width - lw - 8;
            try self.renderer.drawRect(bx, 4, lw, Tabs.bar_height - 8, Color.rgb(40, 90, 70), 1.0);
            try self.renderer.drawText(bx + 8, 8, label, Color.rgb(200, 240, 210));
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
                if (ctx.app.ui == .search and session == ctx.app.tabs.focusedSession()) {
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

                if (session == ctx.app.tabs.focusedSession()) {
                    ctx.app.renderer.drawRect(r.x, r.y, r.w, 2, Color.rgb(80, 140, 220), 0.8) catch {};
                }
            }
        };
        var dctx: DrawCtx = .{ .app = self };
        tab.layout.forEachLeaf(bounds, *DrawCtx, &dctx, DrawCtx.cb);

        if (self.ui == .search) {
            const bar_y = self.window.fb_height - 32;
            try self.renderer.drawRect(0, bar_y, self.window.fb_width, 32, Color.rgb(30, 40, 55), 0.95);
            var label_buf: [160]u8 = undefined;
            const label = std.fmt.bufPrint(&label_buf, "Search: {s}", .{self.search.querySlice()}) catch "Search:";
            try self.renderer.drawText(8, bar_y + 8, label, Color.rgb(230, 235, 240));
        }

        if (self.ui == .ws_picker) {
            try self.drawWorkspacePicker();
        }
        if (self.ui == .ws_save) {
            try self.drawSavePrompt();
        }
        if (self.status_len > 0 and self.ui == .normal) {
            const bar_y = self.window.fb_height - 24;
            try self.renderer.drawRect(0, bar_y, self.window.fb_width, 24, Color.rgb(25, 35, 30), 0.9);
            try self.renderer.drawText(8, bar_y + 4, self.status_msg[0..self.status_len], Color.rgb(180, 220, 180));
        }
    }

    fn drawWorkspacePicker(self: *App) !void {
        const w: i32 = 420;
        const row_h: i32 = 22;
        const header: i32 = 36;
        const h: i32 = header + @as(i32, @intCast(@max(1, self.workspaces.names.items.len))) * row_h + 48;
        const x = @divTrunc(self.window.fb_width - w, 2);
        const y = @divTrunc(self.window.fb_height - h, 2);
        try self.renderer.drawRect(x, y, w, h, Color.rgb(24, 28, 36), 0.97);
        try self.renderer.drawText(x + 16, y + 12, "Open Workspace", Color.rgb(230, 235, 240));
        try self.renderer.drawText(x + 16, y + h - 28, "Enter open  |  Esc close  |  Del delete", Color.rgb(140, 150, 160));

        if (self.workspaces.names.items.len == 0) {
            try self.renderer.drawText(x + 16, y + header + 8, "(no workspaces yet — Ctrl+Shift+S to save)", Color.rgb(160, 170, 180));
            return;
        }
        for (self.workspaces.names.items, 0..) |name, i| {
            const ry = y + header + @as(i32, @intCast(i)) * row_h;
            if (i == self.picker_index) {
                try self.renderer.drawRect(x + 8, ry, w - 16, row_h, Color.rgb(50, 80, 120), 1.0);
            }
            try self.renderer.drawText(x + 20, ry + 4, name[0..@min(name.len, 40)], Color.rgb(220, 225, 230));
        }
    }

    fn drawSavePrompt(self: *App) !void {
        const w: i32 = 400;
        const h: i32 = 90;
        const x = @divTrunc(self.window.fb_width - w, 2);
        const y = @divTrunc(self.window.fb_height - h, 2);
        try self.renderer.drawRect(x, y, w, h, Color.rgb(24, 28, 36), 0.97);
        try self.renderer.drawText(x + 16, y + 14, "Save Workspace", Color.rgb(230, 235, 240));
        var buf: [80]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "Name: {s}", .{self.save_name[0..self.save_name_len]}) catch "Name:";
        try self.renderer.drawText(x + 16, y + 42, label, Color.rgb(200, 210, 220));
        try self.renderer.drawText(x + 16, y + 66, "Enter save  |  Esc cancel", Color.rgb(140, 150, 160));
    }

    fn focused(self: *App) ?*Session {
        return self.tabs.focusedSession();
    }

    fn sessionCwd(self: *App) []const u8 {
        if (self.focused()) |s| return s.cwd;
        if (std.c.getenv("HOME")) |h| return std.mem.span(h);
        return "/";
    }

    fn onChar(ptr: *anyopaque, codepoint: u32) void {
        const self: *App = @ptrCast(@alignCast(ptr));
        switch (self.ui) {
            .search => {
                self.search.inputChar(codepoint);
                if (self.focused()) |s| self.search.findNext(&s.screen);
                return;
            },
            .ws_save => {
                if (codepoint < 32 or codepoint > 126) return;
                if (self.save_name_len + 1 >= self.save_name.len) return;
                // Allow name-safe chars
                const ch: u8 = @intCast(codepoint);
                if (ch == '/' or ch == '\\' or ch == '"' or ch == ' ') return;
                self.save_name[self.save_name_len] = ch;
                self.save_name_len += 1;
                return;
            },
            .ws_picker => return,
            .normal => {},
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

        if (self.ui == .ws_picker) {
            self.handlePickerKey(key);
            return;
        }
        if (self.ui == .ws_save) {
            self.handleSaveKey(key);
            return;
        }
        if (self.ui == .search) {
            if (key == c.GLFW_KEY_ESCAPE) {
                self.search.close();
                self.ui = .normal;
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
                    self.ui = .search;
                    return;
                },
                c.GLFW_KEY_O => {
                    self.openPicker();
                    return;
                },
                c.GLFW_KEY_S => {
                    self.openSavePrompt();
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

    fn openPicker(self: *App) void {
        self.workspaces.refresh() catch {};
        self.picker_index = 0;
        self.ui = .ws_picker;
        self.status_len = 0;
    }

    fn openSavePrompt(self: *App) void {
        self.save_name_len = 0;
        if (self.workspaces.current_name) |n| {
            const len = @min(n.len, self.save_name.len);
            @memcpy(self.save_name[0..len], n[0..len]);
            self.save_name_len = len;
        }
        self.ui = .ws_save;
        self.status_len = 0;
    }

    fn handlePickerKey(self: *App, key: c_int) void {
        switch (key) {
            c.GLFW_KEY_ESCAPE => self.ui = .normal,
            c.GLFW_KEY_UP => {
                if (self.picker_index > 0) self.picker_index -= 1;
            },
            c.GLFW_KEY_DOWN => {
                if (self.workspaces.names.items.len > 0 and self.picker_index + 1 < self.workspaces.names.items.len) {
                    self.picker_index += 1;
                }
            },
            c.GLFW_KEY_ENTER => {
                if (self.workspaces.names.items.len == 0) return;
                const name = self.workspaces.names.items[self.picker_index];
                self.loadWorkspace(name) catch {
                    self.setStatus("workspace load failed");
                };
                self.ui = .normal;
            },
            c.GLFW_KEY_DELETE, c.GLFW_KEY_BACKSPACE => {
                if (self.workspaces.names.items.len == 0) return;
                const name = self.workspaces.names.items[self.picker_index];
                self.workspaces.deleteWorkspace(name) catch {};
                if (self.picker_index >= self.workspaces.names.items.len and self.picker_index > 0) {
                    self.picker_index -= 1;
                }
            },
            else => {},
        }
    }

    fn handleSaveKey(self: *App, key: c_int) void {
        switch (key) {
            c.GLFW_KEY_ESCAPE => self.ui = .normal,
            c.GLFW_KEY_BACKSPACE => {
                if (self.save_name_len > 0) self.save_name_len -= 1;
            },
            c.GLFW_KEY_ENTER => {
                if (self.save_name_len == 0) return;
                const name = self.save_name[0..self.save_name_len];
                self.workspaces.saveTabs(name, &self.tabs) catch |err| {
                    _ = err;
                    self.setStatus("save failed");
                    self.ui = .normal;
                    return;
                };
                self.updateWindowTitle();
                self.setStatus("workspace saved");
                self.ui = .normal;
            },
            else => {},
        }
    }

    fn loadWorkspace(self: *App, name: []const u8) !void {
        var loaded = try self.workspaces.loadSpec(name);
        defer loaded.deinit();

        const bounds = contentRect(self.window.fb_width, self.window.fb_height);
        const cols, const rows = gridSize(bounds.w, bounds.h);
        const theme = self.config.theme();
        try self.workspaces.applyToTabs(
            &loaded,
            &self.tabs,
            cols,
            rows,
            theme.foreground,
            theme.background,
            self.config.scrollback,
        );
        self.resizeAllSessions();
        self.updateWindowTitle();
        self.setStatus("workspace loaded");
    }

    fn newTab(self: *App) !void {
        const bounds = contentRect(self.window.fb_width, self.window.fb_height);
        const cols, const rows = gridSize(bounds.w, bounds.h);
        const theme = self.config.theme();
        var title_buf: [32]u8 = undefined;
        const title = std.fmt.bufPrint(&title_buf, "Shell {d}", .{self.tabs.items.items.len + 1}) catch "Shell";
        const session = try Session.createWith(self.allocator, .{
            .cols = cols,
            .rows = rows,
            .title = title,
            .cwd = self.sessionCwd(),
        });
        session.setTheme(theme.foreground, theme.background);
        session.setScrollback(self.config.scrollback);
        try self.tabs.add(title, session);
    }

    fn splitPane(self: *App, dir: layout_mod.Dir) !void {
        const tab = self.tabs.current() orelse return;
        const bounds = contentRect(self.window.fb_width, self.window.fb_height);
        const half = if (dir == .horizontal)
            Rect{ .x = 0, .y = 0, .w = @divTrunc(bounds.w, 2), .h = bounds.h }
        else
            Rect{ .x = 0, .y = 0, .w = bounds.w, .h = @divTrunc(bounds.h, 2) };
        const cols, const rows = gridSize(half.w, half.h);
        const theme = self.config.theme();
        const session = try Session.createWith(self.allocator, .{
            .cols = cols,
            .rows = rows,
            .title = "Split",
            .cwd = self.sessionCwd(),
        });
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
        if (self.ui != .normal) return;
        const tab = self.tabs.current() orelse return;
        const bounds = contentRect(self.window.fb_width, self.window.fb_height);
        const fb = self.window.windowToFb(self.mouse_x, self.mouse_y);

        if (button == c.GLFW_MOUSE_BUTTON_LEFT) {
            if (action == c.GLFW_PRESS) {
                if (tab.layout.sessionAt(bounds, fb.x, fb.y)) |_| {
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
                        s.selection.begin(@min(col, s.screen.cols -| 1), @min(row, s.screen.rows -| 1));
                    }
                }
            } else if (action == c.GLFW_RELEASE) {
                if (self.focused()) |s| {
                    s.selection.finish();
                    if (s.selection.active) self.copySelection();
                }
            }
        }
    }

    fn onCursorPos(ptr: *anyopaque, x: f64, y: f64) void {
        const self: *App = @ptrCast(@alignCast(ptr));
        self.mouse_x = x;
        self.mouse_y = y;
        if (self.ui != .normal) return;
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
        if (self.ui != .normal) return;
        const session = self.focused() orelse return;
        const lines: i32 = @intFromFloat(yoff * 3.0);
        session.screen.scrollView(lines);
    }
};
