//! Minimal TOML subset loader for Orbit config (~/.config/orbit/config.toml).

const std = @import("std");
const theme_mod = @import("theme.zig");

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
pub const shell_choices = [_][]const u8{
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
    /// Interior padding in logical pixels (Ghostty window-padding).
    padding_x: i32 = 10,
    padding_y: i32 = 6,
    /// Shell executable; null/empty means $SHELL (or /bin/zsh).
    shell: ?[]const u8 = null,
    cursor_style: CursorStyle = .block,
    cursor_blink: bool = true,
    /// Owned theme name buffer when loaded from file.
    theme_name_owned: ?[]u8 = null,
    fg_preset_owned: ?[]u8 = null,
    shell_owned: ?[]u8 = null,

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.theme_name_owned) |t| allocator.free(t);
        if (self.fg_preset_owned) |f| allocator.free(f);
        if (self.shell_owned) |s| allocator.free(s);
        self.theme_name_owned = null;
        self.fg_preset_owned = null;
        self.shell_owned = null;
        self.shell = null;
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

    /// Shell to launch: configured path if it exists, else $SHELL, else /bin/zsh.
    pub fn resolveLaunchShell(self: *const Config) []const u8 {
        if (self.shellPath()) |s| {
            if (pathExecutable(s)) return s;
        }
        if (std.c.getenv("SHELL")) |env| {
            const span = std.mem.span(env);
            if (span.len > 0 and pathExecutable(span)) return span;
        }
        if (pathExecutable("/bin/zsh")) return "/bin/zsh";
        if (pathExecutable("/bin/bash")) return "/bin/bash";
        return "/bin/sh";
    }

    pub fn shellDisplay(self: *const Config) []const u8 {
        if (self.shellPath()) |s| {
            if (!pathExecutable(s)) {
                // Still show configured name so Settings can fix it
                if (std.mem.lastIndexOfScalar(u8, s, '/')) |i| return s[i + 1 ..];
                return s;
            }
            if (std.mem.lastIndexOfScalar(u8, s, '/')) |i| return s[i + 1 ..];
            return s;
        }
        return "$SHELL";
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
        const owned = try allocator.dupe(u8, path);
        self.shell_owned = owned;
        self.shell = owned;
    }

    pub fn cycleShell(self: *Config, allocator: std.mem.Allocator, delta: i32) !void {
        // Build list of available choices (empty = $SHELL, plus existing binaries).
        var available: [shell_choices.len][]const u8 = undefined;
        var count: usize = 0;
        for (shell_choices) |choice| {
            if (choice.len == 0) {
                available[count] = choice;
                count += 1;
            } else if (pathExecutable(choice)) {
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
        const home = std.c.getenv("HOME") orelse return cfg;
        const home_slice = std.mem.span(home);
        const path = std.fmt.allocPrint(allocator, "{s}/.config/orbit/config.toml", .{home_slice}) catch return cfg;
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

    /// Persist current settings to ~/.config/orbit/config.toml.
    pub fn save(self: *const Config, allocator: std.mem.Allocator, io: std.Io) !void {
        const home = std.c.getenv("HOME") orelse return error.NoHome;
        const home_slice = std.mem.span(home);
        const dir_path = try std.fmt.allocPrint(allocator, "{s}/.config/orbit", .{home_slice});
        defer allocator.free(dir_path);
        ensureDir(dir_path);

        const path = try std.fmt.allocPrint(allocator, "{s}/config.toml", .{dir_path});
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
        try appendFmt(&body, allocator, "padding_x = {d}\n", .{self.padding_x});
        try appendFmt(&body, allocator, "padding_y = {d}\n", .{self.padding_y});
        try appendFmt(&body, allocator, "cursor_style = \"{s}\"\n", .{self.cursor_style.name()});
        try appendFmt(&body, allocator, "cursor_blink = {s}\n", .{if (self.cursor_blink) "true" else "false"});
        if (self.shellPath()) |sh| {
            try appendFmt(&body, allocator, "shell = \"{s}\"\n", .{sh});
        } else {
            try body.appendSlice(allocator, "# shell = \"$SHELL\"  # e.g. \"/bin/bash\" or \"/bin/zsh\"\n");
        }

        const file = try std.Io.Dir.createFileAbsolute(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, body.items);
    }

    pub fn parseInto(cfg: *Config, allocator: std.mem.Allocator, data: []const u8) void {
        var section: enum { none, window, theme, terminal } = .none;
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
                    } else {
                        section = .none;
                    }
                }
                continue;
            }
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const key = std.mem.trim(u8, line[0..eq], " \t");
            var val = std.mem.trim(u8, line[eq + 1 ..], " \t");
            if (val.len >= 2 and ((val[0] == '"' and val[val.len - 1] == '"') or (val[0] == '\'' and val[val.len - 1] == '\''))) {
                val = val[1 .. val.len - 1];
            }

            switch (section) {
                .window => {
                    if (std.mem.eql(u8, key, "width")) cfg.window_width = parseI32(val) orelse cfg.window_width;
                    if (std.mem.eql(u8, key, "height")) cfg.window_height = parseI32(val) orelse cfg.window_height;
                    if (std.mem.eql(u8, key, "opacity")) cfg.opacity = parseF32(val) orelse cfg.opacity;
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
                    if (std.mem.eql(u8, key, "font_scale")) {
                        const scale = parseF32(val) orelse 2.0;
                        cfg.font_size = @min(28.0, @max(9.0, 14.0 * scale / 2.0));
                    }
                    if (std.mem.eql(u8, key, "padding_x")) {
                        cfg.padding_x = parseI32(val) orelse cfg.padding_x;
                        cfg.padding_x = @max(0, @min(48, cfg.padding_x));
                    }
                    if (std.mem.eql(u8, key, "padding_y")) {
                        cfg.padding_y = parseI32(val) orelse cfg.padding_y;
                        cfg.padding_y = @max(0, @min(48, cfg.padding_y));
                    }
                    if (std.mem.eql(u8, key, "shell")) {
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
                },
                .none => {},
            }
        }
        cfg.opacity = @min(1.0, @max(0.15, cfg.opacity));

        // Drop configured shell if the binary is missing (e.g. fish not installed).
        if (cfg.shell) |s| {
            if (s.len > 0 and !pathExecutable(s)) {
                if (cfg.shell_owned) |old| allocator.free(old);
                cfg.shell_owned = null;
                cfg.shell = null;
            }
        }
    }
};

fn pathExecutable(path: []const u8) bool {
    if (path.len == 0) return false;
    var buf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= buf.len) return false;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    return std.c.access(buf[0..path.len :0], 1) == 0; // X_OK
}

fn appendFmt(list: *std.ArrayList(u8), allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const slice = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(slice);
    try list.appendSlice(allocator, slice);
}

fn ensureDir(path: []const u8) void {
    var buf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= buf.len) return;
    var i: usize = 1;
    while (i <= path.len) : (i += 1) {
        if (i < path.len and path[i] != '/') continue;
        @memcpy(buf[0..i], path[0..i]);
        buf[i] = 0;
        _ = std.c.mkdir(buf[0..i :0], 0o755);
    }
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
