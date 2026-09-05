//! Minimal TOML subset loader for Orbit config.

const std = @import("std");
const builtin = @import("builtin");
const theme_mod = @import("theme.zig");
const look_mod = @import("look.zig");
const keybind_mod = @import("keybind.zig");
const faces = @import("../font/faces.zig");
const paths = @import("../platform/paths.zig");
const shell_guard = @import("../platform/shell.zig");

pub const Keymap = keybind_mod.Keymap;

pub const Look = look_mod.Look;
pub const PromptStyle = look_mod.PromptStyle;

pub const CursorStyle = enum {
    block,
    underline,
    bar,

    pub fn fromString(s: []const u8) CursorStyle {
        if (std.mem.eql(u8, s, "underline")) return .underline;
        if (std.mem.eql(u8, s, "bar") or std.mem.eql(u8, s, "beam")) return .bar;
        return .block;
    }

    pub fn name(self: CursorStyle) []const u8 {
        return switch (self) {
            .block => "block",
            .underline => "underline",
            .bar => "bar",
        };
    }

    pub fn next(self: CursorStyle) CursorStyle {
        return switch (self) {
            .block => .underline,
            .underline => .bar,
            .bar => .block,
        };
    }

    pub fn prev(self: CursorStyle) CursorStyle {
        return switch (self) {
            .block => .bar,
            .underline => .block,
            .bar => .underline,
        };
    }
};

/// Common shells users can cycle in Settings (next new tab uses this).
pub const shell_choices = if (builtin.os.tag == .windows) [_][]const u8{
    "", // empty = default shell
    "powershell.exe",
    "pwsh.exe",
    "cmd.exe",
} else [_][]const u8{
    "", // empty = $SHELL
    "/bin/zsh",
    "/bin/bash",
    "/bin/sh",
    "/opt/homebrew/bin/fish",
    "/usr/local/bin/fish",
    "/opt/homebrew/bin/zsh",
    "/usr/local/bin/zsh",
};

