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
const bindings = @import("../ui/bindings.zig");
const home_mod = @import("../ui/home.zig");
const Home = home_mod.Home;
const Config = @import("../config/config.zig").Config;
const CursorStyle = @import("../config/config.zig").CursorStyle;
const theme_mod = @import("../config/theme.zig");
const WsManager = @import("../workspace/workspace.zig").Manager;
const PluginRegistry = @import("../plugins/registry.zig").Registry;
const PluginCommand = @import("../plugins/types.zig").PluginCommand;
const plugin_audit = @import("../security/plugin_audit.zig");
const clipboard = @import("../clipboard/clipboard.zig");
const folder_picker = @import("../platform/folder_picker.zig");
const Color = @import("../terminal/cell.zig").Color;
const dev_root = @import("../dev_root.zig");

const UiMode = enum { home, normal, search, ws_picker, ws_save, palette, ssh_prompt, settings, plugins };

const StatusKind = enum { info, success, err };

/// How long the bottom-left toast stays visible (seconds).
const status_ttl_s: f64 = 2.8;
const status_ttl_error_s: f64 = 4.2;

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
    /// Seconds (glfwGetTime) when the toast should disappear (0 = hidden).
    status_until: f64 = 0,
    /// Soft styling: success (green), error (warm), info (default).
    status_kind: StatusKind = .info,
    mouse_x: f64 = 0,
    mouse_y: f64 = 0,
    /// Settings row: 0 theme, 1 text, 2 cursor, 3 blink, 4 shell
    settings_row: usize = 0,
    /// Selected plugin index in the Plugins panel.
    plugin_row: usize = 0,

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
        renderer.cursor_style = config.cursor_style;
        renderer.cursor_blink = config.cursor_blink;

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
        self.publishSourceRoot();
        return self;
    }

    /// Keep ~/.config/orbit/source_root fresh and export ORBIT_SOURCE_ROOT to child shells.
    fn publishSourceRoot(self: *App) void {
        dev_root.ensureRecorded(self.allocator, self.io);
        const root = dev_root.resolve(self.allocator, self.io) orelse return;
        defer self.allocator.free(root);
        var key_buf: [32:0]u8 = undefined;
        var val_buf: [std.fs.max_path_bytes:0]u8 = undefined;
        const key = "ORBIT_SOURCE_ROOT";
        if (root.len >= val_buf.len) return;
        @memcpy(key_buf[0..key.len], key);
        key_buf[key.len] = 0;
        @memcpy(val_buf[0..root.len], root);
        val_buf[root.len] = 0;
        _ = c.setenv(key_buf[0..key.len :0], val_buf[0..root.len :0], 1);
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
        self.search.close(self.allocator);
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
            self.pollTerminalStatus();
            self.tickStatus();
            self.reapExitedSessions();
            try self.draw();
            self.window.swap();
        }
    }

    /// When the user types `exit` (or the shell otherwise ends), close that pane/tab.
    fn reapExitedSessions(self: *App) void {
        if (self.ui != .normal and self.ui != .search) return;
        if (!self.tabs.pruneDead()) return;

        if (self.tabs.items.items.len == 0) {
            self.search.close(self.allocator);
            self.goHome();
            return;
        }
        self.resizeAllSessions();
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

    fn clearStatus(self: *App) void {
        self.status_len = 0;
        self.status_until = 0;
        self.status_kind = .info;
    }

    fn setStatus(self: *App, msg: []const u8) void {
        if (msg.len == 0) {
            self.clearStatus();
            return;
        }
        const n = @min(msg.len, self.status_msg.len);
        @memcpy(self.status_msg[0..n], msg[0..n]);
        self.status_len = n;
        self.status_kind = classifyStatus(msg);
        const ttl: f64 = if (self.status_kind == .err) status_ttl_error_s else status_ttl_s;
        self.status_until = c.glfwGetTime() + ttl;
    }

    fn classifyStatus(msg: []const u8) StatusKind {
        if (containsIgnoreCase(msg, "fail") or
            containsIgnoreCase(msg, "error") or
            containsIgnoreCase(msg, "fatal") or
            containsIgnoreCase(msg, "denied"))
            return .err;
        if (containsIgnoreCase(msg, "saved") or
            containsIgnoreCase(msg, "created") or
            containsIgnoreCase(msg, "wrote") or
            containsIgnoreCase(msg, "written") or
            containsIgnoreCase(msg, "applied") or
            containsIgnoreCase(msg, "opened") or
            containsIgnoreCase(msg, "loaded") or
            containsIgnoreCase(msg, "installed") or
            containsIgnoreCase(msg, "enabled") or
            containsIgnoreCase(msg, "ready"))
            return .success;
        return .info;
    }

    fn containsIgnoreCase(hay: []const u8, needle: []const u8) bool {
        if (needle.len == 0 or needle.len > hay.len) return false;
        var i: usize = 0;
        while (i + needle.len <= hay.len) : (i += 1) {
            if (std.ascii.eqlIgnoreCase(hay[i .. i + needle.len], needle)) return true;
        }
        return false;
    }

    /// Hide the toast once its TTL elapses — it should not linger on screen.
    fn tickStatus(self: *App) void {
        if (self.status_len == 0) return;
        if (c.glfwGetTime() >= self.status_until) {
            self.clearStatus();
        }
    }

    /// Pull ephemeral notices from PTY output (file ops, errors, OSC notifies).
    fn pollTerminalStatus(self: *App) void {
        if (self.ui != .normal and self.ui != .search) return;
        const tab = self.tabs.current() orelse return;
        const Ctx = struct {
            app: *App,
            fn cb(ctx: *@This(), session: *Session, _: Rect) void {
                if (session.takeStatus()) |msg| {
                    ctx.app.setStatus(msg);
                }
            }
        };
        var ctx: Ctx = .{ .app = self };
        tab.layout.forEachLeaf(self.contentRect(), *Ctx, &ctx, Ctx.cb);
    }

    /// Floating status toast near the bottom-left — raised so it is not flush with the window edge.
    /// Only drawn while a recent event is active (`status_len > 0`); auto-clears via `tickStatus`.
    fn drawStatusBar(self: *App) !void {
        if (self.status_len == 0) return;

        const cw = @as(i32, @intFromFloat(self.renderer.cell_w));
        const ch = @as(i32, @intFromFloat(self.renderer.cell_h));
        const fb_w = self.window.fb_width;
        const fb_h = self.window.fb_height;

        const pad_x: i32 = 16;
        const pad_y: i32 = 10;
        const bar_h = ch + pad_y * 2;
        // Sit clearly above the window edge (not flush to the bottom).
        const margin_bottom = @max(48, ch * 2 + 16);
        const bar_y = fb_h - margin_bottom - bar_h;

        const text = self.status_msg[0..self.status_len];
        const text_w = @as(i32, @intCast(text.len)) * cw;
        const bar_w = @min(fb_w - 24, text_w + pad_x * 2 + 8);
        const bar_x: i32 = 12;

        const bg: Color, const accent: Color, const fg: Color = switch (self.status_kind) {
            .err => .{ Color.rgb(48, 28, 28), Color.rgb(220, 120, 110), Color.rgb(255, 210, 205) },
            .success => .{ Color.rgb(28, 42, 34), Color.rgb(110, 200, 140), Color.rgb(200, 240, 200) },
            .info => .{ Color.rgb(28, 34, 44), Color.rgb(120, 170, 220), Color.rgb(210, 225, 240) },
        };

        try self.renderer.drawRect(bar_x, bar_y, bar_w, bar_h, bg, 0.96);
        try self.renderer.drawRect(bar_x, bar_y, 3, bar_h, accent, 1.0);
        try self.renderer.drawText(bar_x + pad_x, bar_y + pad_y, text, fg);
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
            if (self.status_len > 0) {
                try self.drawStatusBar();
            }
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
                .plugins => try self.drawPlugins(),
                .palette => try self.drawPalette(),
                .ws_picker => try self.drawWorkspacePicker(),
                .ws_save => try self.drawSavePrompt(),
                .ssh_prompt => try self.drawSshPrompt(),
                .search => try self.drawSearch(),
                .home, .normal => self.ui = .home,
            }
            if (self.status_len > 0) {
                try self.drawStatusBar();
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
            try self.drawSearch();
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
        if (self.ui == .plugins) {
            try self.drawPlugins();
        }
        // Always on top of overlays so "saved" / theme notes stay readable.
        if (self.status_len > 0) {
            try self.drawStatusBar();
        }
    }

    fn drawPalette(self: *App) !void {
        const cw = @as(i32, @intFromFloat(self.renderer.cell_w));
        const ch = @as(i32, @intFromFloat(self.renderer.cell_h));
        const fb_w = self.window.fb_width;
        const fb_h = self.window.fb_height;

        // Dim the scene so the palette reads as a focused overlay.
        try self.renderer.drawRect(0, 0, fb_w, fb_h, Color.rgb(8, 10, 14), 0.45);

        const pad_x = @max(20, cw + 8);
        const pad_y = @max(16, @divTrunc(ch, 2) + 6);
        const row_h = ch + @divTrunc(ch, 2) + 4;
        const title_h = ch + 6;
        const search_h = ch + @divTrunc(ch, 2) + 8;
        const footer_h = ch + pad_y;
        const gap = @max(10, @divTrunc(ch, 2));

        const max_w = fb_w - cw * 4;
        const w = @min(@max(cw * 52, 560), max_w);
        const max_rows_by_height = @max(1, @divTrunc(fb_h - title_h - search_h - footer_h - gap * 3 - 80, row_h));
        const max_visible: usize = @min(12, @as(usize, @intCast(max_rows_by_height)));

        var start: usize = 0;
        if (self.palette.match_count > 0 and self.palette.selected >= max_visible) {
            start = self.palette.selected + 1 - max_visible;
        }
        const visible = if (self.palette.match_count == 0)
            @as(usize, 1)
        else
            @min(self.palette.match_count - start, max_visible);

        const list_h = @as(i32, @intCast(visible)) * row_h;
        const h = pad_y + title_h + search_h + gap + list_h + footer_h;
        const x = @divTrunc(fb_w - w, 2);
        const y = @max(ch * 2, @divTrunc(fb_h - h, 5));

        const panel = Color.rgb(22, 26, 34);
        const fg = Color.rgb(230, 235, 240);
        const muted = Color.rgb(140, 150, 165);
        const dim = Color.rgb(100, 110, 125);
        const accent = Color.rgb(90, 175, 220);
        const sel_bg = Color.rgb(36, 48, 64);

        try self.renderer.drawRect(x, y, w, h, panel, 0.98);
        // Soft top accent line
        try self.renderer.drawRect(x, y, w, 2, accent, 0.55);

        var cy = y + pad_y;
        try self.renderer.drawText(x + pad_x, cy, "Command Palette", fg);
        cy += title_h;

        // Search field
        try self.renderer.drawRect(x + pad_x - 4, cy - 4, w - pad_x * 2 + 8, search_h, Color.rgb(16, 19, 26), 1.0);
        var qbuf: [96]u8 = undefined;
        const query = self.palette.querySlice();
        const qline = if (query.len == 0)
            "Type to filter commands..."
        else
            (std.fmt.bufPrint(&qbuf, "> {s}", .{query}) catch "> ");
        const qcolor = if (query.len == 0) dim else accent;
        try self.renderer.drawText(x + pad_x + 4, cy + @divTrunc(search_h - ch, 2) - 2, qline, qcolor);
        cy += search_h + gap;

        // Divider under search
        try self.renderer.drawRect(x + pad_x - 4, cy - @divTrunc(gap, 2), w - pad_x * 2 + 8, 1, Color.rgb(40, 48, 60), 0.9);

        if (self.palette.match_count == 0) {
            try self.renderer.drawText(x + pad_x, cy + @divTrunc(row_h - ch, 2), "No matching commands", muted);
        } else {
            const hint_reserve = cw * 18;
            const label_max_cols = @max(12, @divTrunc(w - pad_x * 2 - hint_reserve - cw * 2, cw));

            var i: usize = 0;
            while (i < visible) : (i += 1) {
                const mi = start + i;
                const entry = self.palette.items[self.palette.matches[mi]];
                const ry = cy + @as(i32, @intCast(i)) * row_h;
                const text_y = ry + @divTrunc(row_h - ch, 2);

                if (mi == self.palette.selected) {
                    try self.renderer.drawRect(x + 10, ry, w - 20, row_h - 2, sel_bg, 1.0);
                    try self.renderer.drawRect(x + 10, ry, 3, row_h - 2, accent, 1.0);
                }

                const label_len = @min(entry.label.len, @as(usize, @intCast(label_max_cols)));
                try self.renderer.drawText(x + pad_x + 6, text_y, entry.label[0..label_len], fg);

                if (entry.hint.len > 0) {
                    const hint_len = @min(entry.hint.len, 16);
                    const hx = x + w - pad_x - @as(i32, @intCast(hint_len)) * cw;
                    try self.renderer.drawText(hx, text_y, entry.hint[0..hint_len], muted);
                }
            }
        }

        // Footer with match count when filtering
        var foot: [64]u8 = undefined;
        const foot_line = if (self.palette.query_len > 0 and self.palette.match_count > 0)
            (std.fmt.bufPrint(&foot, "{d} matches   Enter run   Esc close", .{self.palette.match_count}) catch "Enter run   Esc close")
        else
            "Up/Down move   Enter run   Esc close";
        try self.renderer.drawText(x + pad_x, y + h - footer_h + @divTrunc(pad_y, 2), foot_line, dim);
    }

    fn drawSearch(self: *App) !void {
        const cw = @as(i32, @intFromFloat(self.renderer.cell_w));
        const ch = @as(i32, @intFromFloat(self.renderer.cell_h));
        const fb_w = self.window.fb_width;
        const fb_h = self.window.fb_height;

        try self.renderer.drawRect(0, 0, fb_w, fb_h, Color.rgb(8, 10, 14), 0.45);

        const pad_x = @max(20, cw + 8);
        const pad_y = @max(16, @divTrunc(ch, 2) + 6);
        const row_h = ch + @divTrunc(ch, 2) + 4;
        const title_h = ch + 6;
        const search_h = ch + @divTrunc(ch, 2) + 8;
        const mode_h = ch + 8;
        const footer_h = ch + pad_y;
        const gap = @max(10, @divTrunc(ch, 2));

        const max_w = fb_w - cw * 4;
        const w = @min(@max(cw * 52, 560), max_w);
        const max_rows_by_height = @max(1, @divTrunc(fb_h - title_h - search_h - mode_h - footer_h - gap * 4 - 80, row_h));
        const max_visible: usize = @min(12, @as(usize, @intCast(max_rows_by_height)));

        const hit_n = self.search.hitCount();
        var start: usize = 0;
        if (hit_n > 0 and self.search.selected >= max_visible) {
            start = self.search.selected + 1 - max_visible;
        }
        const visible = if (hit_n == 0) @as(usize, 1) else @min(hit_n - start, max_visible);
        const list_h = @as(i32, @intCast(visible)) * row_h;
        const h = pad_y + title_h + mode_h + search_h + gap + list_h + footer_h;
        const x = @divTrunc(fb_w - w, 2);
        const y = @max(ch * 2, @divTrunc(fb_h - h, 5));

        const panel = Color.rgb(22, 26, 34);
        const fg = Color.rgb(230, 235, 240);
        const muted = Color.rgb(140, 150, 165);
        const dim = Color.rgb(100, 110, 125);
        const accent = Color.rgb(90, 175, 220);
        const sel_bg = Color.rgb(36, 48, 64);

        try self.renderer.drawRect(x, y, w, h, panel, 0.98);
        try self.renderer.drawRect(x, y, w, 2, accent, 0.55);

        var cy = y + pad_y;
        try self.renderer.drawText(x + pad_x, cy, "Search", fg);
        cy += title_h;

        // Mode tabs
        const term_label = if (self.search.mode == .terminal) "[ Terminal ]" else "  Terminal  ";
        const files_label = if (self.search.mode == .files) "[ Files ]" else "  Files  ";
        try self.renderer.drawText(x + pad_x, cy, term_label, if (self.search.mode == .terminal) accent else muted);
        try self.renderer.drawText(x + pad_x + cw * 14, cy, files_label, if (self.search.mode == .files) accent else muted);
        try self.renderer.drawText(x + w - pad_x - cw * 12, cy, "Tab switch", dim);
        cy += mode_h;

        try self.renderer.drawRect(x + pad_x - 4, cy - 4, w - pad_x * 2 + 8, search_h, Color.rgb(16, 19, 26), 1.0);
        var qbuf: [96]u8 = undefined;
        const query = self.search.querySlice();
        const placeholder = if (self.search.mode == .terminal)
            "Find in terminal..."
        else
            "Find files in workspace...";
        const qline = if (query.len == 0) placeholder else (std.fmt.bufPrint(&qbuf, "> {s}", .{query}) catch "> ");
        try self.renderer.drawText(x + pad_x + 4, cy + @divTrunc(search_h - ch, 2) - 2, qline, if (query.len == 0) dim else accent);
        cy += search_h + gap;

        try self.renderer.drawRect(x + pad_x - 4, cy - @divTrunc(gap, 2), w - pad_x * 2 + 8, 1, Color.rgb(40, 48, 60), 0.9);

        if (query.len == 0) {
            const hint = if (self.search.mode == .terminal)
                "Type to search scrollback and the visible screen"
            else
                "Type to search file names in the opened folder";
            try self.renderer.drawText(x + pad_x, cy + @divTrunc(row_h - ch, 2), hint, muted);
        } else if (hit_n == 0) {
            try self.renderer.drawText(x + pad_x, cy + @divTrunc(row_h - ch, 2), "No matches", muted);
        } else {
            const label_max = @max(12, @divTrunc(w - pad_x * 2 - cw * 4, cw));
            var i: usize = 0;
            while (i < visible) : (i += 1) {
                const mi = start + i;
                const ry = cy + @as(i32, @intCast(i)) * row_h;
                const text_y = ry + @divTrunc(row_h - ch, 2);
                if (mi == self.search.selected) {
                    try self.renderer.drawRect(x + 10, ry, w - 20, row_h - 2, sel_bg, 1.0);
                    try self.renderer.drawRect(x + 10, ry, 3, row_h - 2, accent, 1.0);
                }

                var line_buf: [128]u8 = undefined;
                const line: []const u8 = switch (self.search.mode) {
                    .terminal => blk: {
                        const hit = self.search.term_hits[mi];
                        break :blk (std.fmt.bufPrint(&line_buf, "line {d}  col {d}", .{ hit.abs_row + 1, hit.col + 1 }) catch "hit");
                    },
                    .files => self.search.file_hits[mi],
                };
                const shown = line[0..@min(line.len, @as(usize, @intCast(label_max)))];
                try self.renderer.drawText(x + pad_x + 6, text_y, shown, fg);
            }
        }

        var foot: [80]u8 = undefined;
        const foot_line = if (hit_n > 0)
            (std.fmt.bufPrint(&foot, "{d} matches   Enter open   Esc close", .{hit_n}) catch "Enter open   Esc close")
        else
            "Up/Down move   Tab mode   Esc close";
        try self.renderer.drawText(x + pad_x, y + h - footer_h + @divTrunc(pad_y, 2), foot_line, dim);
    }

    fn openSearch(self: *App) void {
        // Prefer searching in a live terminal; start one if needed.
        self.ensureShell() catch {
            self.setStatus("failed to start shell for search");
            return;
        };
        const root = self.sessionCwd();
        self.search.open(self.allocator, root);
        self.ui = .search;
        self.clearStatus();
        self.refreshSearchResults();
    }

    fn refreshSearchResults(self: *App) void {
        switch (self.search.mode) {
            .terminal => {
                if (self.focused()) |s| {
                    self.search.refreshTerminal(&s.screen);
                    self.search.revealSelectedTerminal(&s.screen);
                } else {
                    self.search.term_count = 0;
                }
            },
            .files => {
                // Keep root in sync with the focused session cwd.
                if (self.focused()) |s| {
                    self.search.setRoot(self.allocator, s.cwd) catch {};
                }
                self.search.refreshFiles(self.allocator, self.io);
            },
        }
    }

    fn handleSearchKey(self: *App, key: c_int) void {
        switch (key) {
            c.GLFW_KEY_ESCAPE => {
                self.search.close(self.allocator);
                self.leaveOverlay();
            },
            c.GLFW_KEY_TAB => {
                self.search.toggleMode();
                self.refreshSearchResults();
            },
            c.GLFW_KEY_UP => {
                self.search.moveUp();
                if (self.search.mode == .terminal) {
                    if (self.focused()) |s| self.search.revealSelectedTerminal(&s.screen);
                }
            },
            c.GLFW_KEY_DOWN => {
                self.search.moveDown();
                if (self.search.mode == .terminal) {
                    if (self.focused()) |s| self.search.revealSelectedTerminal(&s.screen);
                }
            },
            c.GLFW_KEY_BACKSPACE => {
                self.search.backspace();
                self.refreshSearchResults();
            },
            c.GLFW_KEY_ENTER => self.activateSearchSelection(),
            else => {},
        }
    }

    fn activateSearchSelection(self: *App) void {
        switch (self.search.mode) {
            .terminal => {
                if (self.search.term_count == 0) return;
                if (self.focused()) |s| {
                    self.search.revealSelectedTerminal(&s.screen);
                }
                // Keep search open so the user can jump between hits.
                var buf: [48]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "match {d}/{d}", .{ self.search.selected + 1, self.search.term_count }) catch "match";
                self.setStatus(msg);
            },
            .files => {
                const rel = self.search.selectedFilePath() orelse {
                    self.setStatus("no file selected");
                    return;
                };
                // Insert relative path into the shell for cd/open/edit.
                if (self.focused()) |s| {
                    s.write(rel);
                    s.write(" ");
                }
                self.search.close(self.allocator);
                self.ui = .normal;
                var buf: [96]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "inserted {s}", .{rel}) catch "file inserted";
                self.setStatus(msg);
            },
        }
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
        const cw = @as(i32, @intFromFloat(self.renderer.cell_w));
        const ch = @as(i32, @intFromFloat(self.renderer.cell_h));
        const fb_w = self.window.fb_width;
        const fb_h = self.window.fb_height;

        try self.renderer.drawRect(0, 0, fb_w, fb_h, Color.rgb(8, 10, 14), 0.45);

        const pad_x = @max(24, cw + 10);
        const pad_y = @max(20, @divTrunc(ch, 2) + 8);
        const row_h = ch + @divTrunc(ch, 2) + 8;
        const title_h = ch + 4;
        const subtitle_h = ch + @divTrunc(ch, 2);
        const gap = @max(12, @divTrunc(ch, 2));
        const footer_lines = 3;
        const footer_h = footer_lines * (ch + 4) + pad_y;

        const max_w = fb_w - cw * 4;
        const w = @min(@max(cw * 48, 540), max_w);
        const rows_n: i32 = 5;
        const list_h = rows_n * row_h;
        const h = pad_y + title_h + subtitle_h + gap + list_h + gap + footer_h;
        const x = @divTrunc(fb_w - w, 2);
        const y = @max(ch * 2, @divTrunc(fb_h - h, 2));

        const panel = Color.rgb(22, 26, 34);
        const fg = Color.rgb(230, 235, 240);
        const muted = Color.rgb(150, 160, 175);
        const dim = Color.rgb(100, 110, 125);
        const accent = Color.rgb(90, 175, 220);
        const sel_bg = Color.rgb(36, 48, 64);

        try self.renderer.drawRect(x, y, w, h, panel, 0.98);
        try self.renderer.drawRect(x, y, w, 2, accent, 0.55);

        var cy = y + pad_y;
        try self.renderer.drawText(x + pad_x, cy, "Appearance", fg);
        cy += title_h;
        try self.renderer.drawText(x + pad_x, cy, "Theme, text color, cursor, and shell for new tabs", muted);
        cy += subtitle_h + gap;

        try self.renderer.drawRect(x + pad_x - 4, cy - @divTrunc(gap, 2), w - pad_x * 2 + 8, 1, Color.rgb(40, 48, 60), 0.9);

        const rows = [_]struct { label: []const u8, value: []const u8 }{
            .{ .label = "Theme", .value = self.config.theme_name },
            .{ .label = "Text", .value = self.config.fgDisplay() },
            .{ .label = "Cursor", .value = self.config.cursor_style.name() },
            .{ .label = "Blink", .value = if (self.config.cursor_blink) "on" else "off" },
            .{ .label = "Shell", .value = self.config.shellDisplay() },
        };

        var value_buf: [96]u8 = undefined;
        for (rows, 0..) |row, i| {
            const ry = cy + @as(i32, @intCast(i)) * row_h;
            const text_y = ry + @divTrunc(row_h - ch, 2);
            const selected = i == self.settings_row;

            if (selected) {
                try self.renderer.drawRect(x + 10, ry, w - 20, row_h - 2, sel_bg, 1.0);
                try self.renderer.drawRect(x + 10, ry, 3, row_h - 2, accent, 1.0);
            }

            try self.renderer.drawText(x + pad_x + 6, text_y, row.label, if (selected) fg else muted);

            const value_text = if (selected)
                (std.fmt.bufPrint(&value_buf, "< {s} >", .{row.value}) catch row.value)
            else
                row.value;
            const value_len = @min(value_text.len, @as(usize, @intCast(@max(8, @divTrunc(@divTrunc(w, 2), cw)))));
            const vx = x + w - pad_x - @as(i32, @intCast(value_len)) * cw;
            try self.renderer.drawText(vx, text_y, value_text[0..value_len], if (selected) accent else muted);
        }

        cy += list_h + gap;
        try self.renderer.drawRect(x + pad_x - 4, cy - @divTrunc(gap, 2), w - pad_x * 2 + 8, 1, Color.rgb(40, 48, 60), 0.9);

        var info: [96]u8 = undefined;
        const font_line = std.fmt.bufPrint(&info, "Font  {d:.0}pt    padding  {d}x{d}", .{
            self.renderer.font_size,
            self.config.padding_x,
            self.config.padding_y,
        }) catch "";
        try self.renderer.drawText(x + pad_x, cy, font_line, muted);
        cy += ch + 6;
        try self.renderer.drawText(x + pad_x, cy, "Up/Down select    Left/Right change    S save", dim);
        cy += ch + 6;
        try self.renderer.drawText(x + pad_x, cy, "Esc close    Ctrl+=/-/0 font size", dim);
    }

    fn drawPlugins(self: *App) !void {
        const cw = @as(i32, @intFromFloat(self.renderer.cell_w));
        const ch = @as(i32, @intFromFloat(self.renderer.cell_h));
        const fb_w = self.window.fb_width;
        const fb_h = self.window.fb_height;

        try self.renderer.drawRect(0, 0, fb_w, fb_h, Color.rgb(8, 10, 14), 0.45);

        const pad_x = @max(24, cw + 10);
        const pad_y = @max(20, @divTrunc(ch, 2) + 8);
        const row_gap = 4;
        // Two-line rows: name/version + description.
        const row_h = ch * 2 + @divTrunc(ch, 2) + row_gap;
        const title_h = ch + 4;
        const subtitle_h = ch + @divTrunc(ch, 2);
        const gap = @max(12, @divTrunc(ch, 2));
        const footer_lines = 3;
        const plugin_n = self.plugins.count();

        const max_w = fb_w - cw * 4;
        const w = @min(@max(cw * 52, 580), max_w);

        const header_h = pad_y + title_h + subtitle_h + gap + (ch + 6) + gap;
        const footer_h = footer_lines * (ch + 6) + pad_y;
        const avail_list = @max(row_h, fb_h - header_h - footer_h - ch * 2);
        const max_visible: usize = @max(1, @as(usize, @intCast(@divTrunc(avail_list, row_h))));
        const list_rows = @max(@as(usize, 1), @min(@max(plugin_n, 1), max_visible));
        const list_h = @as(i32, @intCast(list_rows)) * row_h;
        const h = header_h + list_h + gap + footer_h;
        const x = @divTrunc(fb_w - w, 2);
        const y = @max(ch, @divTrunc(fb_h - h, 2));

        const panel = Color.rgb(22, 26, 34);
        const fg = Color.rgb(230, 235, 240);
        const muted = Color.rgb(150, 160, 175);
        const dim = Color.rgb(100, 110, 125);
        const accent = Color.rgb(90, 175, 220);
        const sel_bg = Color.rgb(36, 48, 64);
        const rule = Color.rgb(40, 48, 60);
        const on_col = Color.rgb(120, 200, 140);
        const off_col = Color.rgb(160, 110, 110);

        try self.renderer.drawRect(x, y, w, h, panel, 0.98);
        try self.renderer.drawRect(x, y, w, 2, accent, 0.55);

        var cy = y + pad_y;
        try self.renderer.drawText(x + pad_x, cy, "Plugins", fg);
        cy += title_h;
        try self.renderer.drawText(x + pad_x, cy, "Shortcuts, themes, and commands you can edit", muted);
        cy += subtitle_h;

        try self.renderer.drawRect(x + pad_x - 4, cy, w - pad_x * 2 + 8, 1, rule, 0.9);
        cy += gap;

        var count_buf: [48]u8 = undefined;
        const count_line = if (plugin_n == 0)
            "No plugins installed"
        else
            (std.fmt.bufPrint(&count_buf, "{d} installed", .{plugin_n}) catch "installed");
        try self.renderer.drawText(x + pad_x, cy, count_line, muted);
        if (plugin_n < 6) {
            const tip = "I  install pack";
            const tip_x = x + w - pad_x - @as(i32, @intCast(tip.len)) * cw;
            try self.renderer.drawText(tip_x, cy, tip, accent);
        }
        cy += ch + 6;

        const list_top = cy;
        if (plugin_n == 0) {
            const empty_y = list_top + @divTrunc(list_h - ch * 2, 2);
            try self.renderer.drawText(x + pad_x + 6, empty_y, "Press I to install the bundled pack", fg);
            try self.renderer.drawText(x + pad_x + 6, empty_y + ch + 4, "hello · git · devtools · themes · workflow · keys", dim);
        } else {
            if (self.plugin_row >= plugin_n) self.plugin_row = plugin_n - 1;
            var start: usize = 0;
            if (self.plugin_row >= max_visible) {
                start = self.plugin_row + 1 - max_visible;
            }
            const visible = @min(plugin_n - start, max_visible);
            var i: usize = 0;
            while (i < visible) : (i += 1) {
                const mi = start + i;
                const p = self.plugins.plugins.items[mi];
                const ry = list_top + @as(i32, @intCast(i)) * row_h;
                const selected = mi == self.plugin_row;

                if (selected) {
                    try self.renderer.drawRect(x + 10, ry, w - 20, row_h - row_gap, sel_bg, 1.0);
                    try self.renderer.drawRect(x + 10, ry, 3, row_h - row_gap, accent, 1.0);
                }

                const name_y = ry + @divTrunc(ch, 3);
                const desc_y = name_y + ch + 2;
                const text_x = x + pad_x + 6;

                // Name + version on the first line.
                try self.renderer.drawText(text_x, name_y, p.name, if (selected) fg else muted);

                var ver_buf: [24]u8 = undefined;
                const ver = std.fmt.bufPrint(&ver_buf, "v{s}", .{p.version}) catch "";
                const name_w = @as(i32, @intCast(p.name.len)) * cw;
                try self.renderer.drawText(text_x + name_w + cw, name_y, ver, dim);

                // Compact capability counts when selected (skip zeros).
                if (selected) {
                    var meta_buf: [48]u8 = undefined;
                    var meta_len: usize = 0;
                    const append = struct {
                        fn go(buf: []u8, len: *usize, label: []const u8, n: usize) void {
                            if (n == 0 or len.* >= buf.len) return;
                            if (len.* > 0 and len.* + 2 < buf.len) {
                                buf[len.*] = ' ';
                                buf[len.* + 1] = ' ';
                                len.* += 2;
                            }
                            const piece = std.fmt.bufPrint(buf[len.*..], "{d} {s}", .{ n, label }) catch return;
                            len.* += piece.len;
                        }
                    }.go;
                    append(&meta_buf, &meta_len, "cmd", p.commands.len);
                    append(&meta_buf, &meta_len, "theme", p.themes.len);
                    append(&meta_buf, &meta_len, "bind", p.bindings.len);
                    if (meta_len > 0) {
                        const meta_x = text_x + name_w + cw * (@as(i32, @intCast(ver.len)) + 2);
                        const state_reserve = cw * 6;
                        const meta_max = @max(0, (x + w - pad_x - state_reserve) - meta_x);
                        const meta_chars = @min(meta_len, @as(usize, @intCast(@divTrunc(meta_max, cw))));
                        if (meta_chars > 0) {
                            try self.renderer.drawText(meta_x, name_y, meta_buf[0..meta_chars], dim);
                        }
                    }
                }

                // Description on the second line.
                const desc = if (p.description.len > 0) p.description else "No description";
                const desc_max = @max(8, @divTrunc(w - pad_x * 2 - cw * 4, cw));
                const desc_shown = desc[0..@min(desc.len, @as(usize, @intCast(desc_max)))];
                try self.renderer.drawText(text_x, desc_y, desc_shown, if (selected) muted else dim);

                // Fixed-width toggle so columns stay aligned.
                const state = if (p.enabled) "ON " else "OFF";
                const state_x = x + w - pad_x - @as(i32, @intCast(state.len)) * cw;
                try self.renderer.drawText(state_x, name_y, state, if (p.enabled) on_col else off_col);
            }
        }

        cy = y + h - footer_h;
        try self.renderer.drawRect(x + pad_x - 4, cy - @divTrunc(gap, 2), w - pad_x * 2 + 8, 1, rule, 0.9);
        try self.renderer.drawText(x + pad_x, cy, "~/.config/orbit/plugins/<name>/plugin.toml", dim);
        cy += ch + 6;
        try self.renderer.drawText(x + pad_x, cy, "Up/Down select    Space toggle    R reload", dim);
        cy += ch + 6;
        try self.renderer.drawText(x + pad_x, cy, "I install/update pack    Esc close", dim);
    }

    fn drawWorkspacePicker(self: *App) !void {
        const w: i32 = 420;
        const row_h: i32 = 22;
        const header: i32 = 36;
        const h: i32 = header + @as(i32, @intCast(@max(1, self.workspaces.names.items.len))) * row_h + 48;
        const x = @divTrunc(self.window.fb_width - w, 2);
        const y = @divTrunc(self.window.fb_height - h, 2);
        try self.renderer.drawRect(x, y, w, h, Color.rgb(24, 28, 36), 0.97);
        try self.renderer.drawText(x + 16, y + 12, "Load Saved Workspace", Color.rgb(230, 235, 240));
        try self.renderer.drawText(x + 16, y + h - 28, "Enter open  |  Esc close  |  Del delete", Color.rgb(140, 150, 160));

        if (self.workspaces.names.items.len == 0) {
            try self.renderer.drawText(x + 16, y + header + 8, "(none saved yet — Ctrl+Shift+S to save)", Color.rgb(160, 170, 180));
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
                self.refreshSearchResults();
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
            .ws_picker, .settings, .plugins => return,
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
        const alt = (mods & c.GLFW_MOD_ALT) != 0;
        const bmods: bindings.Mods = .{ .ctrl = ctrl, .shift = shift, .super = super, .alt = alt };

        // Global: quit / close tab — must match the *actual* key, not only modifiers.
        // (Matching "w" while Ctrl is held used to close on every Ctrl chord.)
        if (glfwKeyName(key)) |name| {
            if (bindings.match(name, bmods)) |act| {
                if (act == .quit) {
                    self.requestQuit();
                    return;
                }
                if (act == .close_tab) {
                    self.closeTabOrQuit();
                    return;
                }
            }
        }

        if (self.ui == .home) {
            self.handleHomeKey(key, ctrl, shift, super);
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
            self.handleSettingsKey(key);
            return;
        }
        if (self.ui == .plugins) {
            self.handlePluginsKey(key);
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
            self.handleSearchKey(key);
            return;
        }

        // Palette open is not a palette Action enum member.
        if (ctrl and shift and key == c.GLFW_KEY_P) {
            self.rebuildPalette();
            self.palette.open();
            self.ui = .palette;
            self.clearStatus();
            return;
        }

        // Clipboard (Shift required so plain Ctrl+C still interrupts the shell).
        if ((ctrl or super) and shift and key == c.GLFW_KEY_C) {
            self.copySelection();
            return;
        }
        if ((ctrl or super) and shift and key == c.GLFW_KEY_V) {
            self.pasteClipboard();
            return;
        }

        // Built-in chords from the shared bindings table (palette hints stay in sync).
        if (glfwKeyName(key)) |name| {
            if (bindings.match(name, bmods)) |act| {
                self.runAction(act);
                return;
            }
        }
        // Keypad font shortcuts share equal/minus/0 actions.
        if ((ctrl or super) and !shift) {
            switch (key) {
                c.GLFW_KEY_KP_ADD => {
                    self.runAction(.font_larger);
                    return;
                },
                c.GLFW_KEY_KP_SUBTRACT => {
                    self.runAction(.font_smaller);
                    return;
                },
                c.GLFW_KEY_KP_0 => {
                    self.runAction(.font_reset);
                    return;
                },
                else => {},
            }
        }

        // Plugin shortcuts (after built-ins so Ctrl+Shift+P etc. stay reserved)
        if (self.tryPluginBinding(key, ctrl, shift, super, alt)) return;

        const session = self.focused() orelse return;

        // Forward Ctrl+A…Z to the PTY so the shell stays responsive (interrupt, EOF, …).
        if (glfwKeyName(key)) |name| {
            if (bindings.ctrlLetterToPty(name, bmods)) |byte| {
                session.write(&.{byte});
                return;
            }
        }

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
        self.search.close(self.allocator);
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
            'L' => self.runHomeAction(.plugins),
            'H' => self.runHomeAction(.help),
            'Q' => self.runHomeAction(.quit),
            else => {},
        }
    }

    fn handleHomeKey(self: *App, key: c_int, ctrl: bool, shift: bool, super: bool) void {
        if (self.home.show_help) {
            switch (key) {
                c.GLFW_KEY_ESCAPE, c.GLFW_KEY_H => self.home.closeHelp(),
                c.GLFW_KEY_UP => self.home.scrollHelp(-1),
                c.GLFW_KEY_DOWN => self.home.scrollHelp(1),
                c.GLFW_KEY_PAGE_UP => self.home.scrollHelp(-8),
                c.GLFW_KEY_PAGE_DOWN => self.home.scrollHelp(8),
                c.GLFW_KEY_HOME => self.home.help_scroll = 0,
                c.GLFW_KEY_END => {
                    self.home.help_scroll = if (home_mod.help_rows.len == 0) 0 else home_mod.help_rows.len - 1;
                },
                else => {},
            }
            return;
        }
        if (ctrl and shift and key == c.GLFW_KEY_P) {
            self.runHomeAction(.command_palette);
            return;
        }
        if ((ctrl or super) and shift and key == c.GLFW_KEY_F) {
            self.openSearch();
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
            c.GLFW_KEY_5 => self.runHomeAction(.plugins),
            c.GLFW_KEY_6 => self.runHomeAction(.help),
            c.GLFW_KEY_7 => self.runHomeAction(.quit),
            c.GLFW_KEY_O => self.runHomeAction(.open_workspace),
            c.GLFW_KEY_P => self.runHomeAction(.command_palette),
            c.GLFW_KEY_S => self.runHomeAction(.settings),
            c.GLFW_KEY_L => self.runHomeAction(.plugins),
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
                self.openFolderWorkspace();
            },
            .command_palette => {
                self.rebuildPalette();
                self.palette.open();
                self.ui = .palette;
            },
            .settings => {
                self.settings_row = 0;
                self.ui = .settings;
            },
            .plugins => {
                self.plugin_row = 0;
                self.ui = .plugins;
            },
            .help => self.home.openHelp(),
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
            .open_workspace => self.openFolderWorkspace(),
            .load_saved_workspace => self.openPicker(),
            .save_workspace => self.openSavePrompt(),
            .search => {
                self.openSearch();
            },
            .ssh => {
                self.ssh_host_len = 0;
                self.ui = .ssh_prompt;
            },
            .theme_orbit_dark => self.applyTheme("orbit-dark"),
            .theme_orbit_light => self.applyTheme("orbit-light"),
            .theme_nord => self.applyTheme("nord"),
            .theme_dracula => self.applyTheme("dracula"),
            .theme_gruvbox => self.applyTheme("gruvbox-dark"),
            .theme_solarized => self.applyTheme("solarized-dark"),
            .cursor_block => self.setCursorStyle(.block),
            .cursor_underline => self.setCursorStyle(.underline),
            .cursor_bar => self.setCursorStyle(.bar),
            .cursor_blink_toggle => self.toggleCursorBlink(),
            .font_larger => self.adjustFont(1.0),
            .font_smaller => self.adjustFont(-1.0),
            .font_reset => self.resetFont(),
            .settings => {
                self.settings_row = 0;
                self.ui = .settings;
            },
            .go_home => self.goHome(),
            .reload_config => {
                self.config.reload(self.allocator, self.io);
                self.renderer.opacity = self.config.opacity;
                self.renderer.setContentScale(self.window.contentScale());
                self.renderer.setFontSize(self.config.font_size);
                self.renderer.cursor_style = self.config.cursor_style;
                self.renderer.cursor_blink = self.config.cursor_blink;
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
            .list_plugins => {
                self.plugin_row = 0;
                self.ui = .plugins;
            },
        }
    }

    fn handlePluginsKey(self: *App, key: c_int) void {
        switch (key) {
            c.GLFW_KEY_ESCAPE => self.leaveOverlay(),
            c.GLFW_KEY_UP => {
                if (self.plugin_row > 0) self.plugin_row -= 1;
            },
            c.GLFW_KEY_DOWN => {
                const n = self.plugins.count();
                if (n > 0 and self.plugin_row + 1 < n) self.plugin_row += 1;
            },
            c.GLFW_KEY_ENTER, c.GLFW_KEY_SPACE => self.toggleSelectedPlugin(),
            c.GLFW_KEY_R => self.reloadPluginsFromPanel(),
            c.GLFW_KEY_I => self.installBundledPlugins(),
            else => {},
        }
    }

    fn toggleSelectedPlugin(self: *App) void {
        if (self.plugin_row >= self.plugins.plugins.items.len) {
            self.setStatus("no plugin selected");
            return;
        }
        const p = &self.plugins.plugins.items[self.plugin_row];
        p.enabled = !p.enabled;
        self.rebuildPalette();
        self.applyRendererHooks();
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{s} {s}", .{ p.name, if (p.enabled) "enabled" else "disabled" }) catch "plugin toggled";
        self.setStatus(msg);
    }

    fn reloadPluginsFromPanel(self: *App) void {
        self.plugins.reload() catch {
            self.setStatus("plugin reload failed");
            return;
        };
        self.fireHooks(.on_load);
        self.applyRendererHooks();
        self.rebuildPalette();
        if (self.plugin_row >= self.plugins.count() and self.plugins.count() > 0) {
            self.plugin_row = self.plugins.count() - 1;
        } else if (self.plugins.count() == 0) {
            self.plugin_row = 0;
        }
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "plugins: {d} loaded", .{self.plugins.count()}) catch "plugins reloaded";
        self.setStatus(msg);
    }

    /// Install the bundled plugin pack (hello, git, devtools, themes, workflow, keys).
    fn installBundledPlugins(self: *App) void {
        const Bundle = struct { name: []const u8, toml: []const u8 };
        const pack = [_]Bundle{
            .{
                .name = "hello",
                .toml =
                \\name = "hello"
                \\version = "0.1.0"
                \\description = "Demo Orbit plugin — commands, theme, and lifecycle hooks"
                \\
                \\[[commands]]
                \\id = "hello.greet"
                \\label = "Plugin: Hello"
                \\hint = "status"
                \\action = "status"
                \\payload = "Hello from the hello plugin"
                \\
                \\[[commands]]
                \\id = "hello.date"
                \\label = "Plugin: Insert date"
                \\hint = "insert"
                \\action = "insert"
                \\payload = "date\r"
                \\
                \\[[commands]]
                \\id = "hello.new_tab"
                \\label = "Plugin: New Tab"
                \\hint = "host"
                \\action = "host"
                \\payload = "new_tab"
                \\
                \\[[themes]]
                \\name = "amber"
                \\foreground = "#f5e6c8"
                \\background = "#2a2010"
                \\cursor = "#ffb000"
                \\selection = "#5a4020"
                \\
                \\[hooks]
                \\on_load = "status:hello plugin loaded"
                \\on_workspace_open = "status:hello: workspace opened"
                \\on_workspace_save = "status:hello: workspace saved"
                \\
                ,
            },
            .{
                .name = "git",
                .toml =
                \\name = "git"
                \\version = "0.1.0"
                \\description = "Git shortcuts — status, diff, log, branch, pull, push"
                \\
                \\[[commands]]
                \\id = "git.status"
                \\label = "Git: Status"
                \\hint = "git status"
                \\action = "insert"
                \\payload = "git status\r"
                \\
                \\[[commands]]
                \\id = "git.diff"
                \\label = "Git: Diff"
                \\hint = "git diff"
                \\action = "insert"
                \\payload = "git diff\r"
                \\
                \\[[commands]]
                \\id = "git.log"
                \\label = "Git: Log"
                \\hint = "oneline"
                \\action = "insert"
                \\payload = "git log --oneline -20\r"
                \\
                \\[[commands]]
                \\id = "git.branch"
                \\label = "Git: Branches"
                \\hint = "git branch"
                \\action = "insert"
                \\payload = "git branch -vv\r"
                \\
                \\[[commands]]
                \\id = "git.pull"
                \\label = "Git: Pull"
                \\hint = "git pull"
                \\action = "insert"
                \\payload = "git pull\r"
                \\
                \\[[commands]]
                \\id = "git.push"
                \\label = "Git: Push"
                \\hint = "git push"
                \\action = "insert"
                \\payload = "git push\r"
                \\
                \\[[commands]]
                \\id = "git.stash"
                \\label = "Git: Stash"
                \\hint = "git stash"
                \\action = "insert"
                \\payload = "git stash push -u\r"
                \\
                \\[hooks]
                \\on_load = "status:git plugin ready"
                \\on_workspace_open = "status:git: workspace opened"
                \\
                ,
            },
            .{
                .name = "devtools",
                .toml =
                \\name = "devtools"
                \\version = "0.1.0"
                \\description = "Everyday shell utilities for navigating and inspecting projects"
                \\
                \\[[commands]]
                \\id = "dev.pwd"
                \\label = "Dev: Print cwd"
                \\hint = "pwd"
                \\action = "insert"
                \\payload = "pwd\r"
                \\
                \\[[commands]]
                \\id = "dev.ls"
                \\label = "Dev: List files"
                \\hint = "ls -la"
                \\action = "insert"
                \\payload = "ls -la\r"
                \\
                \\[[commands]]
                \\id = "dev.tree"
                \\label = "Dev: Tree (depth 2)"
                \\hint = "find"
                \\action = "insert"
                \\payload = "find . -maxdepth 2 -not -path '*/.*' | head -80\r"
                \\
                \\[[commands]]
                \\id = "dev.clear"
                \\label = "Dev: Clear screen"
                \\hint = "clear"
                \\action = "insert"
                \\payload = "clear\r"
                \\
                \\[[commands]]
                \\id = "dev.disk"
                \\label = "Dev: Disk usage here"
                \\hint = "du"
                \\action = "insert"
                \\payload = "du -sh ./* 2>/dev/null | sort -h | tail -20\r"
                \\
                \\[[commands]]
                \\id = "dev.ports"
                \\label = "Dev: Listening ports"
                \\hint = "lsof"
                \\action = "insert"
                \\payload = "lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | head -30\r"
                \\
                \\[[commands]]
                \\id = "dev.env"
                \\label = "Dev: Path & shell"
                \\hint = "echo"
                \\action = "insert"
                \\payload = "echo \"SHELL=$SHELL\" && echo \"PATH=$PATH\" | tr ':' '\\n' | head -20\r"
                \\
                \\[hooks]
                \\on_load = "status:devtools ready"
                \\
                ,
            },
            .{
                .name = "themes",
                .toml =
                \\name = "themes"
                \\version = "0.1.0"
                \\description = "Extra color themes — ocean, forest, midnight, rose"
                \\
                \\[[themes]]
                \\name = "ocean"
                \\foreground = "#d8eef8"
                \\background = "#0b1c28"
                \\cursor = "#5ec8f0"
                \\selection = "#1e4a62"
                \\
                \\[[themes]]
                \\name = "forest"
                \\foreground = "#e4efd8"
                \\background = "#142018"
                \\cursor = "#8fbf5a"
                \\selection = "#2a4030"
                \\
                \\[[themes]]
                \\name = "midnight"
                \\foreground = "#e8e6f5"
                \\background = "#12101c"
                \\cursor = "#a090ff"
                \\selection = "#2a2440"
                \\
                \\[[themes]]
                \\name = "rose"
                \\foreground = "#ffe8ee"
                \\background = "#1c1014"
                \\cursor = "#ff8aab"
                \\selection = "#4a2030"
                \\
                \\[hooks]
                \\on_load = "status:themes plugin ready"
                \\
                ,
            },
            .{
                .name = "workflow",
                .toml =
                \\name = "workflow"
                \\version = "0.1.0"
                \\description = "Workflow helpers — tabs, splits, search, workspace shortcuts"
                \\
                \\[[commands]]
                \\id = "wf.new_tab"
                \\label = "Workflow: New Tab"
                \\hint = "host"
                \\action = "host"
                \\payload = "new_tab"
                \\
                \\[[commands]]
                \\id = "wf.split_right"
                \\label = "Workflow: Split Right"
                \\hint = "host"
                \\action = "host"
                \\payload = "split_right"
                \\
                \\[[commands]]
                \\id = "wf.open_workspace"
                \\label = "Workflow: Open Workspace"
                \\hint = "host"
                \\action = "host"
                \\payload = "open_workspace"
                \\
                \\[[commands]]
                \\id = "wf.save_workspace"
                \\label = "Workflow: Save Workspace"
                \\hint = "host"
                \\action = "host"
                \\payload = "save_workspace"
                \\
                \\[[commands]]
                \\id = "wf.search"
                \\label = "Workflow: Search"
                \\hint = "host"
                \\action = "host"
                \\payload = "search"
                \\
                \\[[commands]]
                \\id = "wf.tip"
                \\label = "Workflow: Tip"
                \\hint = "status"
                \\action = "status"
                \\payload = "Tip: Ctrl+Shift+P for palette · L for Plugins · edit keys plugin for shortcuts"
                \\
                \\[hooks]
                \\on_load = "status:workflow helpers ready"
                \\on_workspace_save = "status:workflow: workspace saved"
                \\
                ,
            },
            .{
                .name = "keys",
                .toml =
                \\name = "keys"
                \\version = "0.1.0"
                \\description = "Custom shortcuts starter — edit keys to make Orbit yours"
                \\
                \\[[commands]]
                \\id = "keys.git_status"
                \\label = "Keys: Git Status"
                \\hint = "ctrl+shift+g"
                \\action = "insert"
                \\payload = "git status\r"
                \\shortcut = "ctrl+shift+g"
                \\
                \\[[commands]]
                \\id = "keys.ls"
                \\label = "Keys: List files"
                \\hint = "ctrl+alt+l"
                \\action = "insert"
                \\payload = "ls -la\r"
                \\shortcut = "ctrl+alt+l"
                \\
                \\[[commands]]
                \\id = "keys.clear"
                \\label = "Keys: Clear"
                \\hint = "ctrl+alt+k"
                \\action = "insert"
                \\payload = "clear\r"
                \\shortcut = "ctrl+alt+k"
                \\
                \\[[commands]]
                \\id = "keys.tip"
                \\label = "Keys: Tip"
                \\hint = "status"
                \\action = "status"
                \\payload = "Edit ~/.config/orbit/plugins/keys/plugin.toml — then press R in Plugins"
                \\
                \\[[bindings]]
                \\keys = "ctrl+alt+t"
                \\command = "keys.tip"
                \\
                \\[[themes]]
                \\name = "keys-slate"
                \\foreground = "#e2e8f0"
                \\background = "#0f172a"
                \\cursor = "#38bdf8"
                \\selection = "#1e3a5f"
                \\
                \\[hooks]
                \\on_load = "status:keys plugin — customize shortcuts in plugin.toml"
                \\
                ,
            },
        };

        var installed: usize = 0;
        for (pack) |item| {
            if (self.writePluginToml(item.name, item.toml)) installed += 1;
        }
        self.reloadPluginsFromPanel();
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "installed {d} plugins", .{installed}) catch "plugins installed";
        self.setStatus(msg);
    }

    fn writePluginToml(self: *App, name: []const u8, toml: []const u8) bool {
        const plugin_dir = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.plugins.dir_path, name }) catch return false;
        defer self.allocator.free(plugin_dir);

        var path_buf: [std.fs.max_path_bytes:0]u8 = undefined;
        if (plugin_dir.len >= path_buf.len) return false;
        @memcpy(path_buf[0..plugin_dir.len], plugin_dir);
        path_buf[plugin_dir.len] = 0;
        _ = std.c.mkdir(path_buf[0..plugin_dir.len :0], 0o755);

        const toml_path = std.fmt.allocPrint(self.allocator, "{s}/plugin.toml", .{plugin_dir}) catch return false;
        defer self.allocator.free(toml_path);

        const file = std.Io.Dir.createFileAbsolute(self.io, toml_path, .{}) catch return false;
        defer file.close(self.io);
        file.writeStreamingAll(self.io, toml) catch return false;
        return true;
    }

    fn handleSettingsKey(self: *App, key: c_int) void {
        switch (key) {
            c.GLFW_KEY_ESCAPE => self.leaveOverlay(),
            c.GLFW_KEY_UP => {
                if (self.settings_row > 0) self.settings_row -= 1;
            },
            c.GLFW_KEY_DOWN => {
                if (self.settings_row + 1 < 5) self.settings_row += 1;
            },
            c.GLFW_KEY_LEFT => self.nudgeSettings(-1),
            c.GLFW_KEY_RIGHT, c.GLFW_KEY_ENTER => self.nudgeSettings(1),
            c.GLFW_KEY_S => self.persistAppearance(),
            else => {},
        }
    }

    fn nudgeSettings(self: *App, delta: i32) void {
        switch (self.settings_row) {
            0 => {
                const next = theme_mod.nextName(self.config.theme_name, delta);
                self.applyTheme(next);
            },
            1 => {
                self.config.cycleFgPreset(self.allocator, delta) catch {
                    self.setStatus("text color failed");
                    return;
                };
                self.refreshThemeColors();
                var buf: [64]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "text {s}", .{self.config.fgDisplay()}) catch "text color";
                self.setStatus(msg);
            },
            2 => {
                self.config.cursor_style = if (delta >= 0)
                    self.config.cursor_style.next()
                else
                    self.config.cursor_style.prev();
                self.renderer.cursor_style = self.config.cursor_style;
                self.setStatus("cursor style");
            },
            3 => self.toggleCursorBlink(),
            4 => {
                self.config.cycleShell(self.allocator, delta) catch {
                    self.setStatus("shell change failed");
                    return;
                };
                var buf: [80]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "shell {s} (new tabs)", .{self.config.shellDisplay()}) catch "shell updated";
                self.setStatus(msg);
            },
            else => {},
        }
    }

    fn setCursorStyle(self: *App, style: CursorStyle) void {
        self.config.cursor_style = style;
        self.renderer.cursor_style = style;
        self.setStatus("cursor style");
    }

    fn toggleCursorBlink(self: *App) void {
        self.config.cursor_blink = !self.config.cursor_blink;
        self.renderer.cursor_blink = self.config.cursor_blink;
        self.setStatus(if (self.config.cursor_blink) "cursor blink on" else "cursor blink off");
    }

    fn persistAppearance(self: *App) void {
        self.config.font_size = self.renderer.font_size;
        self.config.save(self.allocator, self.io) catch {
            self.setStatus("could not save config.toml");
            return;
        };
        self.setStatus("saved ~/.config/orbit/config.toml");
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
            self.executePluginCommand(cmd);
            return;
        }
        if (self.plugins.findTheme(command_id) != null) {
            self.applyTheme(command_id);
            return;
        }
        self.setStatus("plugin command missing");
    }

    fn executePluginCommand(self: *App, cmd: *const PluginCommand) void {
        switch (cmd.kind) {
            .insert => {
                if (plugin_audit.auditInsertPayload(cmd.payload)) |hit| {
                    var buf: [192]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, "security warning [{s}]: {s}", .{
                        hit.severity.label(),
                        hit.message,
                    }) catch "security warning: risky plugin insert";
                    self.setStatus(msg);
                    std.log.warn("security: executing risky insert `{s}`: {s}", .{ cmd.id, hit.message });
                } else {
                    self.setStatus("plugin insert");
                }
                if (self.focused()) |s| s.write(cmd.payload);
            },
            .status => self.setStatus(cmd.payload),
            .theme => self.applyTheme(cmd.payload),
            .host => self.runHostPayload(cmd.payload),
        }
    }

    /// Run a plugin keybinding if one matches. Prefer chords with modifiers.
    fn tryPluginBinding(self: *App, key: c_int, ctrl: bool, shift: bool, super: bool, alt: bool) bool {
        // Plain typing must reach the shell — only chords with a modifier (or F-keys).
        const is_fn = key >= c.GLFW_KEY_F1 and key <= c.GLFW_KEY_F12;
        if (!ctrl and !shift and !super and !alt and !is_fn) return false;

        const name = glfwKeyName(key) orelse return false;
        const command_id = self.plugins.matchBinding(name, ctrl, shift, super, alt) orelse return false;
        if (self.plugins.findCommandById(command_id)) |cmd| {
            self.executePluginCommand(cmd);
            return true;
        }
        if (self.plugins.findTheme(command_id) != null) {
            self.applyTheme(command_id);
            return true;
        }
        return false;
    }

    fn glfwKeyName(key: c_int) ?[]const u8 {
        if (key >= c.GLFW_KEY_A and key <= c.GLFW_KEY_Z) {
            const names = [_][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z" };
            return names[@intCast(key - c.GLFW_KEY_A)];
        }
        if (key >= c.GLFW_KEY_0 and key <= c.GLFW_KEY_9) {
            const names = [_][]const u8{ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" };
            return names[@intCast(key - c.GLFW_KEY_0)];
        }
        if (key >= c.GLFW_KEY_F1 and key <= c.GLFW_KEY_F12) {
            const names = [_][]const u8{ "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12" };
            return names[@intCast(key - c.GLFW_KEY_F1)];
        }
        return switch (key) {
            c.GLFW_KEY_ENTER, c.GLFW_KEY_KP_ENTER => "enter",
            c.GLFW_KEY_ESCAPE => "escape",
            c.GLFW_KEY_SPACE => "space",
            c.GLFW_KEY_TAB => "tab",
            c.GLFW_KEY_BACKSPACE => "backspace",
            c.GLFW_KEY_DELETE => "delete",
            c.GLFW_KEY_UP => "up",
            c.GLFW_KEY_DOWN => "down",
            c.GLFW_KEY_LEFT => "left",
            c.GLFW_KEY_RIGHT => "right",
            c.GLFW_KEY_HOME => "home",
            c.GLFW_KEY_END => "end",
            c.GLFW_KEY_PAGE_UP => "pageup",
            c.GLFW_KEY_PAGE_DOWN => "pagedown",
            c.GLFW_KEY_MINUS, c.GLFW_KEY_KP_SUBTRACT => "minus",
            c.GLFW_KEY_EQUAL, c.GLFW_KEY_KP_ADD => "equal",
            c.GLFW_KEY_LEFT_BRACKET => "[",
            c.GLFW_KEY_RIGHT_BRACKET => "]",
            c.GLFW_KEY_SEMICOLON => ";",
            c.GLFW_KEY_APOSTROPHE => "'",
            c.GLFW_KEY_COMMA => ",",
            c.GLFW_KEY_PERIOD => ".",
            c.GLFW_KEY_SLASH => "/",
            c.GLFW_KEY_BACKSLASH => "\\",
            c.GLFW_KEY_GRAVE_ACCENT => "`",
            else => null,
        };
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

    /// Active theme (builtin or plugin) with the configured text-color override.
    fn resolvedTheme(self: *App) theme_mod.Theme {
        const base = if (self.plugins.findTheme(self.config.theme_name)) |t|
            t
        else
            theme_mod.byName(self.config.theme_name);
        return theme_mod.withFgOverride(base, self.config.fg_preset);
    }

    fn refreshThemeColors(self: *App) void {
        const theme = self.resolvedTheme();
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
    }

    fn applyTheme(self: *App, name: []const u8) void {
        self.config.setThemeName(self.allocator, name) catch {
            self.setStatus("theme failed");
            return;
        };
        self.refreshThemeColors();
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

    fn openFolderWorkspace(self: *App) void {
        const path = folder_picker.pickFolder(self.allocator, self.io, struct {
            fn pump() void {
                Window.poll();
            }
        }.pump) catch {
            self.setStatus("folder picker failed");
            return;
        } orelse {
            // User cancelled — stay on current UI.
            return;
        };
        defer self.allocator.free(path);

        self.openFolderAsWorkspace(path) catch {
            self.setStatus("failed to open folder");
            return;
        };
    }

    fn openFolderAsWorkspace(self: *App, path: []const u8) !void {
        // Confirm the path is a readable directory before spawning a shell.
        const dir = std.Io.Dir.openDirAbsolute(self.io, path, .{}) catch return error.NotADirectory;
        dir.close(self.io);

        const name = folder_picker.folderBasename(path);
        try self.newTabInDir(path, name);
        self.workspaces.setCurrent(name) catch {};
        self.updateWindowTitle();
        self.fireHooks(.on_workspace_open);
        self.ui = .normal;
        self.setStatus("workspace opened");
    }

    fn openPicker(self: *App) void {
        self.workspaces.refresh() catch {};
        self.picker_index = 0;
        self.ui = .ws_picker;
        self.clearStatus();
    }

    fn openSavePrompt(self: *App) void {
        self.save_name_len = 0;
        if (self.workspaces.current_name) |n| {
            const len = @min(n.len, self.save_name.len);
            @memcpy(self.save_name[0..len], n[0..len]);
            self.save_name_len = len;
        }
        self.ui = .ws_save;
        self.clearStatus();
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
        try self.newTabInDir(self.sessionCwd(), null);
    }

    fn newTabInDir(self: *App, cwd: []const u8, title_opt: ?[]const u8) !void {
        const bounds = self.contentRect();
        const cols, const rows = self.gridSize(bounds.w, bounds.h);
        const theme = self.config.theme();

        var title_buf: [64]u8 = undefined;
        const title = if (title_opt) |t|
            t
        else
            (std.fmt.bufPrint(&title_buf, "Shell {d}", .{self.tabs.items.items.len + 1}) catch "Shell");

        const launch = self.config.resolveLaunchShell();
        if (self.config.shellPath()) |configured| {
            if (!std.mem.eql(u8, configured, launch)) {
                var warn: [96]u8 = undefined;
                const msg = std.fmt.bufPrint(&warn, "shell missing, using {s}", .{launch}) catch "shell fallback";
                self.setStatus(msg);
            }
        }

        const session = try Session.createWith(self.allocator, .{
            .cols = cols,
            .rows = rows,
            .title = title,
            .cwd = cwd,
            .shell = launch,
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
            .shell = self.config.resolveLaunchShell(),
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
        if (self.ui == .home and self.home.show_help) {
            const lines: i32 = @intFromFloat(-yoff * 3.0);
            self.home.scrollHelp(lines);
            return;
        }
        if (self.ui != .normal) return;
        const session = self.focused() orelse return;
        const lines: i32 = @intFromFloat(yoff * 3.0);
        session.screen.scrollView(lines);
    }
};
