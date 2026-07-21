const std = @import("std");
const c = @import("../c.zig").c;
const Window = @import("../window/window.zig").Window;
const Renderer = @import("../renderer/renderer.zig").Renderer;
const Session = @import("../terminal/session.zig").Session;
const Tabs = @import("../ui/tabs.zig").Tabs;
const layout_mod = @import("../ui/layout.zig");
const Rect = layout_mod.Rect;
const Search = @import("../ui/search.zig").Search;
const Palette = @import("../ui/palette.zig").Palette;
const palette_mod = @import("../ui/palette.zig");
const home_mod = @import("../ui/home.zig");
const Home = home_mod.Home;
const Config = @import("../config/config.zig").Config;
const theme_mod = @import("../config/theme.zig");
const WsManager = @import("../workspace/workspace.zig").Manager;
const PluginRegistry = @import("../plugins/registry.zig").Registry;
const clipboard = @import("../clipboard/clipboard.zig");
const Color = @import("../terminal/cell.zig").Color;

const UiMode = enum { home, normal, search, ws_picker, ws_save, palette, ssh_prompt, settings };

pub const App = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    window: Window,
    renderer: Renderer,
    tabs: Tabs,
    config: Config,
    workspaces: WsManager,
    plugins: PluginRegistry,
    search: Search = .{},
    palette: Palette = .{},
    home: Home = .{},
    ui: UiMode = .home,
    picker_index: usize = 0,
    save_name: [64]u8 = undefined,
    save_name_len: usize = 0,
    ssh_host: [128]u8 = undefined,
    ssh_host_len: usize = 0,
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
        renderer.setContentScale(window.contentScale());
        renderer.setFontSize(config.font_size);

        var tabs = Tabs.init(allocator);
        errdefer tabs.deinit();

        var workspaces = try WsManager.init(allocator, io);
        errdefer workspaces.deinit();

        var plugins = try PluginRegistry.init(allocator, io);
        errdefer plugins.deinit();

        // Start on home — no shell until the user chooses an action.
        self.* = .{
            .allocator = allocator,
            .io = io,
            .window = window,
            .renderer = renderer,
            .tabs = tabs,
            .config = config,
            .workspaces = workspaces,
            .plugins = plugins,
            .ui = .home,
        };

        Window.active = self;
        Window.on_char = onChar;
        Window.on_key = onKey;
        Window.on_mouse_button = onMouseButton;
        Window.on_cursor_pos = onCursorPos;
        Window.on_scroll = onScroll;

        self.updateWindowTitle();
        self.fireHooks(.on_load);
        self.applyRendererHooks();
        return self;
    }

    pub fn destroy(self: *App) void {
        self.fireHooks(.on_unload);
        Window.active = null;
        Window.on_char = null;
        Window.on_key = null;
        Window.on_mouse_button = null;
        Window.on_cursor_pos = null;
        Window.on_scroll = null;
        self.plugins.deinit();
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

    fn contentRect(self: *const App) Rect {
        const scale = self.window.contentScale();
        const pad_x: i32 = @intFromFloat(@round(@as(f32, @floatFromInt(self.config.padding_x)) * scale));
        const pad_y: i32 = @intFromFloat(@round(@as(f32, @floatFromInt(self.config.padding_y)) * scale));
        const fb_w = self.window.fb_width;
        const fb_h = self.window.fb_height;
        return .{
            .x = pad_x,
            .y = Tabs.bar_height + pad_y,
            .w = @max(1, fb_w - pad_x * 2),
            .h = @max(1, fb_h - Tabs.bar_height - pad_y * 2),
        };
    }

    fn gridSize(self: *const App, w: i32, h: i32) struct { u16, u16 } {
        return gridSizeWithCell(w, h, self.renderer.cell_w, self.renderer.cell_h);
    }

    fn gridSizeWithCell(w: i32, h: i32, cell_w: f32, cell_h: f32) struct { u16, u16 } {
        const cw: i32 = @intFromFloat(@max(1.0, cell_w));
        const ch: i32 = @intFromFloat(@max(1.0, cell_h));
        const cols: u16 = @intCast(@max(1, @divTrunc(w, cw)));
        const rows: u16 = @intCast(@max(1, @divTrunc(h, ch)));
        return .{ cols, rows };
    }

    fn handleResize(self: *App) void {
        const prev_w = self.window.fb_width;
        const prev_h = self.window.fb_height;
        self.window.updateFramebufferSize();
        if (self.window.fb_width == prev_w and self.window.fb_height == prev_h) return;

        self.renderer.setFramebufferSize(self.window.fb_width, self.window.fb_height);
        self.renderer.setContentScale(self.window.contentScale());
        self.resizeAllSessions();
    }

    fn resizeAllSessions(self: *App) void {
        const tab = self.tabs.current() orelse return;
        const bounds = self.contentRect();
        const Ctx = struct {
            app: *App,
            fn cb(ctx: *@This(), session: *Session, r: Rect) void {
                const cols, const rows = ctx.app.gridSize(r.w, r.h);
                if (cols != session.screen.cols or rows != session.screen.rows) {
                    session.resize(cols, rows);
                }
            }
        };
        var ctx: Ctx = .{ .app = self };
        tab.layout.forEachLeaf(bounds, *Ctx, &ctx, Ctx.cb);
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
        if (self.ui == .home) {
            try home_mod.draw(
                &self.renderer,
                self.window.fb_width,
                self.window.fb_height,
                &self.home,
                self.config.theme_name,
                self.renderer.font_size,
                self.plugins.count(),
            );
            return;
        }

        self.renderer.clearBackground();

        // Ghostty-like integrated tab strip (matches terminal background)
        const tbg = self.renderer.theme.background;
        const tfg = self.renderer.theme.foreground;
        try self.renderer.drawRect(0, 0, self.window.fb_width, Tabs.bar_height, tbg, 1.0);
        try self.renderer.drawRect(0, Tabs.bar_height - 1, self.window.fb_width, 1, Color.rgb(
            @intCast(@min(255, @as(i32, tbg.r) + 22)),
            @intCast(@min(255, @as(i32, tbg.g) + 22)),
            @intCast(@min(255, @as(i32, tbg.b) + 26)),
        ), 1.0);
        const cell_w_i: i32 = @intFromFloat(@max(1.0, self.renderer.cell_w));
        var x: i32 = 10;
        for (self.tabs.items.items, 0..) |tab, i| {
            const active = i == self.tabs.active;
            const label_w: i32 = @as(i32, @intCast(@min(tab.title.len, 16))) * cell_w_i + 20;
            if (active) {
                try self.renderer.drawRect(x, 6, label_w, Tabs.bar_height - 12, Color.rgb(
                    @intCast(@min(255, @as(i32, tbg.r) + 16)),
                    @intCast(@min(255, @as(i32, tbg.g) + 18)),
                    @intCast(@min(255, @as(i32, tbg.b) + 22)),
                ), 1.0);
            }
            const fg = if (active) tfg else Color.rgb(
                @intCast(@divTrunc(@as(i32, tfg.r) + @as(i32, tbg.r) * 2, 3)),
                @intCast(@divTrunc(@as(i32, tfg.g) + @as(i32, tbg.g) * 2, 3)),
                @intCast(@divTrunc(@as(i32, tfg.b) + @as(i32, tbg.b) * 2, 3)),
            );
            try self.renderer.drawText(x + 10, 10, tab.title[0..@min(tab.title.len, 16)], fg);
            x += label_w + 6;
        }

        // Workspace badge on the right
        if (self.workspaces.current_name) |wn| {
            const label = wn[0..@min(wn.len, 20)];
            const lw: i32 = @as(i32, @intCast(label.len)) * cell_w_i + 20;
            const bx = self.window.fb_width - lw - 10;
            try self.renderer.drawText(bx + 8, 10, label, Color.rgb(140, 180, 160));
        }

        const tab = self.tabs.current() orelse {
            // No shell yet — still draw overlays opened from home (settings, palette, …).
            // Only bounce to home when nothing is open.
            switch (self.ui) {
                .settings => try self.drawSettings(),
                .palette => try self.drawPalette(),
                .ws_picker => try self.drawWorkspacePicker(),
                .ws_save => try self.drawSavePrompt(),
                .ssh_prompt => try self.drawSshPrompt(),
                .search => {},
                .home, .normal => self.ui = .home,
            }
            if (self.status_len > 0) {
                const bar_y = self.window.fb_height - 24;
                try self.renderer.drawRect(0, bar_y, self.window.fb_width, 24, Color.rgb(25, 35, 30), 0.9);
                try self.renderer.drawText(8, bar_y + 4, self.status_msg[0..self.status_len], Color.rgb(180, 220, 180));
            }
            return;
        };
        const bounds = self.contentRect();

        const DrawCtx = struct {
            app: *App,
            fn cb(ctx: *@This(), session: *Session, r: Rect) void {
                const cols, const rows = ctx.app.gridSize(r.w, r.h);
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
        if (self.ui == .palette) {
            try self.drawPalette();
        }
        if (self.ui == .ssh_prompt) {
            try self.drawSshPrompt();
        }
        if (self.ui == .settings) {
            try self.drawSettings();
        }
        if (self.status_len > 0 and self.ui == .normal) {
            const bar_y = self.window.fb_height - 24;
            try self.renderer.drawRect(0, bar_y, self.window.fb_width, 24, Color.rgb(25, 35, 30), 0.9);
            try self.renderer.drawText(8, bar_y + 4, self.status_msg[0..self.status_len], Color.rgb(180, 220, 180));
        }
    }

    fn drawPalette(self: *App) !void {
        const w: i32 = 520;
        const row_h: i32 = 22;
        const header: i32 = 56;
        const visible = @min(self.palette.match_count, 12);
        const h: i32 = header + @as(i32, @intCast(@max(1, visible))) * row_h + 36;
        const x = @divTrunc(self.window.fb_width - w, 2);
        const y = @max(40, @divTrunc(self.window.fb_height - h, 4));
        try self.renderer.drawRect(x, y, w, h, Color.rgb(22, 26, 34), 0.98);
        try self.renderer.drawText(x + 16, y + 12, "Command Palette", Color.rgb(230, 235, 240));
        var qbuf: [80]u8 = undefined;
        const qline = std.fmt.bufPrint(&qbuf, "> {s}", .{self.palette.querySlice()}) catch "> ";
        try self.renderer.drawText(x + 16, y + 32, qline, Color.rgb(160, 200, 255));

        if (self.palette.match_count == 0) {
            try self.renderer.drawText(x + 16, y + header, "No matching commands", Color.rgb(140, 150, 160));
        } else {
            var i: usize = 0;
            while (i < visible) : (i += 1) {
                const entry = self.palette.items[self.palette.matches[i]];
                const ry = y + header + @as(i32, @intCast(i)) * row_h;
                if (i == self.palette.selected) {
                    try self.renderer.drawRect(x + 8, ry, w - 16, row_h, Color.rgb(50, 80, 120), 1.0);
                }
                try self.renderer.drawText(x + 20, ry + 4, entry.label[0..@min(entry.label.len, 36)], Color.rgb(220, 225, 230));
                if (entry.hint.len > 0) {
                    const hx = x + w - 8 - @as(i32, @intCast(@min(entry.hint.len, 18))) * @as(i32, @intFromFloat(self.renderer.cell_w));
                    try self.renderer.drawText(hx, ry + 4, entry.hint[0..@min(entry.hint.len, 18)], Color.rgb(120, 130, 145));
                }
            }
        }
        try self.renderer.drawText(x + 16, y + h - 24, "Enter run  |  Esc close", Color.rgb(130, 140, 155));
    }

    fn drawSshPrompt(self: *App) !void {
        const w: i32 = 440;
        const h: i32 = 90;
        const x = @divTrunc(self.window.fb_width - w, 2);
        const y = @divTrunc(self.window.fb_height - h, 2);
        try self.renderer.drawRect(x, y, w, h, Color.rgb(24, 28, 36), 0.97);
        try self.renderer.drawText(x + 16, y + 14, "SSH", Color.rgb(230, 235, 240));
        var buf: [160]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "Host: {s}", .{self.ssh_host[0..self.ssh_host_len]}) catch "Host:";
        try self.renderer.drawText(x + 16, y + 42, label, Color.rgb(200, 210, 220));
        try self.renderer.drawText(x + 16, y + 66, "Enter connect  |  Esc cancel", Color.rgb(140, 150, 160));
    }

    fn drawSettings(self: *App) !void {
        const w: i32 = 480;
        const h: i32 = 160;
        const x = @divTrunc(self.window.fb_width - w, 2);
        const y = @divTrunc(self.window.fb_height - h, 2);
        try self.renderer.drawRect(x, y, w, h, Color.rgb(24, 28, 36), 0.97);
        try self.renderer.drawText(x + 16, y + 14, "Settings", Color.rgb(230, 235, 240));
        var line: [96]u8 = undefined;
        const t1 = std.fmt.bufPrint(&line, "Theme: {s}", .{self.config.theme_name}) catch "Theme:";
        try self.renderer.drawText(x + 16, y + 44, t1, Color.rgb(200, 210, 220));
        const t2 = std.fmt.bufPrint(&line, "Opacity: {d:.2}  Font: {d:.0}pt", .{ self.config.opacity, self.renderer.font_size }) catch "";
        try self.renderer.drawText(x + 16, y + 66, t2, Color.rgb(200, 210, 220));
        const t3 = std.fmt.bufPrint(&line, "Scrollback: {d}  Plugins: {d}", .{ self.config.scrollback, self.plugins.count() }) catch "";
        try self.renderer.drawText(x + 16, y + 88, t3, Color.rgb(200, 210, 220));
        if (self.workspaces.current_name) |wn| {
            const t4 = std.fmt.bufPrint(&line, "Workspace: {s}", .{wn}) catch "";
            try self.renderer.drawText(x + 16, y + 110, t4, Color.rgb(200, 210, 220));
        } else {
            try self.renderer.drawText(x + 16, y + 110, "Workspace: (none)", Color.rgb(200, 210, 220));
        }
        try self.renderer.drawText(x + 16, y + 136, "Esc close", Color.rgb(140, 150, 160));
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
            .home => {
                self.handleHomeChar(codepoint);
                return;
            },
            .search => {
                self.search.inputChar(codepoint);
                if (self.focused()) |s| self.search.findNext(&s.screen);
                return;
            },
            .palette => {
                self.palette.inputChar(codepoint);
                return;
            },
            .ssh_prompt => {
                if (codepoint < 32 or codepoint > 126) return;
                if (self.ssh_host_len + 1 >= self.ssh_host.len) return;
                self.ssh_host[self.ssh_host_len] = @intCast(codepoint);
                self.ssh_host_len += 1;
                return;
            },
            .ws_save => {
                if (codepoint < 32 or codepoint > 126) return;
                if (self.save_name_len + 1 >= self.save_name.len) return;
                const ch: u8 = @intCast(codepoint);
                if (ch == '/' or ch == '\\' or ch == '"' or ch == ' ') return;
                self.save_name[self.save_name_len] = ch;
                self.save_name_len += 1;
                return;
            },
            .ws_picker, .settings => return,
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

        // Quit anywhere: Cmd+Q (macOS) / Ctrl+Q
        if ((super or ctrl) and !shift and key == c.GLFW_KEY_Q) {
            self.requestQuit();
            return;
        }
        // Close tab / quit from home: Cmd+W or Ctrl+Shift+W
        if ((super and !shift and key == c.GLFW_KEY_W) or (ctrl and shift and key == c.GLFW_KEY_W)) {
            self.closeTabOrQuit();
            return;
        }

        if (self.ui == .home) {
            self.handleHomeKey(key, ctrl, shift);
            return;
        }
        if (self.ui == .palette) {
            self.handlePaletteKey(key);
            return;
        }
        if (self.ui == .ssh_prompt) {
            self.handleSshKey(key);
            return;
        }
        if (self.ui == .settings) {
            if (key == c.GLFW_KEY_ESCAPE) self.leaveOverlay();
            return;
        }
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
                c.GLFW_KEY_H => {
                    self.goHome();
                    return;
                },
                c.GLFW_KEY_P => {
                    self.rebuildPalette();
                    self.palette.open();
                    self.ui = .palette;
                    self.status_len = 0;
                    return;
                },
                c.GLFW_KEY_T => {
                    self.newTab() catch {};
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

        // Font size: Ctrl/Cmd + = / - / 0  (also keypad +/-)
        if ((ctrl or super) and !shift) {
            switch (key) {
                c.GLFW_KEY_EQUAL, c.GLFW_KEY_KP_ADD => {
                    self.adjustFont(1.0);
                    return;
                },
                c.GLFW_KEY_MINUS, c.GLFW_KEY_KP_SUBTRACT => {
                    self.adjustFont(-1.0);
                    return;
                },
                c.GLFW_KEY_0, c.GLFW_KEY_KP_0 => {
                    self.resetFont();
                    return;
                },
                else => {},
            }
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

    fn goHome(self: *App) void {
        self.home = .{};
        self.ui = .home;
        self.status_len = 0;
        self.search.close();
        self.palette.close();
    }

    fn requestQuit(self: *App) void {
        self.window.requestClose();
    }

    /// Cmd+W / Ctrl+Shift+W: close active tab; from home or with no tabs → quit.
    fn closeTabOrQuit(self: *App) void {
        if (self.ui == .home or self.tabs.items.items.len == 0) {
            self.requestQuit();
            return;
        }
        if (self.tabs.items.items.len <= 1) {
            self.tabs.clear();
            self.goHome();
            return;
        }
        self.tabs.closeActive();
    }

    fn handleHomeChar(self: *App, codepoint: u32) void {
        if (self.home.show_help) return;
        if (codepoint >= 'a' and codepoint <= 'z') {
            const ch: u8 = @intCast(codepoint - 32); // upper
            self.handleHomeLetter(ch);
        } else if (codepoint >= 'A' and codepoint <= 'Z') {
            self.handleHomeLetter(@intCast(codepoint));
        }
    }

    fn handleHomeLetter(self: *App, ch: u8) void {
        switch (ch) {
            'O' => self.runHomeAction(.open_workspace),
            'P' => self.runHomeAction(.command_palette),
            'S' => self.runHomeAction(.settings),
            'H' => self.runHomeAction(.help),
            'Q' => self.runHomeAction(.quit),
            else => {},
        }
    }

    fn handleHomeKey(self: *App, key: c_int, ctrl: bool, shift: bool) void {
        if (self.home.show_help) {
            if (key == c.GLFW_KEY_ESCAPE or key == c.GLFW_KEY_H) {
                self.home.show_help = false;
            }
            return;
        }
        if (ctrl and shift and key == c.GLFW_KEY_P) {
            self.runHomeAction(.command_palette);
            return;
        }
        switch (key) {
            c.GLFW_KEY_UP => self.home.moveUp(),
            c.GLFW_KEY_DOWN => self.home.moveDown(),
            c.GLFW_KEY_ENTER, c.GLFW_KEY_KP_ENTER => self.runHomeAction(self.home.selectedAction()),
            c.GLFW_KEY_1 => self.runHomeAction(.new_terminal),
            c.GLFW_KEY_2 => self.runHomeAction(.open_workspace),
            c.GLFW_KEY_3 => self.runHomeAction(.command_palette),
            c.GLFW_KEY_4 => self.runHomeAction(.settings),
            c.GLFW_KEY_5 => self.runHomeAction(.help),
            c.GLFW_KEY_6 => self.runHomeAction(.quit),
            c.GLFW_KEY_O => self.runHomeAction(.open_workspace),
            c.GLFW_KEY_P => self.runHomeAction(.command_palette),
            c.GLFW_KEY_S => self.runHomeAction(.settings),
            c.GLFW_KEY_H => self.runHomeAction(.help),
            c.GLFW_KEY_Q => self.runHomeAction(.quit),
            else => {},
        }
    }

    fn runHomeAction(self: *App, action: home_mod.Action) void {
        switch (action) {
            .new_terminal => {
                self.ensureShell() catch {
                    self.setStatus("failed to start shell");
                    return;
                };
                self.ui = .normal;
            },
            .open_workspace => {
                self.openPicker();
            },
            .command_palette => {
                self.rebuildPalette();
                self.palette.open();
                self.ui = .palette;
            },
            .settings => {
                self.ui = .settings;
            },
            .help => {
                self.home.show_help = true;
            },
            .quit => self.requestQuit(),
        }
    }

    fn ensureShell(self: *App) !void {
        if (self.tabs.items.items.len > 0) return;
        try self.newTab();
    }

    fn leaveOverlay(self: *App) void {
        self.ui = if (self.tabs.items.items.len == 0) .home else .normal;
    }

    fn handlePaletteKey(self: *App, key: c_int) void {
        switch (key) {
            c.GLFW_KEY_ESCAPE => {
                self.palette.close();
                self.leaveOverlay();
            },
            c.GLFW_KEY_UP => self.palette.moveUp(),
            c.GLFW_KEY_DOWN => self.palette.moveDown(),
            c.GLFW_KEY_BACKSPACE => self.palette.backspace(),
            c.GLFW_KEY_ENTER => {
                if (self.palette.selectedItem()) |item| {
                    self.palette.close();
                    // Provisional mode; actions may override (settings, picker, go_home, …).
                    self.ui = .normal;
                    switch (item.source) {
                        .builtin => |act| self.runAction(act),
                        .plugin => |p| self.runPluginCommand(p.plugin_name, p.command_id),
                    }
                    if (self.ui == .normal and self.tabs.items.items.len == 0) {
                        self.ui = .home;
                    }
                }
            },
            else => {},
        }
    }

    fn handleSshKey(self: *App, key: c_int) void {
        switch (key) {
            c.GLFW_KEY_ESCAPE => self.leaveOverlay(),
            c.GLFW_KEY_BACKSPACE => {
                if (self.ssh_host_len > 0) self.ssh_host_len -= 1;
            },
            c.GLFW_KEY_ENTER => {
                if (self.ssh_host_len == 0) return;
                self.connectSsh(self.ssh_host[0..self.ssh_host_len]) catch {
                    self.setStatus("ssh failed");
                };
                self.ui = .normal;
            },
            else => {},
        }
    }

    fn adjustFont(self: *App, delta: f32) void {
        self.renderer.bumpFontSize(delta);
        self.config.font_size = self.renderer.font_size;
        self.resizeAllSessions();
        var buf: [48]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "font {d:.0}pt", .{self.renderer.font_size}) catch "font changed";
        self.setStatus(msg);
    }

    fn resetFont(self: *App) void {
        self.renderer.setFontSize(14.0);
        self.config.font_size = 14.0;
        self.resizeAllSessions();
        self.setStatus("font 14pt");
    }

    fn runAction(self: *App, action: palette_mod.Action) void {
        switch (action) {
            .new_tab => self.newTab() catch {},
            .close_tab => self.closeTabOrQuit(),
            .quit => self.requestQuit(),
            .split_right => self.splitPane(.horizontal) catch {},
            .split_down => self.splitPane(.vertical) catch {},
            .next_tab => self.tabs.next(),
            .prev_tab => self.tabs.prev(),
            .focus_next_pane => {
                if (self.tabs.current()) |tab| tab.layout.focusNext();
            },
            .open_workspace => self.openPicker(),
            .save_workspace => self.openSavePrompt(),
            .search => {
                self.search.open();
                self.ui = .search;
            },
            .ssh => {
                self.ssh_host_len = 0;
                self.ui = .ssh_prompt;
            },
            .theme_orbit_dark => self.applyTheme("orbit-dark"),
            .theme_orbit_light => self.applyTheme("orbit-light"),
            .theme_nord => self.applyTheme("nord"),
            .font_larger => self.adjustFont(1.0),
            .font_smaller => self.adjustFont(-1.0),
            .font_reset => self.resetFont(),
            .settings => self.ui = .settings,
            .go_home => self.goHome(),
            .reload_config => {
                self.config.reload(self.allocator, self.io);
                self.renderer.opacity = self.config.opacity;
                self.renderer.setContentScale(self.window.contentScale());
                self.renderer.setFontSize(self.config.font_size);
                self.applyTheme(self.config.theme_name);
                self.resizeAllSessions();
                self.setStatus("config reloaded");
            },
            .reload_plugins => {
                self.plugins.reload() catch {
                    self.setStatus("plugin reload failed");
                    return;
                };
                self.fireHooks(.on_load);
                self.applyRendererHooks();
                var buf: [64]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "plugins: {d} loaded", .{self.plugins.count()}) catch "plugins reloaded";
                self.setStatus(msg);
            },
            .list_plugins => self.showPluginList(),
        }
    }

    fn rebuildPalette(self: *App) void {
        self.palette.clearItems();
        self.palette.addAllBuiltins();
        for (self.plugins.plugins.items) |*p| {
            if (!p.enabled) continue;
            for (p.commands) |cmd| {
                self.palette.addPluginCommand(cmd.label, cmd.hint, p.name, cmd.id);
            }
            for (p.themes) |t| {
                self.palette.addPluginCommand(t.name, "plugin theme", p.name, t.name);
            }
        }
    }

    fn runPluginCommand(self: *App, plugin_name: []const u8, command_id: []const u8) void {
        if (self.plugins.findCommand(plugin_name, command_id)) |cmd| {
            switch (cmd.kind) {
                .insert => {
                    if (self.focused()) |s| s.write(cmd.payload);
                    self.setStatus("plugin insert");
                },
                .status => self.setStatus(cmd.payload),
                .theme => self.applyTheme(cmd.payload),
                .host => self.runHostPayload(cmd.payload),
            }
            return;
        }
        if (self.plugins.findTheme(command_id) != null) {
            self.applyTheme(command_id);
            return;
        }
        self.setStatus("plugin command missing");
    }

    fn runHostPayload(self: *App, payload: []const u8) void {
        if (std.mem.eql(u8, payload, "new_tab")) {
            self.runAction(.new_tab);
        } else if (std.mem.eql(u8, payload, "open_workspace")) {
            self.runAction(.open_workspace);
        } else if (std.mem.eql(u8, payload, "save_workspace")) {
            self.runAction(.save_workspace);
        } else if (std.mem.eql(u8, payload, "split_right")) {
            self.runAction(.split_right);
        } else if (std.mem.eql(u8, payload, "search")) {
            self.runAction(.search);
        } else {
            self.setStatus(payload);
        }
    }

    fn showPluginList(self: *App) void {
        if (self.plugins.count() == 0) {
            self.setStatus("no plugins (~/.config/orbit/plugins)");
            return;
        }
        var buf: [96]u8 = undefined;
        var len: usize = 0;
        const prefix = "plugins:";
        @memcpy(buf[0..prefix.len], prefix);
        len = prefix.len;
        for (self.plugins.plugins.items) |p| {
            if (len + 1 + p.name.len > buf.len) break;
            buf[len] = ' ';
            len += 1;
            @memcpy(buf[len..][0..p.name.len], p.name);
            len += p.name.len;
        }
        self.setStatus(buf[0..len]);
    }

    fn fireHooks(self: *App, which: enum { on_load, on_unload, on_workspace_open, on_workspace_save }) void {
        const Ctx = struct {
            app: *App,
            fn cb(ctx: *@This(), payload: []const u8) void {
                ctx.app.runHookPayload(payload);
            }
        };
        var ctx: Ctx = .{ .app = self };
        switch (which) {
            .on_load => self.plugins.forEachHook(.on_load, *Ctx, &ctx, Ctx.cb),
            .on_unload => self.plugins.forEachHook(.on_unload, *Ctx, &ctx, Ctx.cb),
            .on_workspace_open => self.plugins.forEachHook(.on_workspace_open, *Ctx, &ctx, Ctx.cb),
            .on_workspace_save => self.plugins.forEachHook(.on_workspace_save, *Ctx, &ctx, Ctx.cb),
        }
    }

    fn runHookPayload(self: *App, payload: []const u8) void {
        if (std.mem.startsWith(u8, payload, "status:")) {
            self.setStatus(payload["status:".len..]);
        } else if (std.mem.startsWith(u8, payload, "insert:")) {
            if (self.focused()) |s| s.write(payload["insert:".len..]);
        } else if (std.mem.startsWith(u8, payload, "theme:")) {
            self.applyTheme(payload["theme:".len..]);
        } else {
            self.setStatus(payload);
        }
    }

    fn applyRendererHooks(self: *App) void {
        if (self.plugins.rendererClearColor()) |col| {
            var theme = self.renderer.theme;
            theme.background = col;
            self.renderer.setTheme(theme);
        }
    }

    fn applyTheme(self: *App, name: []const u8) void {
        self.config.setThemeName(self.allocator, name) catch {
            self.setStatus("theme failed");
            return;
        };
        const theme = if (self.plugins.findTheme(name)) |t| t else theme_mod.byName(name);
        self.renderer.setTheme(theme);
        for (self.tabs.items.items) |*tab| {
            var list: std.ArrayList(*Session) = .empty;
            defer list.deinit(self.allocator);
            tab.layout.collectSessions(&list) catch continue;
            for (list.items) |s| {
                s.setTheme(theme.foreground, theme.background);
            }
        }
        self.applyRendererHooks();
        self.setStatus("theme applied");
    }

    fn connectSsh(self: *App, host: []const u8) !void {
        try self.newTab();
        const session = self.focused() orelse return;
        var cmd: [192]u8 = undefined;
        const line = try std.fmt.bufPrint(&cmd, "ssh {s}\r", .{host});
        session.write(line);
        self.setStatus("ssh started");
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
            c.GLFW_KEY_ESCAPE => self.leaveOverlay(),
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
            c.GLFW_KEY_ESCAPE => self.leaveOverlay(),
            c.GLFW_KEY_BACKSPACE => {
                if (self.save_name_len > 0) self.save_name_len -= 1;
            },
            c.GLFW_KEY_ENTER => {
                if (self.save_name_len == 0) return;
                const name = self.save_name[0..self.save_name_len];
                self.workspaces.saveTabs(name, &self.tabs) catch {
                    self.setStatus("save failed");
                    self.ui = .normal;
                    return;
                };
                self.updateWindowTitle();
                self.fireHooks(.on_workspace_save);
                self.setStatus("workspace saved");
                self.ui = .normal;
            },
            else => {},
        }
    }

    fn loadWorkspace(self: *App, name: []const u8) !void {
        var loaded = try self.workspaces.loadSpec(name);
        defer loaded.deinit();

        const bounds = self.contentRect();
        const cols, const rows = self.gridSize(bounds.w, bounds.h);
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
        self.fireHooks(.on_workspace_open);
        self.setStatus("workspace loaded");
    }

    fn newTab(self: *App) !void {
        const bounds = self.contentRect();
        const cols, const rows = self.gridSize(bounds.w, bounds.h);
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
        const bounds = self.contentRect();
        const half = if (dir == .horizontal)
            Rect{ .x = 0, .y = 0, .w = @divTrunc(bounds.w, 2), .h = bounds.h }
        else
            Rect{ .x = 0, .y = 0, .w = bounds.w, .h = @divTrunc(bounds.h, 2) };
        const cols, const rows = self.gridSize(half.w, half.h);
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
        const bounds = self.contentRect();
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
                        const cw: i32 = @intFromFloat(@max(1.0, self.renderer.cell_w));
                        const ch: i32 = @intFromFloat(@max(1.0, self.renderer.cell_h));
                        const col: u16 = @intCast(@max(0, @divTrunc(fb.x - hit.rect.x, cw)));
                        const row: u16 = @intCast(@max(0, @divTrunc(fb.y - hit.rect.y, ch)));
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
        const bounds = self.contentRect();
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
            const cw: i32 = @intFromFloat(@max(1.0, self.renderer.cell_w));
            const ch: i32 = @intFromFloat(@max(1.0, self.renderer.cell_h));
            const col: u16 = @intCast(@max(0, @divTrunc(fb.x - r.x, cw)));
            const row: u16 = @intCast(@max(0, @divTrunc(fb.y - r.y, ch)));
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