pub const Config = struct {
    window_width: i32 = 900,
    window_height: i32 = 560,
    opacity: f32 = 1.0,
    theme_name: []const u8 = "orbit-dark",
    /// Text color preset id (`theme` = use theme default). See `theme.fg_presets`.
    fg_preset: []const u8 = "theme",
    scrollback: usize = 2000,
    /// Font size in points (Ghostty-style). Scaled for Retina automatically.
    font_size: f32 = 14.0,
    /// Monospace face id (`sf-mono`, `menlo`, …). See `font/faces.zig`.
    font_face: []const u8 = faces.catalog[0].id,
    /// Interior padding in logical pixels (Ghostty window-padding).
    padding_x: i32 = 10,
    padding_y: i32 = 6,
    /// Extra line spacing as a multiplier (Ghostty adjust-cell-height). 1.0 = tight.
    line_height: f32 = 1.0,
    /// Named Ghostty-style look (padding + spacing + opacity).
    look: Look = .compact,
    /// Prompt overlay for new tabs (`default` keeps the user's shell rc).
    prompt: PromptStyle = .default,
    /// Shell executable; null/empty means $SHELL (or /bin/zsh).
    shell: ?[]const u8 = null,
    cursor_style: CursorStyle = .block,
    cursor_blink: bool = true,
    /// Reload the last saved layout when Orbit starts with no folder argument.
    restore_last_workspace: bool = true,
    /// Programming ligatures (`=>`, `!=`, `->`). HarfBuzz when built with `-Dharfbuzz`.
    font_ligatures: bool = true,
    /// Git remote for `orbit sync` (config + workspaces + ssh.toml).
    sync_remote: ?[]const u8 = null,
    /// Owned theme name buffer when loaded from file.
    theme_name_owned: ?[]u8 = null,
    fg_preset_owned: ?[]u8 = null,
    font_face_owned: ?[]u8 = null,
    shell_owned: ?[]u8 = null,
    sync_remote_owned: ?[]u8 = null,
    /// User `keybind = …` lines, in file order (Ghostty-compatible).
    keybind_lines: [][]u8 = &.{},
    /// Compiled defaults + user keybinds.
    keymap: Keymap = .{},

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.theme_name_owned) |t| allocator.free(t);
        if (self.fg_preset_owned) |f| allocator.free(f);
        if (self.font_face_owned) |f| allocator.free(f);
        if (self.shell_owned) |s| allocator.free(s);
        if (self.sync_remote_owned) |s| allocator.free(s);
        self.theme_name_owned = null;
        self.fg_preset_owned = null;
        self.font_face_owned = null;
        self.shell_owned = null;
        self.sync_remote_owned = null;
        self.shell = null;
        self.sync_remote = null;
        self.freeKeybindLines(allocator);
        self.keymap.deinit(allocator);
    }

    pub fn fontFaceDisplay(self: *const Config) []const u8 {
        return faces.labelForId(self.font_face);
    }

    pub fn setFontFace(self: *Config, allocator: std.mem.Allocator, id: []const u8) !void {
        if (self.font_face_owned) |old| allocator.free(old);
        const owned = try allocator.dupe(u8, id);
        self.font_face_owned = owned;
        self.font_face = owned;
    }

    pub fn cycleFontFace(self: *Config, allocator: std.mem.Allocator, delta: i32) !void {
        const next = faces.nextInstalledId(self.font_face, delta);
        try self.setFontFace(allocator, next);
    }

    pub fn theme(self: *const Config) theme_mod.Theme {
        return theme_mod.withFgOverride(theme_mod.byName(self.theme_name), self.fg_preset);
    }

    pub fn fgDisplay(self: *const Config) []const u8 {
        return theme_mod.fgPresetById(self.fg_preset).label;
    }

    pub fn shellPath(self: *const Config) ?[]const u8 {
        if (self.shell) |s| {
            if (s.len > 0) return s;
        }
        return null;
    }

    /// Shell to launch: configured path if allowed and present, else platform default.
    pub fn resolveLaunchShell(self: *const Config) []const u8 {
        if (self.shellPath()) |s| {
            return shell_guard.sanitize(s);
        }
        return shell_guard.sanitize(null);
    }

    pub fn shellDisplay(self: *const Config) []const u8 {
        if (self.shellPath()) |s| {
            if (!paths.pathExecutable(s)) {
                // Still show configured name so Settings can fix it
                if (std.mem.lastIndexOfAny(u8, s, "/\\")) |i| return s[i + 1 ..];
                return s;
            }
            if (std.mem.lastIndexOfAny(u8, s, "/\\")) |i| return s[i + 1 ..];
            return s;
        }
        return if (builtin.os.tag == .windows) "default" else "$SHELL";
    }

    pub fn setThemeName(self: *Config, allocator: std.mem.Allocator, name: []const u8) !void {
        if (self.theme_name_owned) |old| allocator.free(old);
        const owned = try allocator.dupe(u8, name);
        self.theme_name_owned = owned;
        self.theme_name = owned;
    }

    pub fn setFgPreset(self: *Config, allocator: std.mem.Allocator, id: []const u8) !void {
        const canonical = theme_mod.fgPresetById(id).id;
        if (self.fg_preset_owned) |old| allocator.free(old);
        const owned = try allocator.dupe(u8, canonical);
        self.fg_preset_owned = owned;
        self.fg_preset = owned;
    }

    pub fn cycleFgPreset(self: *Config, allocator: std.mem.Allocator, delta: i32) !void {
        const next = theme_mod.nextFgPresetId(self.fg_preset, delta);
        try self.setFgPreset(allocator, next);
    }

    pub fn setShell(self: *Config, allocator: std.mem.Allocator, path: []const u8) !void {
        if (self.shell_owned) |old| allocator.free(old);
        self.shell_owned = null;
        self.shell = null;
        if (path.len == 0) return;
        if (!shell_guard.isAllowed(path)) return;
        const owned = try allocator.dupe(u8, path);
        self.shell_owned = owned;
        self.shell = owned;
    }

    pub fn applyLook(self: *Config, look: Look) void {
        self.look = look;
        self.padding_x = look.paddingX();
        self.padding_y = look.paddingY();
        self.line_height = look.lineHeight();
        self.opacity = look.opacity();
    }

    pub fn cycleLook(self: *Config, delta: i32) void {
        self.applyLook(if (delta >= 0) self.look.next() else self.look.prev());
    }

    pub fn cycleOpacity(self: *Config, delta: i32) void {
        self.opacity = look_mod.cycleOpacity(self.opacity, delta);
        self.opacity = @min(1.0, @max(0.15, self.opacity));
    }

    pub fn cyclePadding(self: *Config, delta: i32) void {
        self.padding_x = look_mod.cyclePadding(self.padding_x, delta);
        // Keep a Ghostty-like ratio: vertical padding a bit tighter than horizontal.
        self.padding_y = @max(2, @divTrunc(self.padding_x * 5, 8));
        self.padding_x = @max(0, @min(48, self.padding_x));
        self.padding_y = @max(0, @min(48, self.padding_y));
    }

    pub fn cycleLineHeight(self: *Config, delta: i32) void {
        self.line_height = look_mod.cycleLineHeight(self.line_height, delta);
    }

    pub fn cyclePrompt(self: *Config, delta: i32) void {
        self.prompt = if (delta >= 0) self.prompt.next() else self.prompt.prev();
    }

    pub fn lineHeightDisplay(self: *const Config) []const u8 {
        return look_mod.lineHeightLabel(self.line_height);
    }

    pub fn cycleShell(self: *Config, allocator: std.mem.Allocator, delta: i32) !void {
        // Build list of available choices (empty = $SHELL, plus existing binaries).
        var available: [shell_choices.len][]const u8 = undefined;
        var count: usize = 0;
        for (shell_choices) |choice| {
            if (choice.len == 0) {
                available[count] = choice;
                count += 1;
            } else if (paths.pathExecutable(choice)) {
                available[count] = choice;
                count += 1;
            }
        }
        if (count == 0) return;

        const current = self.shell orelse "";
        var idx: i32 = 0;
        for (available[0..count], 0..) |c, i| {
            if (std.mem.eql(u8, c, current)) {
                idx = @intCast(i);
                break;
            }
        }
        const n: i32 = @intCast(count);
        idx = @mod(idx + delta, n);
        if (idx < 0) idx += n;
        try self.setShell(allocator, available[@intCast(idx)]);
    }

    pub fn reload(self: *Config, allocator: std.mem.Allocator, io: std.Io) void {
        self.deinit(allocator);
        self.* = Config.load(allocator, io);
    }

    pub fn load(allocator: std.mem.Allocator, io: std.Io) Config {
        var cfg: Config = .{};
        cfg.rebuildKeymap(allocator);
        const path = paths.joinConfig(allocator, &.{"config.toml"}) catch return cfg;
        defer allocator.free(path);

        const file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return cfg;
        defer file.close(io);

        var buf: [4096]u8 = undefined;
        var reader = file.reader(io, &buf);
        const data = reader.interface.allocRemaining(allocator, .limited(64 * 1024)) catch return cfg;
        defer allocator.free(data);

        parseInto(&cfg, allocator, data);
        return cfg;
    }

    /// Persist current settings to the Orbit config file.
    pub fn save(self: *const Config, allocator: std.mem.Allocator, io: std.Io) !void {
        const dir_path = try paths.configDir(allocator);
        defer allocator.free(dir_path);
        paths.ensureDir(dir_path);

        const path = try std.fmt.allocPrint(allocator, "{s}{c}config.toml", .{ dir_path, std.fs.path.sep });
        defer allocator.free(path);

        var body: std.ArrayList(u8) = .empty;
        defer body.deinit(allocator);

        try body.appendSlice(allocator,
            \\# Orbit config — appearance & terminal
            \\
            \\[window]
            \\
        );
        try appendFmt(&body, allocator, "width = {d}\n", .{self.window_width});
        try appendFmt(&body, allocator, "height = {d}\n", .{self.window_height});
        try appendFmt(&body, allocator, "look = \"{s}\"\n", .{self.look.name()});
        try appendFmt(&body, allocator, "opacity = {d:.2}\n", .{self.opacity});
        try body.appendSlice(allocator, "\n[theme]\n");
        try appendFmt(&body, allocator, "name = \"{s}\"\n", .{self.theme_name});
        try appendFmt(&body, allocator, "foreground = \"{s}\"\n", .{self.fg_preset});
        try body.appendSlice(allocator,
            \\
            \\[terminal]
            \\
        );
        try appendFmt(&body, allocator, "scrollback = {d}\n", .{self.scrollback});
        try appendFmt(&body, allocator, "font_size = {d:.0}\n", .{self.font_size});
        try appendFmt(&body, allocator, "font_face = \"{s}\"\n", .{self.font_face});
        try appendFmt(&body, allocator, "padding_x = {d}\n", .{self.padding_x});
        try appendFmt(&body, allocator, "padding_y = {d}\n", .{self.padding_y});
        try appendFmt(&body, allocator, "line_height = {d:.2}\n", .{self.line_height});
        try appendFmt(&body, allocator, "prompt = \"{s}\"\n", .{self.prompt.name()});
        try appendFmt(&body, allocator, "cursor_style = \"{s}\"\n", .{self.cursor_style.name()});
        try appendFmt(&body, allocator, "cursor_blink = {s}\n", .{if (self.cursor_blink) "true" else "false"});
        try appendFmt(&body, allocator, "restore_last_workspace = {s}\n", .{if (self.restore_last_workspace) "true" else "false"});
        try appendFmt(&body, allocator, "font_ligatures = {s}\n", .{if (self.font_ligatures) "true" else "false"});
        try body.appendSlice(allocator, "\n[sync]\n");
        if (self.sync_remote) |r| {
            try appendFmt(&body, allocator, "remote = \"{s}\"\n", .{r});
        } else {
            try body.appendSlice(allocator, "# remote = \"git@github.com:you/orbit-dotfiles.git\"\n");
        }
        if (self.shellPath()) |sh| {
            try appendFmt(&body, allocator, "shell = \"{s}\"\n", .{sh});
        } else {
            try body.appendSlice(allocator, if (builtin.os.tag == .windows)
                "# shell = \"powershell.exe\"  # or \"pwsh.exe\" / \"cmd.exe\"\n"
            else
                "# shell = \"$SHELL\"  # e.g. \"/bin/bash\" or \"/bin/zsh\"\n");
        }

        try body.appendSlice(allocator,
            \\
            \\# Custom keybindings (Ghostty-compatible).
            \\# keybind = trigger=action
            \\# See https://ghostty.org/docs/config/keybind
            \\
        );
        if (self.keybind_lines.len == 0) {
            try body.appendSlice(allocator,
                \\# keybind = ctrl+shift+t=new_tab
                \\# keybind = performable:ctrl+c=copy_to_clipboard
                \\# keybind = ctrl+a>n=new_tab
                \\# keybind = ctrl+k=reload_config
                \\
            );
        } else {
            for (self.keybind_lines) |line| {
                try appendFmt(&body, allocator, "keybind = {s}\n", .{line});
            }
        }

        const file = try std.Io.Dir.createFileAbsolute(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, body.items);
    }

    pub fn parseInto(cfg: *Config, allocator: std.mem.Allocator, data: []const u8) void {
        var keybinds: std.ArrayList([]u8) = .empty;
        defer keybinds.deinit(allocator);

        var section: enum { none, window, theme, terminal, keybind, sync } = .none;
        var lines = std.mem.splitScalar(u8, data, '\n');
        while (lines.next()) |raw| {
            var line = std.mem.trim(u8, raw, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;
            if (line[0] == '[') {
                if (std.mem.indexOfScalar(u8, line, ']')) |end| {
                    const name = std.mem.trim(u8, line[1..end], " \t");
                    if (std.mem.eql(u8, name, "window")) {
                        section = .window;
                    } else if (std.mem.eql(u8, name, "theme")) {
                        section = .theme;
                    } else if (std.mem.eql(u8, name, "terminal")) {
                        section = .terminal;
                    } else if (std.mem.eql(u8, name, "keybind") or std.mem.eql(u8, name, "keybinds")) {
                        section = .keybind;
                    } else if (std.mem.eql(u8, name, "sync")) {
                        section = .sync;
                    } else {
                        section = .none;
                    }
                }
                continue;
            }
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            var key = std.mem.trim(u8, line[0..eq], " \t");
            var val = std.mem.trim(u8, line[eq + 1 ..], " \t");
            if (key.len >= 2 and ((key[0] == '"' and key[key.len - 1] == '"') or (key[0] == '\'' and key[key.len - 1] == '\''))) {
                key = key[1 .. key.len - 1];
            }
            if (val.len >= 2 and ((val[0] == '"' and val[val.len - 1] == '"') or (val[0] == '\'' and val[val.len - 1] == '\''))) {
                val = val[1 .. val.len - 1];
            }

            if (std.mem.eql(u8, key, "keybind") or std.mem.eql(u8, key, "keybinds")) {
                appendKeybind(&keybinds, allocator, val);
                continue;
            }
            if (section == .keybind) {
                appendKeybindSpec(&keybinds, allocator, key, val);
                continue;
            }

            switch (section) {
                .window => {
                    if (std.mem.eql(u8, key, "width")) cfg.window_width = parseI32(val) orelse cfg.window_width;
                    if (std.mem.eql(u8, key, "height")) cfg.window_height = parseI32(val) orelse cfg.window_height;
                    if (std.mem.eql(u8, key, "look")) cfg.applyLook(Look.fromString(val));
                    if (std.mem.eql(u8, key, "opacity") or std.mem.eql(u8, key, "background-opacity") or std.mem.eql(u8, key, "background_opacity")) {
                        cfg.opacity = parseF32(val) orelse cfg.opacity;
                    }
                },
                .theme => {
                    if (std.mem.eql(u8, key, "name")) {
                        if (cfg.theme_name_owned) |old| allocator.free(old);
                        const owned = allocator.dupe(u8, val) catch continue;
                        cfg.theme_name_owned = owned;
                        cfg.theme_name = owned;
                    }
                    if (std.mem.eql(u8, key, "foreground") or std.mem.eql(u8, key, "text") or std.mem.eql(u8, key, "fg")) {
                        if (cfg.fg_preset_owned) |old| allocator.free(old);
                        const canonical = theme_mod.fgPresetById(val).id;
                        const owned = allocator.dupe(u8, canonical) catch continue;
                        cfg.fg_preset_owned = owned;
                        cfg.fg_preset = owned;
                    }
                },
                .terminal => {
                    if (std.mem.eql(u8, key, "scrollback")) {
                        cfg.scrollback = @intCast(parseI32(val) orelse @as(i32, @intCast(cfg.scrollback)));
                    }
                    if (std.mem.eql(u8, key, "font_size")) {
                        cfg.font_size = parseF32(val) orelse cfg.font_size;
                        cfg.font_size = @min(28.0, @max(9.0, cfg.font_size));
                    }
                    if (std.mem.eql(u8, key, "font_face") or std.mem.eql(u8, key, "font_family") or std.mem.eql(u8, key, "font")) {
                        const id = if (faces.byId(val) != null) val else faces.defaultId();
                        if (cfg.font_face_owned) |old| allocator.free(old);
                        const owned = allocator.dupe(u8, id) catch continue;
                        cfg.font_face_owned = owned;
                        cfg.font_face = owned;
                    }
                    if (std.mem.eql(u8, key, "font_scale")) {
                        const scale = parseF32(val) orelse 2.0;
                        cfg.font_size = @min(28.0, @max(9.0, 14.0 * scale / 2.0));
                    }
                    if (std.mem.eql(u8, key, "look")) cfg.applyLook(Look.fromString(val));
                    if (std.mem.eql(u8, key, "padding_x") or std.mem.eql(u8, key, "window-padding-x") or std.mem.eql(u8, key, "window_padding_x")) {
                        cfg.padding_x = parseI32(val) orelse cfg.padding_x;
                        cfg.padding_x = @max(0, @min(48, cfg.padding_x));
                    }
                    if (std.mem.eql(u8, key, "padding_y") or std.mem.eql(u8, key, "window-padding-y") or std.mem.eql(u8, key, "window_padding_y")) {
                        cfg.padding_y = parseI32(val) orelse cfg.padding_y;
                        cfg.padding_y = @max(0, @min(48, cfg.padding_y));
                    }
                    if (std.mem.eql(u8, key, "line_height") or std.mem.eql(u8, key, "adjust-cell-height") or std.mem.eql(u8, key, "adjust_cell_height")) {
                        cfg.line_height = look_mod.parseLineHeight(val) orelse cfg.line_height;
                    }
                    if (std.mem.eql(u8, key, "prompt") or std.mem.eql(u8, key, "prompt_style")) {
                        cfg.prompt = PromptStyle.fromString(val);
                    }
                    if (std.mem.eql(u8, key, "shell")) {
                        if (!shell_guard.isAllowed(val)) continue;
                        if (cfg.shell_owned) |old| allocator.free(old);
                        const owned = allocator.dupe(u8, val) catch continue;
                        cfg.shell_owned = owned;
                        cfg.shell = owned;
                    }
                    if (std.mem.eql(u8, key, "cursor_style")) {
                        cfg.cursor_style = CursorStyle.fromString(val);
                    }
                    if (std.mem.eql(u8, key, "cursor_blink")) {
                        cfg.cursor_blink = parseBool(val);
                    }
                    if (std.mem.eql(u8, key, "restore_last_workspace") or std.mem.eql(u8, key, "restore-last-workspace")) {
                        cfg.restore_last_workspace = parseBool(val);
                    }
                    if (std.mem.eql(u8, key, "font_ligatures") or std.mem.eql(u8, key, "font-ligatures") or std.mem.eql(u8, key, "ligatures")) {
                        cfg.font_ligatures = parseBool(val);
                    }
                },
                .sync => {
                    if (std.mem.eql(u8, key, "remote") or std.mem.eql(u8, key, "url")) {
                        if (cfg.sync_remote_owned) |old| allocator.free(old);
                        const owned = allocator.dupe(u8, val) catch continue;
                        cfg.sync_remote_owned = owned;
                        cfg.sync_remote = owned;
                    }
                },
                .keybind, .none => {},
            }
        }
        cfg.opacity = @min(1.0, @max(0.15, cfg.opacity));
        cfg.line_height = @min(1.5, @max(1.0, cfg.line_height));

        cfg.freeKeybindLines(allocator);
        cfg.keybind_lines = keybinds.toOwnedSlice(allocator) catch blk: {
            for (keybinds.items) |l| allocator.free(l);
            keybinds.clearRetainingCapacity();
            break :blk &.{};
        };

        // Drop configured shell if disallowed or missing (e.g. fish not installed).
        if (cfg.shell) |s| {
            if (s.len > 0 and (!shell_guard.isAllowed(s) or !paths.pathExecutable(s))) {
                if (cfg.shell_owned) |old| allocator.free(old);
                cfg.shell_owned = null;
                cfg.shell = null;
            }
        }

        // Fall back if the chosen face isn't installed.
        if (faces.pathForId(cfg.font_face) == null) {
            const fallback = faces.defaultId();
            if (cfg.font_face_owned) |old| allocator.free(old);
            if (allocator.dupe(u8, fallback)) |owned| {
                cfg.font_face_owned = owned;
                cfg.font_face = owned;
            } else |_| {
                cfg.font_face_owned = null;
                cfg.font_face = fallback;
            }
        }

        cfg.rebuildKeymap(allocator);
    }

    fn freeKeybindLines(self: *Config, allocator: std.mem.Allocator) void {
        for (self.keybind_lines) |line| allocator.free(line);
        if (self.keybind_lines.len > 0) allocator.free(self.keybind_lines);
        self.keybind_lines = &.{};
    }

    fn rebuildKeymap(self: *Config, allocator: std.mem.Allocator) void {
        self.keymap.deinit(allocator);
        self.keymap = .{};
        self.keymap.loadDefaults(allocator) catch {};
        for (self.keybind_lines) |line| {
            self.keymap.applyLine(allocator, line) catch {};
        }
    }
};

fn appendFmt(list: *std.ArrayList(u8), allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const slice = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(slice);
    try list.appendSlice(allocator, slice);
}

fn parseI32(s: []const u8) ?i32 {
    return std.fmt.parseInt(i32, s, 10) catch null;
}

fn parseF32(s: []const u8) ?f32 {
    return std.fmt.parseFloat(f32, s) catch null;
}

fn parseBool(s: []const u8) bool {
    return std.mem.eql(u8, s, "true") or std.mem.eql(u8, s, "1") or std.mem.eql(u8, s, "yes");
}

fn appendKeybind(list: *std.ArrayList([]u8), allocator: std.mem.Allocator, val: []const u8) void {
    if (list.items.len >= keybind_mod.max_bindings) return;
    const owned = allocator.dupe(u8, val) catch return;
    list.append(allocator, owned) catch allocator.free(owned);
}

fn appendKeybindSpec(list: *std.ArrayList([]u8), allocator: std.mem.Allocator, trigger: []const u8, action: []const u8) void {
    if (list.items.len >= keybind_mod.max_bindings) return;
    const spec = std.fmt.allocPrint(allocator, "{s}={s}", .{ trigger, action }) catch return;
    list.append(allocator, spec) catch allocator.free(spec);
}
