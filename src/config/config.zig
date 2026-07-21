//! Minimal TOML subset loader for Orbit config (~/.config/orbit/config.toml).

const std = @import("std");
const theme_mod = @import("theme.zig");

pub const Config = struct {
    window_width: i32 = 900,
    window_height: i32 = 560,
    opacity: f32 = 1.0,
    theme_name: []const u8 = "orbit-dark",
    scrollback: usize = 2000,
    /// Font size in points (Ghostty-style). Scaled for Retina automatically.
    font_size: f32 = 14.0,
    /// Interior padding in logical pixels (Ghostty window-padding).
    padding_x: i32 = 10,
    padding_y: i32 = 6,
    /// Owned theme name buffer when loaded from file.
    theme_name_owned: ?[]u8 = null,

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.theme_name_owned) |t| allocator.free(t);
        self.theme_name_owned = null;
    }

    pub fn theme(self: *const Config) theme_mod.Theme {
        return theme_mod.byName(self.theme_name);
    }

    pub fn setThemeName(self: *Config, allocator: std.mem.Allocator, name: []const u8) !void {
        if (self.theme_name_owned) |old| allocator.free(old);
        const owned = try allocator.dupe(u8, name);
        self.theme_name_owned = owned;
        self.theme_name = owned;
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
            // Strip quotes
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
                },
                .terminal => {
                    if (std.mem.eql(u8, key, "scrollback")) {
                        cfg.scrollback = @intCast(parseI32(val) orelse @as(i32, @intCast(cfg.scrollback)));
                    }
                    if (std.mem.eql(u8, key, "font_size")) {
                        cfg.font_size = parseF32(val) orelse cfg.font_size;
                        cfg.font_size = @min(28.0, @max(9.0, cfg.font_size));
                    }
                    // Back-compat: font_scale 2.0 ≈ 14pt
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
                },
                .none => {},
            }
        }
        cfg.opacity = @min(1.0, @max(0.15, cfg.opacity));
    }
};

fn parseI32(s: []const u8) ?i32 {
    return std.fmt.parseInt(i32, s, 10) catch null;
}

fn parseF32(s: []const u8) ?f32 {
    return std.fmt.parseFloat(f32, s) catch null;
}
