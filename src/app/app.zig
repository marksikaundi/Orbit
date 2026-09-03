const std = @import("std");
const builtin = @import("builtin");
const c = @import("../c.zig").c;
const Window = @import("../window/window.zig").Window;
const Renderer = @import("../renderer/renderer.zig").Renderer;
const Session = @import("../terminal/session.zig").Session;
const Tabs = @import("../ui/tabs.zig").Tabs;
const layout_mod = @import("../ui/layout.zig");
const Rect = layout_mod.Rect;
const Search = @import("../ui/search.zig").Search;
const Viewer = @import("../ui/viewer.zig").Viewer;
const viewer_mod = @import("../ui/viewer.zig");
const Palette = @import("../ui/palette.zig").Palette;
const palette_mod = @import("../ui/palette.zig");
const bindings = @import("../ui/bindings.zig");
const home_mod = @import("../ui/home.zig");
const Home = home_mod.Home;
const ui_scale = @import("../ui/scale.zig");
const ui_chrome = @import("../ui/chrome.zig");
const Config = @import("../config/config.zig").Config;
const keybind_mod = @import("../config/keybind.zig");
const CursorStyle = @import("../config/config.zig").CursorStyle;
const theme_mod = @import("../config/theme.zig");
const WsManager = @import("../workspace/workspace.zig").Manager;
const PluginRegistry = @import("../plugins/registry.zig").Registry;
const PluginCommand = @import("../plugins/types.zig").PluginCommand;
const PluginKind = @import("../plugins/types.zig").PluginKind;
const plugin_types = @import("../plugins/types.zig");
const plugin_runner = @import("../plugins/runner.zig");
const plugin_result_mod = @import("../plugins/result.zig");
const plugin_bundled = @import("../plugins/bundled.zig");
const plugin_audit = @import("../security/plugin_audit.zig");
const clipboard = @import("../clipboard/clipboard.zig");
const folder_picker = @import("../platform/folder_picker.zig");
const macos_open = @import("../platform/macos_open.zig");
const Color = @import("../terminal/cell.zig").Color;
const dev_root = @import("../dev_root.zig");

const UiMode = enum { home, normal, search, viewer, ws_picker, ws_save, palette, ssh_prompt, settings, plugins, plugin_result };

const SettingsRow = enum(u8) {
    theme,
    text,
    font,
    face,
    look,
    opacity,
    padding,
    spacing,
    cursor,
    blink,
    prompt,
    shell,

    pub const count = std.meta.fields(SettingsRow).len;

    fn fromIndex(i: usize) SettingsRow {
        const n = @min(i, count - 1);
        return @enumFromInt(@as(u8, @intCast(n)));
    }
};

const StatusKind = enum { info, success, err };

/// Right-click terminal menu (Copy / Paste).
const ContextMenu = struct {
    x: i32,
    y: i32,
    /// 0 = Copy, 1 = Paste
    hover: usize = 1,
};

const context_menu_items = [_][]const u8{ "Copy", "Paste" };

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
    viewer: Viewer = .{},
    palette: Palette = .{},
    home: Home = .{},
    ui: UiMode = .home,
    picker_index: usize = 0,
    save_name: [64]u8 = undefined,
    save_name_len: usize = 0,
    ssh_host: [128]u8 = undefined,
    ssh_host_len: usize = 0,
    /// Inject `ssh -- host` only after the new tab's shell has printed a prompt.
    pending_ssh_len: usize = 0,
    pending_ssh_host: [128]u8 = undefined,
    status_msg: [96]u8 = undefined,
    status_len: usize = 0,
    /// Seconds (glfwGetTime) when the toast should disappear (0 = hidden).
    status_until: f64 = 0,
    /// Soft styling: success (green), error (warm), info (default).
    status_kind: StatusKind = .info,
    mouse_x: f64 = 0,
    mouse_y: f64 = 0,
    /// Right-click Copy/Paste menu over the terminal (null = closed).
    context_menu: ?ContextMenu = null,
    /// Settings row: theme, text, font, face, look, opacity, padding, spacing, cursor, blink, prompt, shell
    settings_row: usize = 0,
    /// Selected plugin index in the Plugins panel.
    plugin_row: usize = 0,
    plugin_result: plugin_result_mod.ResultView = undefined,
    /// In-progress key sequence (`ctrl+a` waiting for `n` in `ctrl+a>n`).
    seq: [keybind_mod.max_sequence]keybind_mod.Trigger = undefined,
    seq_len: u8 = 0,

    pub const LaunchOpts = struct {
        cwd: ?[]const u8 = null,
        title: ?[]const u8 = null,
        execute: []const []const u8 = &.{},
        wait_after_command: bool = false,
        skip_home: bool = false,
    };

    pub fn create(allocator: std.mem.Allocator, io: std.Io, opts: LaunchOpts) !*App {
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
        renderer.setFontFace(config.font_face);
        renderer.setFontSize(config.font_size);
        renderer.setLineHeight(config.line_height);
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
            .plugin_result = plugin_result_mod.ResultView.init(allocator),
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
        macos_open.install();
        self.applyLaunch(opts);
        self.drainExternalOpens();
        return self;
    }

    /// Keep Orbit config source_root fresh and export ORBIT_SOURCE_ROOT to child shells.
    fn publishSourceRoot(self: *App) void {
        dev_root.ensureRecorded(self.allocator, self.io);
        const root = dev_root.resolve(self.allocator, self.io) orelse return;
        defer self.allocator.free(root);
        @import("../platform/paths.zig").setEnv("ORBIT_SOURCE_ROOT", root);
    }

    pub fn destroy(self: *App) void {
        self.fireHooks(.on_unload);
        Window.active = null;
        Window.on_char = null;
        Window.on_key = null;
        Window.on_mouse_button = null;
        Window.on_cursor_pos = null;
        Window.on_scroll = null;
        self.plugin_result.deinit();
        self.plugins.deinit();
        self.workspaces.deinit();
        self.search.close(self.allocator);
        self.viewer.close(self.allocator);
        self.tabs.deinit();
        self.renderer.deinit();
        self.window.deinit();
        self.config.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn run(self: *App) !void {
        while (!self.window.shouldClose()) {
            Window.poll();
            self.drainExternalOpens();
            self.handleResize();
            self.tabs.tickAll();
            self.flushPendingSsh();
            self.pollTerminalStatus();
            self.tickStatus();
            self.reapExitedSessions();
            try self.draw();
            self.window.swap();
        }
    }

    /// When the user types `exit` (or the shell otherwise ends), close that pane/tab.
    fn reapExitedSessions(self: *App) void {
        if (self.ui != .normal and self.ui != .search and self.ui != .viewer) return;
        if (!self.tabs.pruneDead()) return;

        if (self.tabs.items.items.len == 0) {
            self.search.close(self.allocator);
            self.viewer.close(self.allocator);
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

        // Quiet tab strip — lift from background only (no theme-accent / cyan underlines).
        const tbg = self.renderer.theme.background;
        const tfg = self.renderer.theme.foreground;
        const bar_bg = Color.rgb(
            @intCast(@max(0, @as(i32, tbg.r) - 4)),
            @intCast(@max(0, @as(i32, tbg.g) - 4)),
            @intCast(@max(0, @as(i32, tbg.b) - 4)),
        );
        const active_bg = Color.rgb(
            @intCast(@min(255, @as(i32, tbg.r) + 14)),
            @intCast(@min(255, @as(i32, tbg.g) + 14)),
            @intCast(@min(255, @as(i32, tbg.b) + 16)),
        );
        const rule = Color.rgb(
            @intCast(@min(255, @as(i32, tbg.r) + 28)),
            @intCast(@min(255, @as(i32, tbg.g) + 28)),
            @intCast(@min(255, @as(i32, tbg.b) + 28)),
        );
        // Desaturate inactive labels toward gray so Solarized/Nord don't tint the chrome.
        const avg_fg = @divTrunc(@as(i32, tfg.r) + @as(i32, tfg.g) + @as(i32, tfg.b), 3);
        const avg_bg = @divTrunc(@as(i32, tbg.r) + @as(i32, tbg.g) + @as(i32, tbg.b), 3);
        const muted_v = @divTrunc(avg_fg + avg_bg * 2, 3);
        const muted_fg = Color.rgb(@intCast(muted_v), @intCast(muted_v), @intCast(muted_v));
        try self.renderer.drawRect(0, 0, self.window.fb_width, Tabs.bar_height, bar_bg, 1.0);
        try self.renderer.drawRect(0, Tabs.bar_height - 1, self.window.fb_width, 1, rule, 0.55);
        const cell_w_i: i32 = @intFromFloat(@max(1.0, self.renderer.cell_w));
        const cell_h_i: i32 = @intFromFloat(@max(1.0, self.renderer.cell_h));
        const tab_h: i32 = Tabs.bar_height - 2;
        const tab_y: i32 = 0;
        var x: i32 = 6;
        for (self.tabs.items.items, 0..) |tab, i| {
            const active = i == self.tabs.active;
            const title = tab.title[0..@min(tab.title.len, 16)];
            const text_w: i32 = @as(i32, @intCast(title.len)) * cell_w_i;
            const label_w: i32 = text_w + 28;
            if (active) {
                try self.renderer.drawRect(x, tab_y, label_w, tab_h, active_bg, 1.0);
                try self.renderer.drawRect(x + 8, Tabs.bar_height - 2, label_w - 16, 2, rule, 0.95);
            }
            const fg = if (active) tfg else muted_fg;
            const text_x = x + @divTrunc(label_w - text_w, 2);
            const text_y = tab_y + @divTrunc(tab_h - cell_h_i, 2);
            try self.renderer.drawText(text_x, text_y, title, fg);
            x += label_w + 2;
        }

        // Workspace name on the right (muted, same tone as inactive tabs)
        if (self.workspaces.current_name) |wn| {
            const label = wn[0..@min(wn.len, 20)];
            const lw: i32 = @as(i32, @intCast(label.len)) * cell_w_i + 20;
            const bx = self.window.fb_width - lw - 10;
            try self.renderer.drawText(bx + 8, 10, label, muted_fg);
        }

        const tab = self.tabs.current() orelse {
            // No shell yet — still draw overlays opened from home (settings, palette, …).
            // Only bounce to home when nothing is open.
            switch (self.ui) {
                .settings => try self.drawSettings(),
                .plugins => try self.drawPlugins(),
                .plugin_result => try self.drawPluginResult(),
                .palette => try self.drawPalette(),
                .ws_picker => try self.drawWorkspacePicker(),
                .ws_save => try self.drawSavePrompt(),
                .ssh_prompt => try self.drawSshPrompt(),
                .search => try self.drawSearch(),
                .viewer => try self.drawViewer(),
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
            }
        };
        var dctx: DrawCtx = .{ .app = self };
        tab.layout.forEachLeaf(bounds, *DrawCtx, &dctx, DrawCtx.cb);

        if (self.ui == .search) {
            try self.drawSearch();
        }
        if (self.ui == .viewer) {
            try self.drawViewer();
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
        if (self.ui == .plugin_result) {
            try self.drawPluginResult();
        }
        if (self.context_menu != null) {
            try self.drawContextMenu();
        }
        // Always on top of overlays so "saved" / theme notes stay readable.
        if (self.status_len > 0) {
            try self.drawStatusBar();
        }
    }

    fn contextMenuRect(self: *const App, menu: ContextMenu) Rect {
        const cw = @as(i32, @intFromFloat(@max(1.0, self.renderer.cell_w)));
        const ch = @as(i32, @intFromFloat(@max(1.0, self.renderer.cell_h)));
        const pad_x: i32 = 12;
        const pad_y: i32 = 6;
        const row_h = ch + 8;
        const w = cw * 10 + pad_x * 2;
        const h = pad_y * 2 + row_h * @as(i32, @intCast(context_menu_items.len));
        var x = menu.x;
        var y = menu.y;
        if (x + w > self.window.fb_width) x = @max(0, self.window.fb_width - w);
        if (y + h > self.window.fb_height) y = @max(0, self.window.fb_height - h);
        return .{ .x = x, .y = y, .w = w, .h = h };
    }

    fn contextMenuHit(self: *const App, menu: ContextMenu, px: i32, py: i32) ?usize {
        const r = self.contextMenuRect(menu);
        if (px < r.x or px >= r.x + r.w or py < r.y or py >= r.y + r.h) return null;
        const ch = @as(i32, @intFromFloat(@max(1.0, self.renderer.cell_h)));
        const pad_y: i32 = 6;
        const row_h = ch + 8;
        const rel = py - r.y - pad_y;
        if (rel < 0) return null;
        const idx: usize = @intCast(@divTrunc(rel, row_h));
        if (idx >= context_menu_items.len) return null;
        return idx;
    }

    fn overlayChrome(self: *const App) ui_chrome.Chrome {
        return ui_chrome.fromTheme(self.renderer.theme);
    }

    fn drawContextMenu(self: *App) !void {
        const menu = self.context_menu orelse return;
        const r = self.contextMenuRect(menu);
        const ch = @as(i32, @intFromFloat(@max(1.0, self.renderer.cell_h)));
        const pad_x: i32 = 12;
        const pad_y: i32 = 6;
        const row_h = ch + 8;
        const chrome = self.overlayChrome();
        const panel = chrome.panel;
        const accent = chrome.accent;
        const fg = chrome.fg;
        const muted = chrome.muted;
        const sel_bg = chrome.sel_bg;

        try self.renderer.drawRect(r.x, r.y, r.w, r.h, panel, 0.98);
        try self.renderer.drawRect(r.x, r.y, 2, r.h, accent, 0.7);

        const can_copy = if (self.focused()) |s| s.selection.active else false;
        for (context_menu_items, 0..) |label, i| {
            const ry = r.y + pad_y + @as(i32, @intCast(i)) * row_h;
            const enabled = i != 0 or can_copy;
            if (menu.hover == i and enabled) {
                try self.renderer.drawRect(r.x + 4, ry, r.w - 8, row_h - 2, sel_bg, 1.0);
            }
            const color = if (enabled) fg else muted;
            try self.renderer.drawText(r.x + pad_x, ry + 4, label, color);
        }
    }

    fn closeContextMenu(self: *App) void {
        self.context_menu = null;
    }

    fn openContextMenu(self: *App, fb_x: i32, fb_y: i32) void {
        self.context_menu = .{ .x = fb_x, .y = fb_y, .hover = 1 };
    }

    fn runContextMenuItem(self: *App, index: usize) void {
        switch (index) {
            0 => self.copySelection(),
            1 => self.pasteClipboard(),
            else => {},
        }
        self.closeContextMenu();
    }

    fn drawPalette(self: *App) !void {
        const fb_w = self.window.fb_width;
        const fb_h = self.window.fb_height;
        const ui = ui_scale.uiScale(fb_w, fb_h, self.renderer.content_scale);
        const title_s = ui * 1.12;
        const base_cw = @as(i32, @intFromFloat(self.renderer.cell_w));
        const base_ch = @as(i32, @intFromFloat(self.renderer.cell_h));
        const cw = ui_scale.scaled(base_cw, ui);
        const ch = ui_scale.scaled(base_ch, ui);
        const title_ch = ui_scale.scaled(base_ch, title_s);

        const chrome = self.overlayChrome();

        // Dim with theme background so overlays stay uniform with Help / the active theme.
        try self.renderer.drawRect(0, 0, fb_w, fb_h, chrome.bg, 0.55);

        const pad_x = @max(cw + 8, @as(i32, @intFromFloat(@round(22.0 * ui))));
        const pad_y = @max(@divTrunc(ch, 2) + 6, @as(i32, @intFromFloat(@round(18.0 * ui))));
        const row_h = ch + @divTrunc(ch, 2) + @max(4, @divTrunc(ch, 5));
        const title_h = title_ch + @divTrunc(ch, 3);
        const search_h = ch + @divTrunc(ch, 2) + @max(8, @divTrunc(ch, 4));
        const footer_h = ch + pad_y;
        const gap = @max(@divTrunc(ch, 2), @as(i32, @intFromFloat(@round(12.0 * ui))));
        const accent_h = @max(2, @divTrunc(ch, 10));

        const w = ui_scale.panelWidth(fb_w, cw, 52, @as(i32, @intFromFloat(@round(560.0 * ui))));
        const chrome_h = title_h + search_h + footer_h + gap * 3 + pad_y * 2;
        const max_rows_by_height = @max(1, @divTrunc(fb_h - chrome_h - ch * 2, row_h));
        const max_visible: usize = @min(16, @as(usize, @intCast(max_rows_by_height)));

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
        const y = @max(ch * 2, @divTrunc(fb_h - h, 6));

        const panel = chrome.panel;
        const field = chrome.field;
        const fg = chrome.fg;
        const muted = chrome.muted;
        const dim = chrome.dim;
        const accent = chrome.accent;
        const sel_bg = chrome.sel_bg;
        const rule = chrome.rule;

        try self.renderer.drawRect(x, y, w, h, panel, 0.98);
        try self.renderer.drawRect(x, y, w, accent_h, accent, 0.55);

        var cy = y + pad_y;
        try self.renderer.drawTextScaled(x + pad_x, cy, "Command Palette", fg, title_s);
        const kbd = "Ctrl+Shift+P";
        const kbd_x = x + w - pad_x - @as(i32, @intCast(kbd.len)) * cw;
        try self.renderer.drawTextScaled(kbd_x, cy + @divTrunc(title_ch - ch, 2), kbd, dim, ui);
        cy += title_h;

        // Search field
        try self.renderer.drawRect(x + pad_x - 4, cy - 4, w - pad_x * 2 + 8, search_h, field, 1.0);
        try self.renderer.drawRect(x + pad_x - 4, cy - 4, accent_h, search_h, accent, 0.35);
        var qbuf: [96]u8 = undefined;
        const query = self.palette.querySlice();
        const qline = if (query.len == 0)
            "Type to filter commands..."
        else
            (std.fmt.bufPrint(&qbuf, "> {s}", .{query}) catch "> ");
        const qcolor = if (query.len == 0) dim else accent;
        try self.renderer.drawTextScaled(x + pad_x + 8, cy + @divTrunc(search_h - ch, 2) - 2, qline, qcolor, ui);
        cy += search_h + gap;

        try self.renderer.drawRect(x + pad_x - 4, cy - @divTrunc(gap, 2), w - pad_x * 2 + 8, 1, rule, 0.9);

        if (self.palette.match_count == 0) {
            try self.renderer.drawTextScaled(x + pad_x, cy + @divTrunc(row_h - ch, 2), "No matching commands", muted, ui);
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
                    try self.renderer.drawRect(x + 10, ry, @max(3, @divTrunc(cw, 4)), row_h - 2, accent, 1.0);
                }

                const label_len = @min(entry.label.len, @as(usize, @intCast(label_max_cols)));
                try self.renderer.drawTextScaled(x + pad_x + 8, text_y, entry.label[0..label_len], fg, ui);

                if (entry.hint.len > 0) {
                    const hint_len = @min(entry.hint.len, 18);
                    const hx = x + w - pad_x - @as(i32, @intCast(hint_len)) * cw;
                    try self.renderer.drawTextScaled(hx, text_y, entry.hint[0..hint_len], muted, ui);
                }
            }
        }

        var foot: [64]u8 = undefined;
        const foot_line = if (self.palette.query_len > 0 and self.palette.match_count > 0)
            (std.fmt.bufPrint(&foot, "{d} matches   Enter run   Esc close", .{self.palette.match_count}) catch "Enter run   Esc close")
        else
            "Up/Down move   Enter run   Esc close";
        try self.renderer.drawTextScaled(x + pad_x, y + h - footer_h + @divTrunc(pad_y, 2), foot_line, dim, ui);
    }

    fn drawSearch(self: *App) !void {
        const cw = @as(i32, @intFromFloat(self.renderer.cell_w));
        const ch = @as(i32, @intFromFloat(self.renderer.cell_h));
        const fb_w = self.window.fb_width;
        const fb_h = self.window.fb_height;
        const chrome = self.overlayChrome();

        try self.renderer.drawRect(0, 0, fb_w, fb_h, chrome.bg, 0.55);

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

        const panel = chrome.panel;
        const fg = chrome.fg;
        const muted = chrome.muted;
        const dim = chrome.dim;
        const accent = chrome.accent;
        const sel_bg = chrome.sel_bg;

        try self.renderer.drawRect(x, y, w, h, panel, 0.98);
        try self.renderer.drawRect(x, y, w, 2, accent, 0.55);

        var cy = y + pad_y;
        try self.renderer.drawText(x + pad_x, cy, "Search", fg);
        cy += title_h;

        // Mode tabs
        const term_label = if (self.search.mode == .terminal) "[ Terminal ]" else "  Terminal  ";
        const files_label = if (self.search.mode == .files) "[ Files ]" else "  Files  ";
        const code_label = if (self.search.mode == .code) "[ Code ]" else "  Code  ";
        try self.renderer.drawText(x + pad_x, cy, term_label, if (self.search.mode == .terminal) accent else muted);
        try self.renderer.drawText(x + pad_x + cw * 14, cy, files_label, if (self.search.mode == .files) accent else muted);
        try self.renderer.drawText(x + pad_x + cw * 24, cy, code_label, if (self.search.mode == .code) accent else muted);
        try self.renderer.drawText(x + w - pad_x - cw * 12, cy, "Tab switch", dim);
        cy += mode_h;

        try self.renderer.drawRect(x + pad_x - 4, cy - 4, w - pad_x * 2 + 8, search_h, chrome.field, 1.0);
        var qbuf: [96]u8 = undefined;
        const query = self.search.querySlice();
        const placeholder = switch (self.search.mode) {
            .terminal => "Find in terminal...",
            .files => "Find files by name...",
            .code => "Find code in files...",
        };
        const qline = if (query.len == 0) placeholder else (std.fmt.bufPrint(&qbuf, "> {s}", .{query}) catch "> ");
        try self.renderer.drawText(x + pad_x + 4, cy + @divTrunc(search_h - ch, 2) - 2, qline, if (query.len == 0) dim else accent);
        cy += search_h + gap;

        try self.renderer.drawRect(x + pad_x - 4, cy - @divTrunc(gap, 2), w - pad_x * 2 + 8, 1, chrome.rule, 0.9);

        if (query.len == 0) {
            const hint = switch (self.search.mode) {
                .terminal => "Type to search scrollback and the visible screen",
                .files => "Type to search file names in the opened folder",
                .code => "Type to search inside files, then Enter to open at that line",
            };
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

                var line_buf: [160]u8 = undefined;
                const line: []const u8 = switch (self.search.mode) {
                    .terminal => blk: {
                        const hit = self.search.term_hits[mi];
                        break :blk (std.fmt.bufPrint(&line_buf, "line {d}  col {d}", .{ hit.abs_row + 1, hit.col + 1 }) catch "hit");
                    },
                    .files => self.search.file_hits[mi],
                    .code => blk: {
                        const hit = self.search.code_hits[mi];
                        break :blk (std.fmt.bufPrint(
                            &line_buf,
                            "{s}:{d}  {s}",
                            .{ hit.rel, hit.line + 1, hit.snippetSlice() },
                        ) catch hit.rel);
                    },
                };
                const shown = line[0..@min(line.len, @as(usize, @intCast(label_max)))];
                try self.renderer.drawText(x + pad_x + 6, text_y, shown, fg);
            }
        }

        var foot: [96]u8 = undefined;
        const foot_line = if (hit_n > 0)
            (std.fmt.bufPrint(&foot, "{d} matches   Enter open   Shift+Enter insert   Esc", .{hit_n}) catch "Enter open   Esc close")
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
            .code => {
                if (self.focused()) |s| {
                    self.search.setRoot(self.allocator, s.cwd) catch {};
                }
                self.search.refreshCode(self.allocator, self.io);
            },
        }
    }

    fn handleSearchKey(self: *App, key: c_int, shift: bool) void {
        switch (key) {
            c.GLFW_KEY_ESCAPE => {
                self.search.close(self.allocator);
                if (self.viewer.active) {
                    self.ui = .viewer;
                } else {
                    self.leaveOverlay();
                }
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
            c.GLFW_KEY_ENTER => self.activateSearchSelection(shift),
            else => {},
        }
    }

    fn activateSearchSelection(self: *App, insert_path: bool) void {
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
            .files, .code => {
                const rel = self.search.selectedFilePath() orelse {
                    self.setStatus("no file selected");
                    return;
                };
                if (insert_path) {
                    if (self.focused()) |s| {
                        s.write(rel);
                        s.write(" ");
                    }
                    self.search.close(self.allocator);
                    if (self.viewer.active) {
                        self.ui = .viewer;
                    } else {
                        self.ui = .normal;
                    }
                    var buf: [96]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, "inserted {s}", .{rel}) catch "file inserted";
                    self.setStatus(msg);
                    return;
                }
                const abs = self.search.selectedFileAbsolute(self.allocator) catch {
                    self.setStatus("could not open file");
                    return;
                } orelse {
                    self.setStatus("no file selected");
                    return;
                };
                defer self.allocator.free(abs);
                const code = self.search.selectedCodeHit();
                const goto_line: ?usize = if (code) |h| h.line else null;
                const goto_col: usize = if (code) |h| h.col else 0;
                var qbuf: [64]u8 = undefined;
                const q = self.search.querySlice();
                const qn = @min(q.len, qbuf.len);
                @memcpy(qbuf[0..qn], q[0..qn]);
                const from_code = self.search.mode == .code;
                self.openViewerPath(abs, rel);
                if (goto_line) |row| self.viewer.goTo(row, goto_col);
                if (from_code and qn > 0) {
                    @memcpy(self.viewer.find_query[0..qn], qbuf[0..qn]);
                    self.viewer.find_len = qn;
                    self.viewer.openFind();
                }
                self.search.close(self.allocator);
            },
        }
    }

    fn drawSshPrompt(self: *App) !void {
        const chrome = self.overlayChrome();
        const fb_w = self.window.fb_width;
        const fb_h = self.window.fb_height;
        try self.renderer.drawRect(0, 0, fb_w, fb_h, chrome.bg, 0.55);
        const w: i32 = 440;
        const h: i32 = 90;
        const x = @divTrunc(fb_w - w, 2);
        const y = @divTrunc(fb_h - h, 2);
        try self.renderer.drawRect(x, y, w, h, chrome.panel, 0.98);
        try self.renderer.drawRect(x, y, w, 2, chrome.accent, 0.55);
        try self.renderer.drawText(x + 16, y + 14, "SSH", chrome.fg);
        var buf: [160]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "Host: {s}", .{self.ssh_host[0..self.ssh_host_len]}) catch "Host:";
        try self.renderer.drawText(x + 16, y + 42, label, chrome.muted);
        try self.renderer.drawText(x + 16, y + 66, "Enter connect  |  Esc cancel", chrome.dim);
    }

    fn drawSettings(self: *App) !void {
        const fb_w = self.window.fb_width;
        const fb_h = self.window.fb_height;
        const ui = ui_scale.uiScale(fb_w, fb_h, self.renderer.content_scale);
        const title_s = ui * 1.12;
        const base_cw = @as(i32, @intFromFloat(self.renderer.cell_w));
        const base_ch = @as(i32, @intFromFloat(self.renderer.cell_h));
        const cw = ui_scale.scaled(base_cw, ui);
        const ch = ui_scale.scaled(base_ch, ui);
        const title_ch = ui_scale.scaled(base_ch, title_s);

        const chrome = self.overlayChrome();
        try self.renderer.drawRect(0, 0, fb_w, fb_h, chrome.bg, 0.55);

        const pad_x = @max(cw + 10, @as(i32, @intFromFloat(@round(26.0 * ui))));
        const pad_y = @max(@divTrunc(ch, 2) + 8, @as(i32, @intFromFloat(@round(22.0 * ui))));
        const row_h = ch + @divTrunc(ch, 2) + @max(8, @divTrunc(ch, 4));
        const title_h = title_ch + @divTrunc(ch, 4);
        const subtitle_h = ch + @divTrunc(ch, 2);
        const gap = @max(@divTrunc(ch, 2), @as(i32, @intFromFloat(@round(14.0 * ui))));
        const footer_lines = 3;
        const footer_h = footer_lines * (ch + @max(4, @divTrunc(ch, 5))) + pad_y;
        const accent_h = @max(2, @divTrunc(ch, 10));

        const w = ui_scale.panelWidth(fb_w, cw, 48, @as(i32, @intFromFloat(@round(540.0 * ui))));
        const header_h = pad_y + title_h + subtitle_h + gap;
        const avail = @max(row_h, fb_h - header_h - footer_h - ch * 2);
        const max_visible: usize = @max(1, @as(usize, @intCast(@divTrunc(avail, row_h))));
        const total = SettingsRow.count;
        const visible = @min(total, max_visible);
        const list_h = @as(i32, @intCast(visible)) * row_h;
        const h = header_h + list_h + gap + footer_h;
        const x = @divTrunc(fb_w - w, 2);
        const y = @max(ch, @divTrunc(fb_h - h, 2));

        const panel = chrome.panel;
        const fg = chrome.fg;
        const muted = chrome.muted;
        const dim = chrome.dim;
        const accent = chrome.accent;
        const sel_bg = chrome.sel_bg;
        const rule = chrome.rule;

        try self.renderer.drawRect(x, y, w, h, panel, 0.98);
        try self.renderer.drawRect(x, y, w, accent_h, accent, 0.55);

        var cy = y + pad_y;
        try self.renderer.drawTextScaled(x + pad_x, cy, "Appearance", fg, title_s);
        cy += title_h;
        try self.renderer.drawTextScaled(x + pad_x, cy, "Ghostty-style look, prompt, and shell", muted, ui);
        cy += subtitle_h + gap;

        try self.renderer.drawRect(x + pad_x - 4, cy - @divTrunc(gap, 2), w - pad_x * 2 + 8, 1, rule, 0.9);

        var size_buf: [16]u8 = undefined;
        const size_str = std.fmt.bufPrint(&size_buf, "{d:.0}pt", .{self.renderer.font_size}) catch "14pt";
        var opacity_buf: [16]u8 = undefined;
        const opacity_str = std.fmt.bufPrint(&opacity_buf, "{d:.0}%", .{self.config.opacity * 100.0}) catch "100%";
        var pad_buf: [24]u8 = undefined;
        const pad_str = std.fmt.bufPrint(&pad_buf, "{d}×{d}", .{
            self.config.padding_x,
            self.config.padding_y,
        }) catch "10×6";
        const rows = [_]struct { label: []const u8, value: []const u8 }{
            .{ .label = "Theme", .value = self.config.theme_name },
            .{ .label = "Text", .value = self.config.fgDisplay() },
            .{ .label = "Font", .value = size_str },
            .{ .label = "Face", .value = self.config.fontFaceDisplay() },
            .{ .label = "Look", .value = self.config.look.name() },
            .{ .label = "Opacity", .value = opacity_str },
            .{ .label = "Padding", .value = pad_str },
            .{ .label = "Spacing", .value = self.config.lineHeightDisplay() },
            .{ .label = "Cursor", .value = self.config.cursor_style.name() },
            .{ .label = "Blink", .value = if (self.config.cursor_blink) "on" else "off" },
            .{ .label = "Prompt", .value = self.config.prompt.name() },
            .{ .label = "Shell", .value = self.config.shellDisplay() },
        };

        if (self.settings_row >= rows.len) self.settings_row = rows.len - 1;
        var start: usize = 0;
        if (self.settings_row >= visible) {
            start = self.settings_row + 1 - visible;
        }

        var value_buf: [96]u8 = undefined;
        const value_col_w = @divTrunc(w * 11, 20);
        const list_top = cy;
        var shown: usize = 0;
        while (shown < visible) : (shown += 1) {
            const i = start + shown;
            const row = rows[i];
            const ry = list_top + @as(i32, @intCast(shown)) * row_h;
            const text_y = ry + @divTrunc(row_h - ch, 2);
            const selected = i == self.settings_row;

            if (selected) {
                try self.renderer.drawRect(x + 10, ry, w - 20, row_h - 2, sel_bg, 1.0);
                try self.renderer.drawRect(x + 10, ry, @max(3, @divTrunc(cw, 4)), row_h - 2, accent, 1.0);
            }

            try self.renderer.drawTextScaled(x + pad_x + 8, text_y, row.label, if (selected) fg else muted, ui);

            const value_text = if (selected)
                (std.fmt.bufPrint(&value_buf, "< {s} >", .{row.value}) catch row.value)
            else
                row.value;
            const max_val_cols = @max(8, @divTrunc(value_col_w - pad_x, cw));
            const value_len = @min(value_text.len, @as(usize, @intCast(max_val_cols)));
            const vx = x + w - pad_x - @as(i32, @intCast(value_len)) * cw;
            try self.renderer.drawTextScaled(vx, text_y, value_text[0..value_len], if (selected) accent else muted, ui);
        }

        cy = y + h - footer_h;
        try self.renderer.drawRect(x + pad_x - 4, cy - @divTrunc(gap, 2), w - pad_x * 2 + 8, 1, rule, 0.9);

        const more = if (start > 0 or start + visible < rows.len) "  (scroll)" else "";
        var info: [96]u8 = undefined;
        const hint = std.fmt.bufPrint(&info, "Look sets padding + spacing + opacity{s}", .{more}) catch "Look sets padding + spacing + opacity";
        try self.renderer.drawTextScaled(x + pad_x, cy, hint, muted, ui);
        cy += ch + @max(6, @divTrunc(ch, 4));
        try self.renderer.drawTextScaled(x + pad_x, cy, "Up/Down select    Left/Right change    S save", dim, ui);
        cy += ch + @max(6, @divTrunc(ch, 4));
        try self.renderer.drawTextScaled(x + pad_x, cy, "Prompt applies to new tabs    Esc close", dim, ui);
    }

    fn drawPlugins(self: *App) !void {
        const fb_w = self.window.fb_width;
        const fb_h = self.window.fb_height;
        const ui = ui_scale.uiScale(fb_w, fb_h, self.renderer.content_scale);
        const title_s = ui * 1.12;
        const base_cw = @as(i32, @intFromFloat(self.renderer.cell_w));
        const base_ch = @as(i32, @intFromFloat(self.renderer.cell_h));
        const cw = ui_scale.scaled(base_cw, ui);
        const ch = ui_scale.scaled(base_ch, ui);
        const title_ch = ui_scale.scaled(base_ch, title_s);

        const chrome = self.overlayChrome();
        try self.renderer.drawRect(0, 0, fb_w, fb_h, chrome.bg, 0.55);

        const pad_x = @max(cw + 8, @as(i32, @intFromFloat(@round(22.0 * ui))));
        const pad_y = @max(@divTrunc(ch, 2) + 8, @as(i32, @intFromFloat(@round(20.0 * ui))));
        const gap = @max(@divTrunc(ch, 2), @as(i32, @intFromFloat(@round(12.0 * ui))));
        const list_row_h = ch + @divTrunc(ch, 2) + @max(4, @divTrunc(ch, 6));
        const accent_h = @max(2, @divTrunc(ch, 10));
        const plugin_n = self.plugins.count();

        const w = ui_scale.panelWidthWide(fb_w, cw, 68, @as(i32, @intFromFloat(@round(760.0 * ui))));
        const header_h = pad_y + title_ch + @divTrunc(ch, 4) + gap;
        const footer_h = ch + pad_y;
        const min_body = list_row_h * 8;
        const max_h = fb_h - ch * 2;
        const h = @min(max_h, @max(header_h + min_body + footer_h, @divTrunc(fb_h * 11, 18)));
        const x = @divTrunc(fb_w - w, 2);
        const y = @max(ch, @divTrunc(fb_h - h, 2));

        const list_w = @max(cw * 16, @min(@divTrunc(w * 2, 5), cw * 24));
        const body_top = y + header_h;
        const body_h = h - header_h - footer_h;
        const list_top = body_top + @divTrunc(ch, 4);
        const max_visible: usize = @max(1, @as(usize, @intCast(@divTrunc(body_h - @divTrunc(ch, 2), list_row_h))));

        const panel = chrome.panel;
        const fg = chrome.fg;
        const muted = chrome.muted;
        const dim = chrome.dim;
        const accent = chrome.accent;
        const sel_bg = chrome.sel_bg;
        const rule = chrome.rule;
        const on_col = chrome.on_col;
        const off_col = chrome.off_col;

        try self.renderer.drawRect(x, y, w, h, panel, 0.98);
        try self.renderer.drawRect(x, y, w, accent_h, accent, 0.55);

        var enabled_n: usize = 0;
        for (self.plugins.plugins.items) |p| {
            if (p.enabled) enabled_n += 1;
        }

        var cy = y + pad_y;
        try self.renderer.drawTextScaled(x + pad_x, cy, "Plugins", fg, title_s);

        var count_buf: [48]u8 = undefined;
        const count_line = if (plugin_n == 0)
            "none installed"
        else
            (std.fmt.bufPrint(&count_buf, "{d} of {d} on", .{ enabled_n, plugin_n }) catch "");
        const count_x = x + w - pad_x - @as(i32, @intCast(count_line.len)) * cw;
        try self.renderer.drawTextScaled(count_x, cy + @divTrunc(title_ch - ch, 2), count_line, muted, ui);

        try self.renderer.drawRect(x, y + header_h - 1, w, 1, rule, 0.9);

        if (plugin_n == 0) {
            const empty_y = body_top + @divTrunc(body_h - ch * 3, 2);
            const centerLine = struct {
                fn xFor(panel_x: i32, panel_w: i32, text: []const u8, cell_w: i32) i32 {
                    return panel_x + @divTrunc(panel_w - @as(i32, @intCast(text.len)) * cell_w, 2);
                }
            }.xFor;
            const l1 = "No plugins installed";
            const l2 = "Press I to install the bundled pack";
            const l3 = "hello   git   format   lint   ai   keys   themes";
            try self.renderer.drawTextScaled(centerLine(x, w, l1, cw), empty_y, l1, fg, ui);
            try self.renderer.drawTextScaled(centerLine(x, w, l2, cw), empty_y + ch + 6, l2, muted, ui);
            try self.renderer.drawTextScaled(centerLine(x, w, l3, cw), empty_y + ch * 2 + 12, l3, dim, ui);
        } else {
            try self.renderer.drawRect(x, body_top, list_w, body_h, chrome.field, 1.0);
            try self.renderer.drawRect(x + list_w, body_top, 1, body_h, rule, 0.9);

            if (self.plugin_row >= plugin_n) self.plugin_row = plugin_n - 1;
            var start: usize = 0;
            if (self.plugin_row >= max_visible) {
                start = self.plugin_row + 1 - max_visible;
            }
            const visible = @min(plugin_n - start, max_visible);
            const pill_w = cw * 3 + 10;
            const name_max = @max(4, @divTrunc(list_w - pad_x * 2 - pill_w - cw * 3, cw));
            const bar_w = @max(3, @divTrunc(cw, 4));

            var i: usize = 0;
            while (i < visible) : (i += 1) {
                const mi = start + i;
                const p = self.plugins.plugins.items[mi];
                const ry = list_top + @as(i32, @intCast(i)) * list_row_h;
                const selected = mi == self.plugin_row;
                const row_h = list_row_h - 2;
                const text_y = ry + @divTrunc(list_row_h - ch, 2);

                if (selected) {
                    try self.renderer.drawRect(x + 6, ry, list_w - 12, row_h, sel_bg, 1.0);
                    try self.renderer.drawRect(x + 6, ry, bar_w, row_h, accent, 1.0);
                }

                const dot = @max(5, @divTrunc(ch, 4));
                const dot_x = x + pad_x;
                const dot_y = text_y + @divTrunc(ch - dot, 2);
                try self.renderer.drawRect(dot_x, dot_y, dot, dot, if (p.enabled) on_col else off_col, if (p.enabled) 1.0 else 0.55);

                const name_x = dot_x + dot + @divTrunc(cw, 2) + 2;
                const shown = clipUiText(p.name, name_max);
                try self.renderer.drawTextScaled(name_x, text_y, shown, if (selected) fg else if (p.enabled) muted else dim, ui);

                const state: []const u8 = if (p.enabled) "ON" else "OFF";
                const pill_h = ch + 2;
                const pill_x = x + list_w - pad_x - pill_w + 4;
                const pill_y = ry + @divTrunc(list_row_h - pill_h, 2);
                const pill_col = if (p.enabled) on_col else off_col;
                try self.renderer.drawRect(pill_x, pill_y, pill_w, pill_h, pill_col, 0.22);
                const state_x = pill_x + @divTrunc(pill_w - @as(i32, @intCast(state.len)) * cw, 2);
                try self.renderer.drawTextScaled(state_x, pill_y + 1, state, pill_col, ui);
            }

            if (plugin_n > max_visible) {
                const track_h = body_h - 16;
                const thumb_h = @max(10, @divTrunc(track_h * @as(i32, @intCast(max_visible)), @as(i32, @intCast(plugin_n))));
                const travel = plugin_n - max_visible;
                const thumb_y = body_top + 8 + @divTrunc((track_h - thumb_h) * @as(i32, @intCast(start)), @as(i32, @intCast(travel)));
                try self.renderer.drawRect(x + list_w - 4, thumb_y, 2, thumb_h, accent, 0.45);
            }

            try self.drawPluginDetail(
                &self.plugins.plugins.items[self.plugin_row],
                x + list_w,
                body_top,
                w - list_w,
                body_h,
                pad_x,
                cw,
                ch,
                ui,
                title_s,
                title_ch,
                chrome,
            );
        }

        cy = y + h - footer_h + @divTrunc(pad_y, 2) - 2;
        try self.renderer.drawRect(x, y + h - footer_h, w, 1, rule, 0.9);
        const foot = "Up/Down select   Space on/off   I install   U remove   R reload   Esc";
        try self.renderer.drawTextScaled(x + pad_x, cy, clipUiText(foot, @divTrunc(w - pad_x * 2, cw)), dim, ui);
    }

    fn drawPluginDetail(
        self: *App,
        p: *const plugin_types.Plugin,
        x: i32,
        y: i32,
        w: i32,
        h: i32,
        pad_x: i32,
        cw: i32,
        ch: i32,
        ui: f32,
        title_s: f32,
        title_ch: i32,
        chrome: ui_chrome.Chrome,
    ) !void {
        const fg = chrome.fg;
        const muted = chrome.muted;
        const dim = chrome.dim;
        const accent = chrome.accent;
        const off_col = chrome.off_col;
        const kind_col = self.pluginKindColor(p.kind);
        const dx = x + pad_x;
        const inner_w = w - pad_x * 2;
        const bottom = y + h - @divTrunc(ch, 3);
        var dy = y + pad_x;

        const name_max = @max(4, @divTrunc(inner_w, cw));
        try self.renderer.drawTextScaled(dx, dy, clipUiText(p.name, name_max), if (p.enabled) fg else muted, title_s);
        dy += title_ch + @divTrunc(ch, 4);

        const badge = p.kind.badge();
        const badge_w = @as(i32, @intCast(badge.len)) * cw + 10;
        const badge_h = ch + 4;
        try self.renderer.drawRect(dx, dy - 1, badge_w, badge_h, kind_col, 0.22);
        try self.renderer.drawTextScaled(dx + 5, dy + 1, badge, kind_col, ui);

        var ver_buf: [24]u8 = undefined;
        const ver = std.fmt.bufPrint(&ver_buf, "v{s}", .{p.version}) catch "";
        var meta_buf: [64]u8 = undefined;
        const meta = std.fmt.bufPrint(&meta_buf, "{s}  ·  {s}", .{ ver, p.kind.label() }) catch p.kind.label();
        try self.renderer.drawTextScaled(dx + badge_w + cw, dy + 1, clipUiText(meta, @divTrunc(inner_w - badge_w - cw, cw)), dim, ui);
        dy += badge_h + @divTrunc(ch, 2);

        if (!p.enabled) {
            try self.renderer.drawTextScaled(dx, dy, "Disabled  —  Space to enable", off_col, ui);
            dy += ch + @divTrunc(ch, 3);
        }

        const desc = if (p.description.len > 0) p.description else "No description";
        const desc_cols = @max(8, @as(usize, @intCast(@divTrunc(inner_w, cw))));
        var rest: []const u8 = desc;
        var line_i: usize = 0;
        while (line_i < 3 and rest.len > 0 and dy + ch < bottom) : (line_i += 1) {
            const step = wrapUiText(rest, desc_cols);
            try self.renderer.drawTextScaled(dx, dy, step.line, muted, ui);
            dy += ch + 2;
            rest = step.rest;
        }
        dy += @divTrunc(ch, 3);

        var stats_buf: [80]u8 = undefined;
        var stats_len: usize = 0;
        const appendStat = struct {
            fn go(buf: []u8, len: *usize, n: usize, label: []const u8) void {
                if (n == 0) return;
                if (len.* > 0) {
                    const sep = "  ·  ";
                    if (len.* + sep.len >= buf.len) return;
                    @memcpy(buf[len.*..][0..sep.len], sep);
                    len.* += sep.len;
                }
                const piece = std.fmt.bufPrint(buf[len.*..], "{d} {s}", .{ n, label }) catch return;
                len.* += piece.len;
            }
        }.go;
        appendStat(&stats_buf, &stats_len, p.commands.len, "commands");
        appendStat(&stats_buf, &stats_len, p.themes.len, "themes");
        appendStat(&stats_buf, &stats_len, p.bindings.len, "shortcuts");
        if (p.tool.hasRunner()) appendStat(&stats_buf, &stats_len, 1, "tool");
        if (stats_len > 0 and dy + ch < bottom) {
            try self.renderer.drawTextScaled(dx, dy, clipUiText(stats_buf[0..stats_len], @as(i32, @intCast(desc_cols))), dim, ui);
            dy += ch + @divTrunc(ch, 2);
        }

        if (dy + ch * 2 < bottom) {
            try self.renderer.drawTextScaled(dx, dy, "Provides", accent, ui);
            dy += ch + @divTrunc(ch, 4);

            var shown: usize = 0;
            for (p.commands) |cmd| {
                if (dy + ch > bottom) break;
                const label = clipUiText(cmd.label, @as(i32, @intCast(desc_cols)) - 2);
                try self.renderer.drawTextScaled(dx, dy, "·", dim, ui);
                try self.renderer.drawTextScaled(dx + cw * 2, dy, label, fg, ui);
                dy += ch + 2;
                shown += 1;
            }
            for (p.themes) |th| {
                if (dy + ch > bottom) break;
                const label = clipUiText(th.name, @as(i32, @intCast(desc_cols)) - 2);
                try self.renderer.drawTextScaled(dx, dy, "·", dim, ui);
                try self.renderer.drawTextScaled(dx + cw * 2, dy, label, muted, ui);
                dy += ch + 2;
                shown += 1;
            }
            if (p.tool.hasRunner() and dy + ch <= bottom) {
                const runner = p.tool.script orelse p.tool.command orelse "tool";
                var run_buf: [64]u8 = undefined;
                const run_line = std.fmt.bufPrint(&run_buf, "runs {s}", .{runner}) catch runner;
                try self.renderer.drawTextScaled(dx, dy, "·", dim, ui);
                try self.renderer.drawTextScaled(dx + cw * 2, dy, clipUiText(run_line, @as(i32, @intCast(desc_cols)) - 2), muted, ui);
                dy += ch + 2;
                shown += 1;
            }
            if (shown == 0 and dy + ch <= bottom) {
                try self.renderer.drawTextScaled(dx + cw * 2, dy, "nothing registered", dim, ui);
            }
        }
    }

    fn pluginKindColor(self: *const App, kind: PluginKind) Color {
        const ansi = self.renderer.theme.ansi;
        return switch (kind) {
            .commands => ansi[4],
            .theme => ansi[5],
            .keys => ansi[6],
            .format => ansi[2],
            .lint => ansi[3],
            .ai => ansi[13],
        };
    }

    fn drawWorkspacePicker(self: *App) !void {
        const fb_w = self.window.fb_width;
        const fb_h = self.window.fb_height;
        const ui = ui_scale.uiScale(fb_w, fb_h, self.renderer.content_scale);
        const title_s = ui * 1.12;
        const base_cw = @as(i32, @intFromFloat(self.renderer.cell_w));
        const base_ch = @as(i32, @intFromFloat(self.renderer.cell_h));
        const cw = ui_scale.scaled(base_cw, ui);
        const ch = ui_scale.scaled(base_ch, ui);
        const title_ch = ui_scale.scaled(base_ch, title_s);

        const chrome = self.overlayChrome();
        try self.renderer.drawRect(0, 0, fb_w, fb_h, chrome.bg, 0.55);

        const pad_x = @max(cw + 10, @as(i32, @intFromFloat(@round(26.0 * ui))));
        const pad_y = @max(@divTrunc(ch, 2) + 8, @as(i32, @intFromFloat(@round(22.0 * ui))));
        const row_h = ch + @divTrunc(ch, 2) + @max(6, @divTrunc(ch, 5));
        const title_h = title_ch + @divTrunc(ch, 4);
        const subtitle_h = ch + @divTrunc(ch, 3);
        const gap = @max(@divTrunc(ch, 2), @as(i32, @intFromFloat(@round(12.0 * ui))));
        const footer_h = ch + pad_y;
        const accent_h = @max(2, @divTrunc(ch, 10));
        const name_n = self.workspaces.names.items.len;

        const w = ui_scale.panelWidth(fb_w, cw, 44, @as(i32, @intFromFloat(@round(480.0 * ui))));
        const chrome_h = pad_y + title_h + subtitle_h + gap + footer_h + gap + ch;
        const max_rows_by_height = @max(1, @divTrunc(fb_h - chrome_h - ch * 2, row_h));
        const max_visible: usize = @min(10, @as(usize, @intCast(max_rows_by_height)));
        const list_rows = @max(@as(usize, 1), @min(@max(name_n, 1), max_visible));
        const list_h = @as(i32, @intCast(list_rows)) * row_h;
        const h = pad_y + title_h + subtitle_h + gap + list_h + gap + footer_h;
        const x = @divTrunc(fb_w - w, 2);
        const y = @max(ch * 2, @divTrunc(fb_h - h, 2));

        const panel = chrome.panel;
        const fg = chrome.fg;
        const muted = chrome.muted;
        const dim = chrome.dim;
        const accent = chrome.accent;
        const sel_bg = chrome.sel_bg;
        const rule = chrome.rule;

        try self.renderer.drawRect(x, y, w, h, panel, 0.98);
        try self.renderer.drawRect(x, y, w, accent_h, accent, 0.55);

        var cy = y + pad_y;
        try self.renderer.drawTextScaled(x + pad_x, cy, "Load Saved Workspace", fg, title_s);
        cy += title_h;

        var count_buf: [48]u8 = undefined;
        const subtitle = if (name_n == 0)
            "No saved layouts yet"
        else
            (std.fmt.bufPrint(&count_buf, "{d} saved", .{name_n}) catch "saved");
        try self.renderer.drawTextScaled(x + pad_x, cy, subtitle, muted, ui);
        cy += subtitle_h + gap;

        try self.renderer.drawRect(x + pad_x - 4, cy - @divTrunc(gap, 2), w - pad_x * 2 + 8, 1, rule, 0.9);

        if (name_n == 0) {
            const empty_y = cy + @divTrunc(list_h - ch * 2, 2);
            try self.renderer.drawTextScaled(x + pad_x + 4, empty_y, "Save a layout with Ctrl+Shift+S", fg, ui);
            try self.renderer.drawTextScaled(x + pad_x + 4, empty_y + ch + 4, "Then open it again from here", dim, ui);
        } else {
            if (self.picker_index >= name_n) self.picker_index = name_n - 1;
            var start: usize = 0;
            if (self.picker_index >= max_visible) {
                start = self.picker_index + 1 - max_visible;
            }
            const visible = @min(name_n - start, max_visible);
            const label_max = @max(8, @divTrunc(w - pad_x * 2 - cw * 2, cw));

            var i: usize = 0;
            while (i < visible) : (i += 1) {
                const mi = start + i;
                const name = self.workspaces.names.items[mi];
                const ry = cy + @as(i32, @intCast(i)) * row_h;
                const text_y = ry + @divTrunc(row_h - ch, 2);
                const selected = mi == self.picker_index;

                if (selected) {
                    try self.renderer.drawRect(x + 10, ry, w - 20, row_h - 2, sel_bg, 1.0);
                    try self.renderer.drawRect(x + 10, ry, @max(3, @divTrunc(cw, 4)), row_h - 2, accent, 1.0);
                }

                const shown = name[0..@min(name.len, @as(usize, @intCast(label_max)))];
                try self.renderer.drawTextScaled(x + pad_x + 8, text_y, shown, if (selected) fg else muted, ui);
            }
        }

        const foot = if (name_n == 0)
            "Ctrl+Shift+S save    Esc close"
        else
            "Enter open    Del delete    Esc close";
        try self.renderer.drawTextScaled(x + pad_x, y + h - footer_h + @divTrunc(pad_y, 2), foot, dim, ui);
    }

    fn drawSavePrompt(self: *App) !void {
        const chrome = self.overlayChrome();
        const fb_w = self.window.fb_width;
        const fb_h = self.window.fb_height;
        try self.renderer.drawRect(0, 0, fb_w, fb_h, chrome.bg, 0.55);
        const w: i32 = 400;
        const h: i32 = 90;
        const x = @divTrunc(fb_w - w, 2);
        const y = @divTrunc(fb_h - h, 2);
        try self.renderer.drawRect(x, y, w, h, chrome.panel, 0.98);
        try self.renderer.drawRect(x, y, w, 2, chrome.accent, 0.55);
        try self.renderer.drawText(x + 16, y + 14, "Save Workspace", chrome.fg);
        var buf: [80]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "Name: {s}", .{self.save_name[0..self.save_name_len]}) catch "Name:";
        try self.renderer.drawText(x + 16, y + 42, label, chrome.muted);
        try self.renderer.drawText(x + 16, y + 66, "Enter save  |  Esc cancel", chrome.dim);
    }

    fn focused(self: *App) ?*Session {
        return self.tabs.focusedSession();
    }

    fn sessionCwd(self: *App) []const u8 {
        if (self.focused()) |s| return s.cwd;
        return @import("../platform/paths.zig").defaultCwd();
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
            .viewer => {
                if (self.viewer.suppress_next_char) {
                    self.viewer.suppress_next_char = false;
                    return;
                }
                if (self.viewer.find_open) {
                    self.viewer.findInputChar(codepoint);
                    self.viewer.ensureCursorVisible(self.viewerVisibleLines());
                    return;
                }
                self.viewer.insertChar(self.allocator, codepoint);
                self.viewer.ensureCursorVisible(self.viewerVisibleLines());
                return;
            },
            .palette => {
                self.palette.inputChar(codepoint);
                return;
            },
            .ssh_prompt => {
                if (codepoint < 32 or codepoint > 126) return;
                if (self.ssh_host_len + 1 >= self.ssh_host.len) return;
                const ch: u8 = @intCast(codepoint);
                // Only hostname / user@host / :port characters (no shell metacharacters).
                const ok = (ch >= 'a' and ch <= 'z') or
                    (ch >= 'A' and ch <= 'Z') or
                    (ch >= '0' and ch <= '9') or
                    ch == '.' or ch == '-' or ch == '_' or ch == '@' or ch == ':';
                if (!ok) return;
                self.ssh_host[self.ssh_host_len] = ch;
                self.ssh_host_len += 1;
                return;
            },
            .ws_save => {
                if (codepoint < 32 or codepoint > 126) return;
                if (self.save_name_len + 1 >= self.save_name.len) return;
                const ch: u8 = @intCast(codepoint);
                // Keep workspace names as a single path segment (no traversal / shell meta).
                if (ch == '/' or ch == '\\' or ch == '"' or ch == ' ' or ch == ';') return;
                self.save_name[self.save_name_len] = ch;
                self.save_name_len += 1;
                return;
            },
            .ws_picker, .settings, .plugins, .plugin_result => return,
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

        // Quit / close tab work from every screen (including home).
        if (self.fireQuitOrClose(key, bmods)) return;

        if (self.ui == .home) {
            if (ctrl or super or alt) {
                if (self.tryFireKeymap(key, bmods, action)) return;
            }
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
        if (self.ui == .plugin_result) {
            self.handlePluginResultKey(key);
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
            self.handleSearchKey(key, shift);
            return;
        }
        if (self.ui == .viewer) {
            self.handleViewerKey(key, ctrl, shift, super);
            return;
        }

        // Context menu: Esc closes without sending to the shell.
        if (self.context_menu != null and key == c.GLFW_KEY_ESCAPE) {
            self.closeContextMenu();
            return;
        }

        if (self.tryFireKeymap(key, bmods, action)) return;

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

        // Plugin shortcuts (after config keybinds so users can reserve chords)
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
            else => {},
        }
    }

    fn fireQuitOrClose(self: *App, key: c_int, bmods: bindings.Mods) bool {
        const name = glfwKeyName(key) orelse return false;
        const trigger = keybind_mod.Trigger.from(bmods, name);
        return switch (self.config.keymap.advance(&.{}, trigger)) {
            .fire => |binding| {
                if (!binding.isQuitOrClose()) return false;
                if (binding.prefixes.performable and !self.canPerform(binding)) return false;
                self.seq_len = 0;
                self.runBinding(binding);
                return true;
            },
            else => false,
        };
    }

    fn tryFireKeymap(self: *App, key: c_int, bmods: bindings.Mods, glfw_action: c_int) bool {
        const name = glfwKeyName(key) orelse return false;
        const trigger = keybind_mod.Trigger.from(bmods, name);

        if (glfw_action == c.GLFW_REPEAT and self.seq_len > 0) return true;

        switch (self.config.keymap.advance(self.seq[0..self.seq_len], trigger)) {
            .wait => {
                if (self.seq_len < keybind_mod.max_sequence) {
                    self.seq[self.seq_len] = trigger;
                    self.seq_len += 1;
                }
                return true;
            },
            .miss => {
                self.seq_len = 0;
                return false;
            },
            .fire => |binding| {
                self.seq_len = 0;
                if (binding.prefixes.performable and !self.canPerform(binding)) return false;
                self.closeContextMenu();
                self.runBinding(binding);
                if (binding.prefixes.unconsumed) {
                    if (self.focused()) |s| {
                        var buf: [8]u8 = undefined;
                        const bytes = keybind_mod.encodeTrigger(trigger, &buf);
                        if (bytes.len > 0) s.write(bytes);
                    }
                }
                return true;
            },
        }
    }

    fn canPerform(self: *App, binding: *const keybind_mod.Binding) bool {
        for (binding.actionsSlice()) |act| {
            switch (act) {
                .app => |a| switch (a) {
                    .copy_selection => {
                        const s = self.focused() orelse return false;
                        if (!s.selection.active) return false;
                    },
                    else => {},
                },
                else => {},
            }
        }
        return true;
    }

    fn runBinding(self: *App, binding: *const keybind_mod.Binding) void {
        var reload = false;
        for (binding.actionsSlice()) |act| {
            switch (act) {
                .ignore, .unbind => {},
                .app => |a| {
                    if (a == .reload_config) {
                        reload = true;
                    } else {
                        self.runAction(a);
                    }
                },
                .text => |t| {
                    if (self.focused()) |s| s.write(t);
                },
                .csi => |t| {
                    if (self.focused()) |s| {
                        s.write("\x1b[");
                        s.write(t);
                    }
                },
                .esc => |t| {
                    if (self.focused()) |s| {
                        s.write("\x1b");
                        s.write(t);
                    }
                },
            }
        }
        if (reload) self.runAction(.reload_config);
    }

    fn goHome(self: *App) void {
        self.seq_len = 0;
        self.home = .{};
        self.ui = .home;
        self.closeContextMenu();
        self.plugin_result.close();
        self.search.close(self.allocator);
        self.viewer.close(self.allocator);
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
        if (ctrl or super or shift) {
            switch (key) {
                c.GLFW_KEY_UP => self.home.moveUp(),
                c.GLFW_KEY_DOWN => self.home.moveDown(),
                else => {},
            }
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
        if (self.ui == .plugin_result) {
            const back_viewer = self.plugin_result.return_to_viewer and self.viewer.active;
            self.plugin_result.close();
            self.ui = if (back_viewer) .viewer else if (self.tabs.items.items.len == 0) .home else .normal;
            return;
        }
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
            .toggle_palette => {
                if (self.ui == .palette) {
                    self.palette.close();
                    self.leaveOverlay();
                } else {
                    self.rebuildPalette();
                    self.palette.open();
                    self.ui = .palette;
                    self.clearStatus();
                }
            },
            .copy_selection => self.copySelection(),
            .paste_clipboard => self.pasteClipboard(),
            .scroll_page_up => {
                if (self.focused()) |s| s.screen.scrollView(10);
            },
            .scroll_page_down => {
                if (self.focused()) |s| s.screen.scrollView(-10);
            },
            .scroll_to_top => {
                if (self.focused()) |s| s.screen.scrollView(32767);
            },
            .scroll_to_bottom => {
                if (self.focused()) |s| s.screen.scrollView(-32767);
            },
            .open_file => {
                self.openSearch();
                if (self.ui == .search) {
                    self.search.mode = .files;
                    self.refreshSearchResults();
                }
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
            .theme_catppuccin => self.applyTheme("catppuccin-mocha"),
            .theme_tokyo_night => self.applyTheme("tokyo-night"),
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
                self.seq_len = 0;
                self.renderer.setContentScale(self.window.contentScale());
                self.renderer.setFontSize(self.config.font_size);
                self.renderer.setFontFace(self.config.font_face);
                self.renderer.cursor_style = self.config.cursor_style;
                self.renderer.cursor_blink = self.config.cursor_blink;
                self.applyLookVisuals();
                self.applyTheme(self.config.theme_name);
                self.setStatus("config reloaded");
            },
            .reload_plugins => {
                self.fireHooks(.on_unload);
                self.plugins.reload() catch {
                    self.setStatus("plugin reload failed");
                    return;
                };
                self.fireHooks(.on_load);
                self.applyRendererHooks();
                self.rebuildPalette();
                var buf: [64]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "plugins: {d} loaded", .{self.plugins.count()}) catch "plugins reloaded";
                self.setStatus(msg);
            },
            .list_plugins => {
                self.plugin_row = 0;
                self.ui = .plugins;
            },
            .format_document => self.runKindPlugin(.format, "format"),
            .lint_file => self.runKindPlugin(.lint, "lint"),
            .ai_explain => self.runKindPlugin(.ai, "explain"),
            .ai_suggest => self.runKindPlugin(.ai, "suggest"),
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
            c.GLFW_KEY_U, c.GLFW_KEY_DELETE, c.GLFW_KEY_BACKSPACE => self.uninstallSelectedPlugin(),
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
        self.plugins.persistEnabled();
        self.rebuildPalette();
        self.applyRendererHooks();
        var buf: [64]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{s} {s}", .{ p.name, if (p.enabled) "enabled" else "disabled" }) catch "plugin toggled";
        self.setStatus(msg);
    }

    fn reloadPluginsFromPanel(self: *App) void {
        self.fireHooks(.on_unload);
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
        installed += plugin_bundled.install(self.allocator, self.io, self.plugins.dir_path);
        self.reloadPluginsFromPanel();
        var buf: [64]u8 = undefined;
        const n = self.plugins.count();
        const msg = std.fmt.bufPrint(&buf, "installed {d} plugins", .{if (n > 0) n else installed}) catch "plugins installed";
        self.setStatus(msg);
    }

    fn writePluginToml(self: *App, name: []const u8, toml: []const u8) bool {
        const plugin_dir = std.fmt.allocPrint(self.allocator, "{s}{c}{s}", .{ self.plugins.dir_path, std.fs.path.sep, name }) catch return false;
        defer self.allocator.free(plugin_dir);

        @import("../platform/paths.zig").ensureDir(plugin_dir);

        const toml_path = std.fmt.allocPrint(self.allocator, "{s}{c}plugin.toml", .{ plugin_dir, std.fs.path.sep }) catch return false;
        defer self.allocator.free(toml_path);

        const file = std.Io.Dir.createFileAbsolute(self.io, toml_path, .{}) catch return false;
        defer file.close(self.io);
        file.writeStreamingAll(self.io, toml) catch return false;
        return true;
    }

    /// Remove the selected plugin folder from `~/.config/orbit/plugins/<name>/`.
    fn uninstallSelectedPlugin(self: *App) void {
        if (self.plugin_row >= self.plugins.plugins.items.len) {
            self.setStatus("no plugin selected");
            return;
        }
        const name = self.plugins.plugins.items[self.plugin_row].name;
        if (!isSafePluginFolderName(name)) {
            self.setStatus("invalid plugin name");
            return;
        }

        var name_buf: [64]u8 = undefined;
        const n = @min(name.len, name_buf.len);
        @memcpy(name_buf[0..n], name[0..n]);
        const saved = name_buf[0..n];

        const parent = std.Io.Dir.openDirAbsolute(self.io, self.plugins.dir_path, .{}) catch {
            self.setStatus("uninstall failed");
            return;
        };
        defer parent.close(self.io);
        parent.deleteTree(self.io, saved) catch {
            self.setStatus("uninstall failed");
            return;
        };

        self.reloadPluginsFromPanel();
        var buf: [80]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "uninstalled {s}", .{saved}) catch "plugin uninstalled";
        self.setStatus(msg);
    }

    fn isSafePluginFolderName(name: []const u8) bool {
        if (name.len == 0 or name.len > 64) return false;
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) return false;
        for (name) |ch| {
            switch (ch) {
                'a'...'z', 'A'...'Z', '0'...'9', '-', '_' => {},
                else => return false,
            }
        }
        return true;
    }

    fn handleSettingsKey(self: *App, key: c_int) void {
        switch (key) {
            c.GLFW_KEY_ESCAPE => self.leaveOverlay(),
            c.GLFW_KEY_UP => {
                if (self.settings_row > 0) self.settings_row -= 1;
            },
            c.GLFW_KEY_DOWN => {
                if (self.settings_row + 1 < SettingsRow.count) self.settings_row += 1;
            },
            c.GLFW_KEY_LEFT => self.nudgeSettings(-1),
            c.GLFW_KEY_RIGHT, c.GLFW_KEY_ENTER => self.nudgeSettings(1),
            c.GLFW_KEY_S => self.persistAppearance(),
            else => {},
        }
    }

    fn nudgeSettings(self: *App, delta: i32) void {
        switch (SettingsRow.fromIndex(self.settings_row)) {
            .theme => {
                const next = theme_mod.nextName(self.config.theme_name, delta);
                self.applyTheme(next);
            },
            .text => {
                self.config.cycleFgPreset(self.allocator, delta) catch {
                    self.setStatus("text color failed");
                    return;
                };
                self.refreshThemeColors();
                var buf: [64]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "text {s}", .{self.config.fgDisplay()}) catch "text color";
                self.setStatus(msg);
            },
            .font => {
                self.adjustFont(if (delta >= 0) 1.0 else -1.0);
            },
            .face => {
                self.config.cycleFontFace(self.allocator, delta) catch {
                    self.setStatus("font face failed");
                    return;
                };
                self.renderer.setFontFace(self.config.font_face);
                self.resizeAllSessions();
                var buf: [80]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "face {s}", .{self.config.fontFaceDisplay()}) catch "font face";
                self.setStatus(msg);
            },
            .look => {
                self.config.cycleLook(delta);
                self.applyLookVisuals();
                var buf: [80]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "look {s}", .{self.config.look.name()}) catch "look updated";
                self.setStatus(msg);
            },
            .opacity => {
                self.config.cycleOpacity(delta);
                self.applyLookVisuals();
                var buf: [48]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "opacity {d:.0}%", .{self.config.opacity * 100.0}) catch "opacity";
                self.setStatus(msg);
            },
            .padding => {
                self.config.cyclePadding(delta);
                self.resizeAllSessions();
                var buf: [48]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "padding {d}x{d}", .{
                    self.config.padding_x,
                    self.config.padding_y,
                }) catch "padding";
                self.setStatus(msg);
            },
            .spacing => {
                self.config.cycleLineHeight(delta);
                self.applyLookVisuals();
                var buf: [64]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "spacing {s}", .{self.config.lineHeightDisplay()}) catch "spacing";
                self.setStatus(msg);
            },
            .cursor => {
                self.config.cursor_style = if (delta >= 0)
                    self.config.cursor_style.next()
                else
                    self.config.cursor_style.prev();
                self.renderer.cursor_style = self.config.cursor_style;
                self.setStatus("cursor style");
            },
            .blink => self.toggleCursorBlink(),
            .prompt => {
                self.config.cyclePrompt(delta);
                var buf: [80]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "prompt {s} (new tabs)", .{self.config.prompt.name()}) catch "prompt updated";
                self.setStatus(msg);
            },
            .shell => {
                self.config.cycleShell(self.allocator, delta) catch {
                    self.setStatus("shell change failed");
                    return;
                };
                var buf: [80]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "shell {s} (new tabs)", .{self.config.shellDisplay()}) catch "shell updated";
                self.setStatus(msg);
            },
        }
    }

    fn applyLookVisuals(self: *App) void {
        self.renderer.opacity = self.config.opacity;
        self.renderer.setLineHeight(self.config.line_height);
        self.window.setOpacity(self.config.opacity);
        self.resizeAllSessions();
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
        self.config.setFontFace(self.allocator, self.renderer.font_face) catch {};
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
        if (self.plugins.findCommandRef(plugin_name, command_id)) |ref| {
            self.executePluginCommand(ref.plugin, ref.command);
            return;
        }
        if (self.plugins.findTheme(command_id) != null) {
            self.applyTheme(command_id);
            return;
        }
        self.setStatus("plugin command missing");
    }

    fn executePluginCommand(self: *App, plugin: *const plugin_types.Plugin, cmd: *const PluginCommand) void {
        switch (cmd.kind) {
            .insert => {
                if (plugin_audit.auditInsertPayload(cmd.payload)) |hit| {
                    var buf: [192]u8 = undefined;
                    if (plugin_audit.shouldBlock(hit)) {
                        const msg = std.fmt.bufPrint(&buf, "security blocked [{s}]: {s}", .{
                            hit.severity.label(),
                            hit.message,
                        }) catch "security blocked: risky plugin insert";
                        self.setStatus(msg);
                        std.log.warn("security: blocked insert `{s}`: {s}", .{ cmd.id, hit.message });
                        return;
                    }
                    const msg = std.fmt.bufPrint(&buf, "security warning [{s}]: {s}", .{
                        hit.severity.label(),
                        hit.message,
                    }) catch "security warning: risky plugin insert";
                    self.setStatus(msg);
                    std.log.warn("security: executing warned insert `{s}`: {s}", .{ cmd.id, hit.message });
                } else {
                    self.setStatus("plugin insert");
                }
                if (self.focused()) |s| s.write(cmd.payload);
            },
            .status => self.setStatus(cmd.payload),
            .theme => self.applyTheme(cmd.payload),
            .host => self.runHostPayload(cmd.payload),
            .run => self.runPluginTool(plugin, cmd.payload),
        }
    }

    /// Run a plugin keybinding if one matches. Prefer chords with modifiers.
    fn tryPluginBinding(self: *App, key: c_int, ctrl: bool, shift: bool, super: bool, alt: bool) bool {
        // Plain typing must reach the shell — only chords with a modifier (or F-keys).
        const is_fn = key >= c.GLFW_KEY_F1 and key <= c.GLFW_KEY_F12;
        if (!ctrl and !shift and !super and !alt and !is_fn) return false;

        const name = glfwKeyName(key) orelse return false;
        const command_id = self.plugins.matchBinding(name, ctrl, shift, super, alt) orelse return false;
        if (self.plugins.findCommandByIdRef(command_id)) |ref| {
            self.executePluginCommand(ref.plugin, ref.command);
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
        } else if (std.mem.eql(u8, payload, "split_down")) {
            self.runAction(.split_down);
        } else if (std.mem.eql(u8, payload, "search")) {
            self.runAction(.search);
        } else {
            self.setStatus(payload);
        }
    }

    fn runKindPlugin(self: *App, kind: PluginKind, action: []const u8) void {
        const plugin = self.plugins.findByKind(kind) orelse {
            const msg: []const u8 = switch (kind) {
                .format => "no format plugin — Plugins → I to install",
                .lint => "no lint plugin — Plugins → I to install",
                .ai => "no AI plugin — Plugins → I to install",
                else => "plugin not installed",
            };
            self.setStatus(msg);
            return;
        };
        self.runPluginTool(plugin, action);
    }

    fn runPluginTool(self: *App, plugin: *const plugin_types.Plugin, action: []const u8) void {
        if (!plugin.tool.hasRunner()) {
            self.setStatus("plugin has no [tool]");
            return;
        }

        var sel_buf: [32 * 1024]u8 = undefined;
        const selection = self.capturePluginSelection(&sel_buf);

        const file_path: []const u8 = if (self.viewer.abs_path) |p| p else "";
        const language: []const u8 = if (self.viewer.active) @tagName(self.viewer.language) else "";
        const buffer: []const u8 = if (self.viewer.content) |b| b else "";
        const cwd = self.sessionCwd();
        const prompt_t = plugin.tool.prompt orelse "";

        const ctx = plugin_runner.Context{
            .plugin = plugin.name,
            .action = action,
            .file = file_path,
            .language = language,
            .cwd = cwd,
            .selection = selection,
            .buffer = buffer,
            .plugin_dir = plugin.dir,
            .prompt = prompt_t,
        };

        if (plugin.kind == .format or plugin.kind == .lint) {
            if (!self.viewer.active or !self.viewer.canEdit()) {
                if (plugin.kind == .format or plugin.kind == .lint) {
                    self.setStatus("open a file first (Search → Files / Code)");
                    return;
                }
            }
        }
        if (plugin.kind == .format and !plugin.tool.matchesLanguage(language)) {
            self.setStatus("format plugin does not handle this language");
            return;
        }

        self.setStatus("running plugin…");
        var result = plugin_runner.run(self.allocator, self.io, plugin, ctx) catch |err| {
            const msg: []const u8 = switch (err) {
                error.Timeout => "plugin timed out",
                error.CommandNotFound => "plugin command not found — edit its script",
                error.NoTool => "plugin has no [tool]",
                error.UnsafeScriptPath => "plugin script path refused",
                else => "plugin failed to run",
            };
            self.setStatus(msg);
            return;
        };
        defer result.deinit();

        self.applyToolResult(plugin, &result);
    }

    fn applyToolResult(self: *App, plugin: *const plugin_types.Plugin, result: *plugin_runner.Result) void {
        const out = std.mem.trim(u8, result.stdout, " \t\r\n");
        const err_txt = std.mem.trim(u8, result.stderr, " \t\r\n");

        switch (plugin.tool.stdout) {
            .replace => {
                if (out.len > 0 and self.viewer.canEdit()) {
                    self.viewer.replaceContent(self.allocator, result.stdout) catch {
                        self.setStatus("formatted output too large");
                        return;
                    };
                    self.setStatus("formatted");
                    self.ui = .viewer;
                    return;
                }
                if (self.viewer.active) {
                    self.viewer.reloadFromDisk(self.allocator, self.io);
                    self.setStatus("formatted");
                    self.ui = .viewer;
                    return;
                }
                self.setStatus(if (result.code == 0) "format ran" else "format failed");
            },
            .insert => {
                if (out.len == 0) {
                    self.setStatus(if (err_txt.len > 0) err_txt else "plugin produced no output");
                    return;
                }
                if (self.focused()) |s| s.write(out);
                self.setStatus("plugin inserted");
            },
            .status => {
                const msg = if (out.len > 0) out else if (err_txt.len > 0) err_txt else "plugin done";
                self.setStatus(msg);
            },
            .discard => {
                self.setStatus(if (result.code == 0) "plugin done" else "plugin exited with error");
            },
            .overlay => {
                var title_buf: [72]u8 = undefined;
                const title = std.fmt.bufPrint(&title_buf, "{s} · {s}", .{ plugin.kind.badge(), plugin.name }) catch plugin.name;
                const body = if (out.len > 0) result.stdout else if (err_txt.len > 0) result.stderr else "No output.";
                const insertable = plugin.kind == .ai or plugin.tool.stdout == .overlay and plugin.kind != .lint;
                self.plugin_result.open(title, body, insertable and plugin.kind == .ai);
                self.plugin_result.return_to_viewer = self.viewer.active;
                if (plugin.tool.parse == .unix) self.plugin_result.applyUnixDiagnostics();
                self.ui = .plugin_result;
            },
        }
    }

    fn capturePluginSelection(self: *App, buf: []u8) []const u8 {
        if (self.focused()) |session| {
            if (session.selection.active) {
                const n = session.selection.copyText(&session.screen, buf);
                if (n > 0) return buf[0..n];
            }
            const n = App.copyVisibleScreen(&session.screen, buf);
            if (n > 0) return buf[0..n];
        }
        if (self.viewer.content) |body| {
            const n = @min(body.len, buf.len);
            @memcpy(buf[0..n], body[0..n]);
            return buf[0..n];
        }
        return "";
    }

    fn copyVisibleScreen(screen: *const @import("../terminal/screen.zig").Screen, buf: []u8) usize {
        var out: usize = 0;
        var row: u16 = 0;
        while (row < screen.rows) : (row += 1) {
            var col: u16 = 0;
            var line_end = out;
            while (col < screen.cols) : (col += 1) {
                if (out >= buf.len) return out;
                const cp = screen.visibleCell(col, row).codepoint;
                const ch: u8 = if (cp >= 32 and cp < 127) @intCast(cp) else ' ';
                buf[out] = ch;
                out += 1;
                if (ch != ' ') line_end = out;
            }
            out = line_end;
            if (out < buf.len) {
                buf[out] = '\n';
                out += 1;
            }
        }
        return out;
    }

    fn handlePluginResultKey(self: *App, key: c_int) void {
        const visible = self.pluginResultVisibleLines();
        switch (key) {
            c.GLFW_KEY_ESCAPE => self.leaveOverlay(),
            c.GLFW_KEY_UP => self.plugin_result.scrollBy(-1, visible),
            c.GLFW_KEY_DOWN => self.plugin_result.scrollBy(1, visible),
            c.GLFW_KEY_PAGE_UP => self.plugin_result.scrollBy(-@as(i32, @intCast(@max(visible, 1))), visible),
            c.GLFW_KEY_PAGE_DOWN => self.plugin_result.scrollBy(@as(i32, @intCast(@max(visible, 1))), visible),
            c.GLFW_KEY_ENTER, c.GLFW_KEY_KP_ENTER => {
                if (self.plugin_result.jump_line) |line| {
                    if (self.viewer.active) {
                        const col = if (self.plugin_result.jump_col) |c0| c0 -| 1 else 0;
                        self.viewer.goTo(line -| 1, col);
                        self.plugin_result.close();
                        self.ui = .viewer;
                        return;
                    }
                }
                if (self.plugin_result.insertable and self.plugin_result.body.len > 0) {
                    if (self.focused()) |s| s.write(self.plugin_result.body);
                    self.setStatus("inserted plugin output");
                    self.leaveOverlay();
                }
            },
            else => {},
        }
    }

    fn pluginResultVisibleLines(self: *const App) usize {
        const ch = @as(i32, @intFromFloat(@max(1.0, self.renderer.cell_h)));
        const h = @max(ch * 8, self.window.fb_height - ch * 10);
        return @max(1, @as(usize, @intCast(@divTrunc(h, ch + 4))));
    }

    fn drawPluginResult(self: *App) !void {
        const fb_w = self.window.fb_width;
        const fb_h = self.window.fb_height;
        const ui = ui_scale.uiScale(fb_w, fb_h, self.renderer.content_scale);
        const title_s = ui * 1.12;
        const base_cw = @as(i32, @intFromFloat(self.renderer.cell_w));
        const base_ch = @as(i32, @intFromFloat(self.renderer.cell_h));
        const cw = ui_scale.scaled(base_cw, ui);
        const ch = ui_scale.scaled(base_ch, ui);
        const title_ch = ui_scale.scaled(base_ch, title_s);
        const chrome = self.overlayChrome();

        try self.renderer.drawRect(0, 0, fb_w, fb_h, chrome.bg, 0.55);

        const pad_x = @max(cw + 10, @as(i32, @intFromFloat(@round(26.0 * ui))));
        const pad_y = @max(@divTrunc(ch, 2) + 8, @as(i32, @intFromFloat(@round(22.0 * ui))));
        const w = ui_scale.panelWidth(fb_w, cw, 64, @as(i32, @intFromFloat(@round(720.0 * ui))));
        const h = @min(fb_h - ch * 2, @max(ch * 16, @divTrunc(fb_h * 3, 4)));
        const x = @divTrunc(fb_w - w, 2);
        const y = @max(ch, @divTrunc(fb_h - h, 2));

        try self.renderer.drawRect(x, y, w, h, chrome.panel, 0.98);
        try self.renderer.drawRect(x, y, w, @max(2, @divTrunc(ch, 10)), chrome.accent, 0.55);

        var cy = y + pad_y;
        try self.renderer.drawTextScaled(x + pad_x, cy, self.plugin_result.titleSlice(), chrome.fg, title_s);
        cy += title_ch + @divTrunc(ch, 2);

        const footer_h = ch + pad_y;
        const list_h = h - (cy - y) - footer_h;
        const row_h = ch + @max(4, @divTrunc(ch, 6));
        const visible: usize = @max(1, @as(usize, @intCast(@divTrunc(list_h, row_h))));
        const total = self.plugin_result.lineCount();
        const start = self.plugin_result.scroll;
        const shown = @min(visible, if (total > start) total - start else 0);
        const max_chars = @max(8, @divTrunc(w - pad_x * 2, cw));

        var i: usize = 0;
        while (i < shown) : (i += 1) {
            const text = self.plugin_result.line(start + i);
            const clip = text[0..@min(text.len, @as(usize, @intCast(max_chars)))];
            try self.renderer.drawTextScaled(x + pad_x, cy + @as(i32, @intCast(i)) * row_h, clip, chrome.muted, ui);
        }

        cy = y + h - footer_h;
        try self.renderer.drawRect(x + pad_x - 4, cy - 8, w - pad_x * 2 + 8, 1, chrome.rule, 0.9);
        const hint: []const u8 = if (self.plugin_result.insertable)
            "Enter insert into shell    Esc close"
        else if (self.plugin_result.jump_line != null)
            "Enter jump to line    Esc close"
        else
            "Esc close";
        try self.renderer.drawTextScaled(x + pad_x, cy, hint, chrome.dim, ui);
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
            const text = payload["insert:".len..];
            if (plugin_audit.auditInsertPayload(text)) |hit| {
                if (plugin_audit.shouldBlock(hit)) {
                    var buf: [192]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, "security blocked hook [{s}]: {s}", .{
                        hit.severity.label(),
                        hit.message,
                    }) catch "security blocked: risky plugin hook";
                    self.setStatus(msg);
                    std.log.warn("security: blocked hook insert: {s}", .{hit.message});
                    return;
                }
            }
            if (self.focused()) |s| s.write(text);
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
        if (!isSafeSshTarget(host)) {
            self.setStatus("invalid ssh host");
            return;
        }
        // Open a tab titled with the host; inject the command only after the prompt appears
        // so we don't get a ghost echoed line + weird highlight before the shell is ready.
        var title_buf: [64]u8 = undefined;
        const title = std.fmt.bufPrint(&title_buf, "ssh {s}", .{host}) catch "ssh";
        try self.newTabInDir(self.sessionCwd(), title[0..@min(title.len, 32)]);
        if (self.focused()) |s| s.selection.clear();
        const n = @min(host.len, self.pending_ssh_host.len);
        @memcpy(self.pending_ssh_host[0..n], host[0..n]);
        self.pending_ssh_len = n;
        self.setStatus("ssh starting…");
    }

    fn flushPendingSsh(self: *App) void {
        if (self.pending_ssh_len == 0) return;
        const session = self.focused() orelse {
            self.pending_ssh_len = 0;
            return;
        };
        if (!session.alive or !session.output_seen) return;

        var cmd: [192]u8 = undefined;
        const line = std.fmt.bufPrint(
            &cmd,
            "ssh -- {s}\r",
            .{self.pending_ssh_host[0..self.pending_ssh_len]},
        ) catch {
            self.pending_ssh_len = 0;
            self.setStatus("ssh failed");
            return;
        };
        session.write(line);
        self.pending_ssh_len = 0;
        self.setStatus("ssh started");
    }

    /// Allow `user@host`, hostnames, IPv4, and optional `:port` — reject shell metacharacters.
    fn isSafeSshTarget(host: []const u8) bool {
        if (host.len == 0 or host.len > 180) return false;
        var saw_at = false;
        var saw_colon = false;
        for (host) |ch| {
            switch (ch) {
                'a'...'z', 'A'...'Z', '0'...'9', '.', '-', '_' => {},
                '@' => {
                    if (saw_at) return false;
                    saw_at = true;
                },
                ':' => {
                    if (saw_colon) return false;
                    saw_colon = true;
                },
                else => return false,
            }
        }
        return true;
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
                if (!WsManager.isValidName(name)) {
                    self.setStatus("invalid workspace name");
                    return;
                }
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
        try self.openSession(self.sessionCwd(), null, &.{}, false);
    }

    fn newTabInDir(self: *App, cwd: []const u8, title_opt: ?[]const u8) !void {
        try self.openSession(cwd, title_opt, &.{}, false);
    }

    fn applyLaunch(self: *App, opts: LaunchOpts) void {
        if (!opts.skip_home) return;
        const raw = opts.cwd orelse @import("../platform/paths.zig").defaultCwd();
        var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
        var file_buf: [std.fs.max_path_bytes]u8 = undefined;
        const resolved = self.resolveOpenPath(raw, &dir_buf, &file_buf);
        self.openSession(resolved.dir, opts.title, opts.execute, opts.wait_after_command) catch {
            self.setStatus("could not open folder");
            return;
        };
        if (resolved.file) |f| self.openViewerPath(f, std.fs.path.basename(f));
    }

    fn drainExternalOpens(self: *App) void {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        while (macos_open.take(&buf)) |p| {
            var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
            var file_buf: [std.fs.max_path_bytes]u8 = undefined;
            const resolved = self.resolveOpenPath(p, &dir_buf, &file_buf);
            self.openSession(resolved.dir, null, &.{}, false) catch {
                self.setStatus("could not open folder");
                continue;
            };
            if (resolved.file) |f| self.openViewerPath(f, std.fs.path.basename(f));
        }
    }

    fn pathIsDir(self: *App, path: []const u8) bool {
        const dir = std.Io.Dir.openDirAbsolute(self.io, path, .{}) catch return false;
        dir.close(self.io);
        return true;
    }

    fn pathIsFile(self: *App, path: []const u8) bool {
        const file = std.Io.Dir.openFileAbsolute(self.io, path, .{}) catch return false;
        file.close(self.io);
        return true;
    }

    fn absolutizePath(self: *App, path: []const u8, buf: *[std.fs.max_path_bytes]u8) ?[]u8 {
        if (std.fs.path.isAbsolute(path)) {
            if (path.len >= buf.len) return null;
            @memcpy(buf[0..path.len], path);
            return buf[0..path.len];
        }
        var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
        const n = std.Io.Dir.cwd().realPath(self.io, &cwd_buf) catch return null;
        return std.fmt.bufPrint(buf, "{s}{c}{s}", .{ cwd_buf[0..n], std.fs.path.sep, path }) catch null;
    }

    fn resolveOpenPath(
        self: *App,
        path: []const u8,
        dir_buf: *[std.fs.max_path_bytes]u8,
        file_buf: *[std.fs.max_path_bytes]u8,
    ) struct { dir: []const u8, file: ?[]const u8 } {
        const abs = self.absolutizePath(path, file_buf) orelse return .{ .dir = path, .file = null };
        if (self.pathIsDir(abs)) return .{ .dir = abs, .file = null };
        if (!self.pathIsFile(abs)) return .{ .dir = abs, .file = null };
        const parent = std.fs.path.dirname(abs) orelse ".";
        const n = @min(parent.len, dir_buf.len);
        @memcpy(dir_buf[0..n], parent[0..n]);
        return .{ .dir = dir_buf[0..n], .file = abs };
    }

    fn openViewerPath(self: *App, abs_path: []const u8, display: []const u8) void {
        self.viewer.open(self.allocator, self.io, abs_path, display);
        self.ui = .viewer;
        var buf: [96]u8 = undefined;
        const msg = std.fmt.bufPrint(
            &buf,
            "{s} · {s} · type to edit",
            .{ std.fs.path.basename(abs_path), viewer_mod.languageLabel(self.viewer.language) },
        ) catch "opened file";
        self.setStatus(msg);
    }

    fn viewerVisibleLines(self: *const App) usize {
        const ch = @as(i32, @intFromFloat(@max(1.0, self.renderer.cell_h)));
        const row_h = ch + 4;
        const header = ch + 28;
        const find_h: i32 = if (self.viewer.find_open) ch + 16 else 0;
        const footer = ch + 16;
        const body = @max(row_h, self.window.fb_height - Tabs.bar_height - 24 - header - find_h - footer);
        return @intCast(@max(1, @divTrunc(body, row_h)));
    }

    fn handleViewerKey(self: *App, key: c_int, ctrl: bool, shift: bool, super: bool) void {
        const visible = self.viewerVisibleLines();
        const cmd = ctrl or super;

        if (cmd and !shift and key == c.GLFW_KEY_S) {
            if (self.viewer.save(self.io)) {
                self.setStatus("saved");
            } else {
                self.setStatus("could not save");
            }
            return;
        }

        if (cmd and !shift and key == c.GLFW_KEY_F) {
            self.viewer.suppress_next_char = true;
            self.viewer.openFind();
            return;
        }

        if (cmd and shift and key == c.GLFW_KEY_F) {
            self.openSearch();
            if (self.ui == .search) {
                self.search.mode = .code;
                self.refreshSearchResults();
            }
            return;
        }

        if (self.viewer.find_open) {
            switch (key) {
                c.GLFW_KEY_ESCAPE => {
                    self.viewer.closeFind();
                    return;
                },
                c.GLFW_KEY_ENTER, c.GLFW_KEY_KP_ENTER, c.GLFW_KEY_F3 => {
                    if (shift) self.viewer.findPrev() else self.viewer.findNext();
                    self.viewer.ensureCursorVisible(visible);
                    return;
                },
                c.GLFW_KEY_BACKSPACE => {
                    self.viewer.findBackspace();
                    self.viewer.ensureCursorVisible(visible);
                    return;
                },
                c.GLFW_KEY_UP => {
                    self.viewer.findPrev();
                    self.viewer.ensureCursorVisible(visible);
                    return;
                },
                c.GLFW_KEY_DOWN, c.GLFW_KEY_TAB => {
                    self.viewer.findNext();
                    self.viewer.ensureCursorVisible(visible);
                    return;
                },
                else => {},
            }
        }

        if (cmd and !shift and key == c.GLFW_KEY_SPACE) {
            self.viewer.suppress_next_char = true;
            self.viewer.refreshCompletion(true);
            return;
        }

        if (self.viewer.complete_open) {
            switch (key) {
                c.GLFW_KEY_ESCAPE => {
                    self.viewer.complete_open = false;
                    return;
                },
                c.GLFW_KEY_UP => {
                    self.viewer.completeMove(-1);
                    return;
                },
                c.GLFW_KEY_DOWN => {
                    self.viewer.completeMove(1);
                    return;
                },
                c.GLFW_KEY_TAB, c.GLFW_KEY_ENTER, c.GLFW_KEY_KP_ENTER => {
                    self.viewer.suppress_next_char = true;
                    _ = self.viewer.acceptCompletion(self.allocator);
                    self.viewer.ensureCursorVisible(visible);
                    return;
                },
                else => {},
            }
        }

        switch (key) {
            c.GLFW_KEY_ESCAPE => {
                if (self.viewer.dirty and !self.viewer.discard_armed) {
                    self.viewer.discard_armed = true;
                    self.setStatus("unsaved — Esc again to discard, ⌘/Ctrl+S to save");
                    return;
                }
                self.viewer.close(self.allocator);
                self.leaveOverlay();
            },
            c.GLFW_KEY_UP => {
                self.viewer.moveUp();
                self.viewer.ensureCursorVisible(visible);
            },
            c.GLFW_KEY_DOWN => {
                self.viewer.moveDown();
                self.viewer.ensureCursorVisible(visible);
            },
            c.GLFW_KEY_LEFT => {
                self.viewer.moveLeft();
                self.viewer.ensureCursorVisible(visible);
            },
            c.GLFW_KEY_RIGHT => {
                self.viewer.moveRight();
                self.viewer.ensureCursorVisible(visible);
            },
            c.GLFW_KEY_PAGE_UP => self.viewer.page(-@as(i32, @intCast(visible)), visible),
            c.GLFW_KEY_PAGE_DOWN => self.viewer.page(@as(i32, @intCast(visible)), visible),
            c.GLFW_KEY_HOME => {
                if (cmd) self.viewer.moveFileStart() else self.viewer.moveLineStart();
                self.viewer.ensureCursorVisible(visible);
            },
            c.GLFW_KEY_END => {
                if (cmd) self.viewer.moveFileEnd() else self.viewer.moveLineEnd();
                self.viewer.ensureCursorVisible(visible);
            },
            c.GLFW_KEY_BACKSPACE => {
                self.viewer.backspace(self.allocator);
                self.viewer.ensureCursorVisible(visible);
            },
            c.GLFW_KEY_DELETE => {
                self.viewer.deleteForward(self.allocator);
                self.viewer.ensureCursorVisible(visible);
            },
            c.GLFW_KEY_ENTER, c.GLFW_KEY_KP_ENTER => {
                self.viewer.newline(self.allocator);
                self.viewer.ensureCursorVisible(visible);
            },
            c.GLFW_KEY_TAB => {
                self.viewer.suppress_next_char = true;
                self.viewer.insertBytes(self.allocator, "    ");
                self.viewer.refreshCompletion(false);
                self.viewer.ensureCursorVisible(visible);
            },
            else => {},
        }
    }

    fn drawViewer(self: *App) !void {
        const chrome = self.overlayChrome();
        const fb_w = self.window.fb_width;
        const fb_h = self.window.fb_height;
        const cw = @as(i32, @intFromFloat(@max(1.0, self.renderer.cell_w)));
        const ch = @as(i32, @intFromFloat(@max(1.0, self.renderer.cell_h)));
        const margin: i32 = @max(cw * 2, 16);
        const x = margin;
        const y = Tabs.bar_height + 8;
        const w = @max(cw * 20, fb_w - margin * 2);
        const h = @max(ch * 8, fb_h - y - 12);
        const pad_x: i32 = 14;
        const pad_y: i32 = 10;
        const header_h = ch + 18;
        const find_h: i32 = if (self.viewer.find_open) ch + 16 else 0;
        const footer_h = ch + 14;
        const row_h = ch + 4;
        const gutter_cols: i32 = 6;
        const gutter_w = cw * gutter_cols + 10;
        const body_y = y + pad_y + header_h + find_h;
        const body_h = @max(row_h, h - pad_y - header_h - find_h - footer_h);
        const visible: usize = @intCast(@max(1, @divTrunc(body_h, row_h)));
        const code_cols: usize = @intCast(@max(8, @divTrunc(w - pad_x * 2 - gutter_w, cw)));
        self.viewer.ensureCursorVisible(visible);

        try self.renderer.drawRect(0, 0, fb_w, fb_h, chrome.bg, 0.55);
        try self.renderer.drawRect(x, y, w, h, chrome.panel, 0.98);
        try self.renderer.drawRect(x, y, w, 2, chrome.accent, 0.55);

        const name = self.viewer.displayName();
        const lang = viewer_mod.languageLabel(self.viewer.language);
        const dirty_mark: []const u8 = if (self.viewer.dirty) " •" else "";
        var title_buf: [168]u8 = undefined;
        const title = std.fmt.bufPrint(&title_buf, "{s}{s}  ·  {s}", .{ name, dirty_mark, lang }) catch name;
        const title_shown = title[0..@min(title.len, @as(usize, @intCast(@max(8, @divTrunc(w - pad_x * 2, cw)))))];
        try self.renderer.drawText(x + pad_x, y + pad_y, title_shown, chrome.fg);
        try self.renderer.drawRect(x + pad_x, y + pad_y + header_h - 8, w - pad_x * 2, 1, chrome.rule, 0.9);

        if (self.viewer.find_open) {
            const fy = y + pad_y + header_h - 2;
            try self.renderer.drawRect(x + pad_x, fy, w - pad_x * 2, find_h - 4, chrome.field, 1.0);
            var find_buf: [96]u8 = undefined;
            const q = self.viewer.findQuerySlice();
            const n = self.viewer.find_count;
            const find_line = if (q.len == 0)
                "Find in file…"
            else if (n == 0)
                (std.fmt.bufPrint(&find_buf, "Find  {s}   no matches", .{q}) catch "Find")
            else
                (std.fmt.bufPrint(&find_buf, "Find  {s}   {d}/{d}", .{ q, self.viewer.find_sel + 1, n }) catch "Find");
            const find_shown = find_line[0..@min(find_line.len, @as(usize, @intCast(@max(8, @divTrunc(w - pad_x * 2 - 8, cw)))))];
            try self.renderer.drawText(x + pad_x + 8, fy + 4, find_shown, if (q.len == 0) chrome.dim else chrome.accent);
        }

        const text_x = x + pad_x + gutter_w;
        var caret_screen_y: ?i32 = null;

        if (self.viewer.error_msg) |err| {
            try self.renderer.drawText(x + pad_x, body_y + 8, err, chrome.muted);
        } else if (self.viewer.lineCount() == 0) {
            try self.renderer.drawText(x + pad_x, body_y + 8, "(empty file)", chrome.muted);
        } else {
            const start = self.viewer.scroll;
            const total = self.viewer.lineCount();
            const shown_n = @min(visible, total -| start);
            var i: usize = 0;
            var spans: [viewer_mod.max_spans]viewer_mod.Span = undefined;
            while (i < shown_n) : (i += 1) {
                const li = start + i;
                const text = self.viewer.line(li);
                const ry = body_y + @as(i32, @intCast(i)) * row_h;
                const on_cursor = li == self.viewer.cursor_row;
                if (on_cursor) {
                    try self.renderer.drawRect(x + pad_x, ry - 1, w - pad_x * 2, row_h, chrome.sel_bg, 0.28);
                    caret_screen_y = ry;
                }
                if (self.viewer.find_open and self.viewer.find_len > 0) {
                    const qlen = self.viewer.find_len;
                    var hi: usize = 0;
                    while (hi < self.viewer.find_count) : (hi += 1) {
                        const hit = self.viewer.find_hits[hi];
                        if (hit.row != li) continue;
                        if (hit.col >= code_cols) continue;
                        const hw = @min(qlen, code_cols - hit.col);
                        if (hw == 0) continue;
                        const alpha: f32 = if (hi == self.viewer.find_sel) 0.55 else 0.28;
                        try self.renderer.drawRect(
                            text_x + @as(i32, @intCast(hit.col)) * cw,
                            ry,
                            @as(i32, @intCast(hw)) * cw,
                            ch,
                            chrome.accent,
                            alpha,
                        );
                    }
                }
                var num_buf: [12]u8 = undefined;
                const num = std.fmt.bufPrint(&num_buf, "{d: >5}", .{li + 1}) catch "    0";
                try self.renderer.drawText(x + pad_x, ry, num, if (on_cursor) chrome.accent else chrome.dim);

                const clipped = text[0..@min(text.len, code_cols)];
                var state = self.viewer.lineState(li);
                const n = viewer_mod.highlightLine(clipped, self.viewer.language, &state, &spans);
                if (n == 0) {
                    try self.renderer.drawText(text_x, ry, clipped, chrome.fg);
                } else {
                    var si: usize = 0;
                    while (si < n) : (si += 1) {
                        const span = spans[si];
                        if (span.start >= clipped.len) break;
                        const end = @min(span.end, clipped.len);
                        if (end <= span.start) continue;
                        const color = viewer_mod.colorFor(span.kind, self.renderer.theme);
                        try self.renderer.drawText(
                            text_x + @as(i32, @intCast(span.start)) * cw,
                            ry,
                            clipped[span.start..end],
                            color,
                        );
                    }
                }
            }

            if (caret_screen_y) |cy| {
                const col = @min(self.viewer.cursor_col, code_cols);
                const cx = text_x + @as(i32, @intCast(col)) * cw;
                try self.renderer.drawRect(cx, cy, @max(2, @divTrunc(cw, 5)), ch, chrome.accent, 0.95);
            }
        }

        if (self.viewer.complete_open and self.viewer.complete_n > 0) {
            try self.drawCompletionPopup(chrome, text_x, body_y, body_h, w, pad_x, x, cw, ch, row_h, code_cols);
        }

        var foot: [128]u8 = undefined;
        const lines = self.viewer.lineCount();
        const foot_line = std.fmt.bufPrint(
            &foot,
            "{d} lines   ⌘/Ctrl+S save   ⌘/Ctrl+F find   Ctrl+Shift+F code   Esc close",
            .{lines},
        ) catch "Esc close";
        const foot_shown = foot_line[0..@min(foot_line.len, @as(usize, @intCast(@max(8, @divTrunc(w - pad_x * 2, cw)))))];
        try self.renderer.drawText(x + pad_x, y + h - footer_h + 2, foot_shown, chrome.dim);
    }

    fn drawCompletionPopup(
        self: *App,
        chrome: ui_chrome.Chrome,
        text_x: i32,
        body_y: i32,
        body_h: i32,
        panel_w: i32,
        pad_x: i32,
        panel_x: i32,
        cw: i32,
        ch: i32,
        row_h: i32,
        code_cols: usize,
    ) !void {
        const n = self.viewer.complete_n;
        const line_text = self.viewer.line(self.viewer.cursor_row);
        const col = @min(self.viewer.cursor_col, line_text.len);
        const prefix = viewer_mod.identPrefix(line_text, col);
        const prefix_col = col - prefix.len;
        const vis_row = self.viewer.cursor_row -| self.viewer.scroll;
        const caret_y = body_y + @as(i32, @intCast(vis_row)) * row_h;
        const doc_h = ch + 10;
        const list_h = @as(i32, @intCast(n)) * row_h;
        const pop_h = list_h + doc_h;
        const pop_w = @min(@as(i32, @intCast(@min(code_cols, 56))) * cw, @max(cw * 24, panel_w - pad_x * 2 - (text_x - panel_x)));
        var pop_x = text_x + @as(i32, @intCast(@min(prefix_col, code_cols))) * cw;
        if (pop_x + pop_w > panel_x + panel_w - pad_x) {
            pop_x = panel_x + panel_w - pad_x - pop_w;
        }
        pop_x = @max(panel_x + pad_x, pop_x);

        const below_y = caret_y + row_h + 2;
        const above_y = caret_y - pop_h - 2;
        const pop_y = if (below_y + pop_h <= body_y + body_h) below_y else @max(body_y, above_y);

        try self.renderer.drawRect(pop_x, pop_y, pop_w, pop_h, chrome.field, 0.98);
        try self.renderer.drawRect(pop_x, pop_y, pop_w, 2, chrome.accent, 0.7);

        const cols: usize = @intCast(@max(8, @divTrunc(pop_w - 16, cw)));
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const hit = self.viewer.complete_hits[i];
            const ry = pop_y + 4 + @as(i32, @intCast(i)) * row_h;
            if (i == self.viewer.complete_sel) {
                try self.renderer.drawRect(pop_x + 2, ry - 1, pop_w - 4, row_h, chrome.sel_bg, 0.85);
            }
            const kind = hit.kindTag();
            try self.renderer.drawText(pop_x + 8, ry, kind, chrome.dim);
            const label_x = pop_x + 8 + cw * 4;
            const label = hit.label();
            const label_shown = label[0..@min(label.len, cols / 2)];
            try self.renderer.drawText(label_x, ry, label_shown, chrome.fg);
            if (hit.detail.len > 0 and cols > label_shown.len + 10) {
                const det = hit.detail[0..@min(hit.detail.len, cols / 3)];
                const det_x = pop_x + pop_w - 8 - @as(i32, @intCast(det.len)) * cw;
                if (det_x > label_x + @as(i32, @intCast(label_shown.len)) * cw) {
                    try self.renderer.drawText(det_x, ry, det, chrome.muted);
                }
            }
        }

        const sel = self.viewer.complete_hits[self.viewer.complete_sel];
        const doc_y = pop_y + list_h + 2;
        try self.renderer.drawRect(pop_x, doc_y - 1, pop_w, 1, chrome.rule, 0.8);
        const doc = if (sel.doc.len > 0) sel.doc else sel.detail;
        const doc_shown = doc[0..@min(doc.len, cols)];
        try self.renderer.drawText(pop_x + 8, doc_y + 2, doc_shown, chrome.muted);
    }

    fn openSession(
        self: *App,
        cwd: []const u8,
        title_opt: ?[]const u8,
        command: []const []const u8,
        wait_after: bool,
    ) !void {
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

        var prompt_buf: [80]u8 = undefined;
        var env_refs: [3][]const u8 = undefined;
        const env = self.sessionLaunchEnv(&prompt_buf, &env_refs);

        const session = try Session.createWith(self.allocator, .{
            .cols = cols,
            .rows = rows,
            .title = title,
            .cwd = cwd,
            .shell = launch,
            .env = env,
            .command = command,
            .wait_after_command = wait_after,
        });
        session.setTheme(theme.foreground, theme.background);
        session.setScrollback(self.config.scrollback);
        try self.tabs.add(title, session);
        self.ui = .normal;
        self.updateWindowTitle();
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
        var prompt_buf: [80]u8 = undefined;
        var env_refs: [3][]const u8 = undefined;
        const env = self.sessionLaunchEnv(&prompt_buf, &env_refs);
        const session = try Session.createWith(self.allocator, .{
            .cols = cols,
            .rows = rows,
            .title = "Split",
            .cwd = self.sessionCwd(),
            .shell = self.config.resolveLaunchShell(),
            .env = env,
        });
        session.setTheme(theme.foreground, theme.background);
        session.setScrollback(self.config.scrollback);
        try tab.layout.splitFocused(dir, session);
        self.resizeAllSessions();
    }

    fn sessionLaunchEnv(self: *const App, prompt_buf: *[80]u8, refs: *[3][]const u8) []const []const u8 {
        refs[0] = "ORBIT_TERMINAL=1";
        refs[1] = "TERM_PROGRAM=Orbit";
        refs[2] = std.fmt.bufPrint(prompt_buf, "ORBIT_PROMPT={s}", .{self.config.prompt.name()}) catch "ORBIT_PROMPT=default";
        return refs[0..3];
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
        if (text.len == 0) return;
        // Cap paste size (matches copy buffer) to limit paste-jacking / DoS.
        const capped = text[0..@min(text.len, 64 * 1024)];
        const has_newline = std.mem.indexOfScalar(u8, capped, '\n') != null or
            std.mem.indexOfScalar(u8, capped, '\r') != null;
        if (has_newline) {
            // Bracketed paste so shells that support it treat the blob as literal text.
            session.write("\x1b[200~");
            session.write(capped);
            session.write("\x1b[201~");
        } else {
            session.write(capped);
        }
    }

    /// Focus the pane under framebuffer coords; returns session + leaf rect if any.
    fn focusSessionAt(self: *App, fb_x: i32, fb_y: i32) ?struct { session: *Session, rect: Rect } {
        const tab = self.tabs.current() orelse return null;
        const bounds = self.contentRect();
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
        var hit: Hit = .{ .px = fb_x, .py = fb_y };
        tab.layout.forEachLeaf(bounds, *Hit, &hit, Hit.cb);
        if (hit.session) |s| {
            tab.layout.focused = s;
            return .{ .session = s, .rect = hit.rect };
        }
        return null;
    }

    fn onMouseButton(ptr: *anyopaque, button: c_int, action: c_int, mods: c_int) void {
        _ = mods;
        const self: *App = @ptrCast(@alignCast(ptr));
        if (self.ui != .normal) return;
        const fb = self.window.windowToFb(self.mouse_x, self.mouse_y);

        // Context menu interaction (open on right-click; activate / dismiss on left-click).
        if (button == c.GLFW_MOUSE_BUTTON_RIGHT and action == c.GLFW_PRESS) {
            if (self.focusSessionAt(fb.x, fb.y) != null) {
                self.openContextMenu(fb.x, fb.y);
            }
            return;
        }

        if (button == c.GLFW_MOUSE_BUTTON_LEFT) {
            if (action == c.GLFW_PRESS) {
                if (self.context_menu) |menu| {
                    if (self.contextMenuHit(menu, fb.x, fb.y)) |idx| {
                        const can_copy = if (self.focused()) |s| s.selection.active else false;
                        if (idx == 0 and !can_copy) return;
                        self.runContextMenuItem(idx);
                        return;
                    }
                    self.closeContextMenu();
                    // Fall through so a click outside still starts selection.
                }
                if (self.focusSessionAt(fb.x, fb.y)) |hit| {
                    const cw: i32 = @intFromFloat(@max(1.0, self.renderer.cell_w));
                    const ch: i32 = @intFromFloat(@max(1.0, self.renderer.cell_h));
                    const col: u16 = @intCast(@max(0, @divTrunc(fb.x - hit.rect.x, cw)));
                    const row: u16 = @intCast(@max(0, @divTrunc(fb.y - hit.rect.y, ch)));
                    hit.session.selection.begin(@min(col, hit.session.screen.cols -| 1), @min(row, hit.session.screen.rows -| 1));
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

        const fb = self.window.windowToFb(x, y);
        if (self.context_menu) |*menu| {
            if (self.contextMenuHit(menu.*, fb.x, fb.y)) |idx| {
                menu.hover = idx;
            }
            return;
        }

        const session = self.focused() orelse return;
        if (!session.selection.selecting) return;

        const tab = self.tabs.current() orelse return;
        const bounds = self.contentRect();

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
        if (self.ui == .viewer) {
            const lines: i32 = @intFromFloat(-yoff * 3.0);
            self.viewer.scrollBy(lines, self.viewerVisibleLines());
            return;
        }
        if (self.ui == .plugin_result) {
            const lines: i32 = @intFromFloat(-yoff * 3.0);
            self.plugin_result.scrollBy(lines, self.pluginResultVisibleLines());
            return;
        }
        if (self.ui != .normal) return;
        const session = self.focused() orelse return;
        const lines: i32 = @intFromFloat(yoff * 3.0);
        session.screen.scrollView(lines);
    }
};

fn clipUiText(text: []const u8, max_cols: i32) []const u8 {
    if (max_cols <= 0) return "";
    return text[0..@min(text.len, @as(usize, @intCast(max_cols)))];
}

fn wrapUiText(text: []const u8, max_cols: usize) struct { line: []const u8, rest: []const u8 } {
    const skip = std.mem.trimStart(u8, text, " ");
    if (skip.len == 0) return .{ .line = "", .rest = "" };
    if (max_cols == 0) return .{ .line = "", .rest = skip };
    if (skip.len <= max_cols) return .{ .line = skip, .rest = "" };
    var i = max_cols;
    const floor = @max(@as(usize, 1), max_cols / 2);
    while (i > floor) : (i -= 1) {
        if (skip[i] == ' ') {
            return .{ .line = skip[0..i], .rest = skip[i + 1 ..] };
        }
    }
    return .{ .line = skip[0..max_cols], .rest = skip[max_cols..] };
}
