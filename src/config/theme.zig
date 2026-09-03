//! Built-in color themes — pick via Settings or config.toml [theme] name.

const std = @import("std");
const Color = @import("../terminal/cell.zig").Color;

pub const Theme = struct {
    name: []const u8,
    foreground: Color,
    background: Color,
    cursor: Color,
    selection_bg: Color,
    ansi: [16]Color,

    pub fn applyAnsiOverride(self: *const Theme, index: u8) Color {
        if (index < 16) return self.ansi[index];
        return Color.fromIndex(index);
    }
};

/// Names users can cycle in Settings / palette (order matters).
pub const builtin_names = [_][]const u8{
    "orbit-dark",
    "orbit-light",
    "nord",
    "dracula",
    "gruvbox-dark",
    "solarized-dark",
    "catppuccin-mocha",
    "tokyo-night",
};

pub const orbit_dark: Theme = .{
    .name = "orbit-dark",
    .foreground = Color.rgb(218, 224, 232),
    .background = Color.rgb(17, 18, 22),
    .cursor = Color.rgb(218, 224, 232),
    .selection_bg = Color.rgb(52, 64, 84),
    .ansi = .{
        Color.rgb(28, 30, 36),
        Color.rgb(232, 98, 106),
        Color.rgb(98, 186, 128),
        Color.rgb(224, 188, 96),
        Color.rgb(96, 156, 230),
        Color.rgb(188, 130, 210),
        Color.rgb(86, 186, 200),
        Color.rgb(218, 224, 232),
        Color.rgb(90, 96, 108),
        Color.rgb(242, 120, 128),
        Color.rgb(120, 210, 150),
        Color.rgb(240, 210, 120),
        Color.rgb(120, 180, 245),
        Color.rgb(210, 150, 230),
        Color.rgb(110, 210, 220),
        Color.rgb(255, 255, 255),
    },
};

pub const orbit_light: Theme = .{
    .name = "orbit-light",
    .foreground = Color.rgb(30, 34, 40),
    .background = Color.rgb(250, 250, 252),
    .cursor = Color.rgb(40, 100, 200),
    .selection_bg = Color.rgb(180, 210, 240),
    .ansi = .{
        Color.rgb(0, 0, 0),
        Color.rgb(185, 30, 30),
        Color.rgb(20, 140, 80),
        Color.rgb(160, 120, 0),
        Color.rgb(30, 90, 180),
        Color.rgb(150, 40, 150),
        Color.rgb(20, 130, 160),
        Color.rgb(180, 180, 180),
        Color.rgb(100, 100, 100),
        Color.rgb(220, 50, 50),
        Color.rgb(30, 180, 100),
        Color.rgb(200, 160, 0),
        Color.rgb(50, 120, 220),
        Color.rgb(190, 70, 190),
        Color.rgb(30, 160, 190),
        Color.rgb(30, 34, 40),
    },
};

pub const nord: Theme = .{
    .name = "nord",
    .foreground = Color.rgb(216, 222, 233),
    .background = Color.rgb(46, 52, 64),
    .cursor = Color.rgb(136, 192, 208),
    .selection_bg = Color.rgb(67, 76, 94),
    .ansi = .{
        Color.rgb(59, 66, 82),
        Color.rgb(191, 97, 106),
        Color.rgb(163, 190, 140),
        Color.rgb(235, 203, 139),
        Color.rgb(129, 161, 193),
        Color.rgb(180, 142, 173),
        Color.rgb(136, 192, 208),
        Color.rgb(229, 233, 240),
        Color.rgb(76, 86, 106),
        Color.rgb(191, 97, 106),
        Color.rgb(163, 190, 140),
        Color.rgb(235, 203, 139),
        Color.rgb(129, 161, 193),
        Color.rgb(180, 142, 173),
        Color.rgb(136, 192, 208),
        Color.rgb(236, 239, 244),
    },
};

pub const dracula: Theme = .{
    .name = "dracula",
    .foreground = Color.rgb(248, 248, 242),
    .background = Color.rgb(40, 42, 54),
    .cursor = Color.rgb(248, 248, 242),
    .selection_bg = Color.rgb(68, 71, 90),
    .ansi = .{
        Color.rgb(33, 34, 44),
        Color.rgb(255, 85, 85),
        Color.rgb(80, 250, 123),
        Color.rgb(241, 250, 140),
        Color.rgb(139, 233, 253),
        Color.rgb(255, 121, 198),
        Color.rgb(139, 233, 253),
        Color.rgb(248, 248, 242),
        Color.rgb(98, 114, 164),
        Color.rgb(255, 110, 110),
        Color.rgb(105, 255, 145),
        Color.rgb(255, 255, 165),
        Color.rgb(160, 240, 255),
        Color.rgb(255, 146, 208),
        Color.rgb(160, 240, 255),
        Color.rgb(255, 255, 255),
    },
};

pub const gruvbox_dark: Theme = .{
    .name = "gruvbox-dark",
    .foreground = Color.rgb(235, 219, 178),
    .background = Color.rgb(40, 40, 40),
    .cursor = Color.rgb(235, 219, 178),
    .selection_bg = Color.rgb(80, 73, 69),
    .ansi = .{
        Color.rgb(40, 40, 40),
        Color.rgb(204, 36, 29),
        Color.rgb(152, 151, 26),
        Color.rgb(215, 153, 33),
        Color.rgb(69, 133, 136),
        Color.rgb(177, 98, 134),
        Color.rgb(104, 157, 106),
        Color.rgb(168, 153, 132),
        Color.rgb(146, 131, 116),
        Color.rgb(251, 73, 52),
        Color.rgb(184, 187, 38),
        Color.rgb(250, 189, 47),
        Color.rgb(131, 165, 152),
        Color.rgb(211, 134, 155),
        Color.rgb(142, 192, 124),
        Color.rgb(235, 219, 178),
    },
};

pub const solarized_dark: Theme = .{
    .name = "solarized-dark",
    .foreground = Color.rgb(131, 148, 150),
    .background = Color.rgb(0, 43, 54),
    .cursor = Color.rgb(131, 148, 150),
    .selection_bg = Color.rgb(7, 54, 66),
    .ansi = .{
        Color.rgb(7, 54, 66),
        Color.rgb(220, 50, 47),
        Color.rgb(133, 153, 0),
        Color.rgb(181, 137, 0),
        Color.rgb(38, 139, 210),
        Color.rgb(211, 54, 130),
        Color.rgb(42, 161, 152),
        Color.rgb(238, 232, 213),
        Color.rgb(0, 43, 54),
        Color.rgb(203, 75, 22),
        Color.rgb(88, 110, 117),
        Color.rgb(101, 123, 131),
        Color.rgb(131, 148, 150),
        Color.rgb(108, 113, 196),
        Color.rgb(147, 161, 161),
        Color.rgb(253, 246, 227),
    },
};

pub const tokyo_night: Theme = .{
    .name = "tokyo-night",
    .foreground = Color.rgb(169, 177, 214),
    .background = Color.rgb(26, 27, 38),
    .cursor = Color.rgb(122, 162, 247),
    .selection_bg = Color.rgb(51, 52, 76),
    .ansi = .{
        Color.rgb(21, 22, 30),
        Color.rgb(247, 118, 142),
        Color.rgb(158, 206, 106),
        Color.rgb(224, 175, 104),
        Color.rgb(122, 162, 247),
        Color.rgb(187, 154, 247),
        Color.rgb(125, 207, 255),
        Color.rgb(169, 177, 214),
        Color.rgb(86, 95, 137),
        Color.rgb(247, 118, 142),
        Color.rgb(158, 206, 106),
        Color.rgb(224, 175, 104),
        Color.rgb(122, 162, 247),
        Color.rgb(187, 154, 247),
        Color.rgb(125, 207, 255),
        Color.rgb(192, 202, 245),
    },
};

pub const catppuccin_mocha: Theme = .{
    .name = "catppuccin-mocha",
    .foreground = Color.rgb(205, 214, 244),
    .background = Color.rgb(30, 30, 46),
    .cursor = Color.rgb(245, 224, 220),
    .selection_bg = Color.rgb(69, 71, 90),
    .ansi = .{
        Color.rgb(69, 71, 90),
        Color.rgb(243, 139, 168),
        Color.rgb(166, 227, 161),
        Color.rgb(249, 226, 175),
        Color.rgb(137, 180, 250),
        Color.rgb(203, 166, 247),
        Color.rgb(148, 226, 213),
        Color.rgb(186, 194, 222),
        Color.rgb(88, 91, 112),
        Color.rgb(243, 139, 168),
        Color.rgb(166, 227, 161),
        Color.rgb(249, 226, 175),
        Color.rgb(137, 180, 250),
        Color.rgb(203, 166, 247),
        Color.rgb(148, 226, 213),
        Color.rgb(166, 173, 200),
    },
};

pub fn byName(name: []const u8) Theme {
    if (std.mem.eql(u8, name, "orbit-light") or std.mem.eql(u8, name, "light")) return orbit_light;
    if (std.mem.eql(u8, name, "nord")) return nord;
    if (std.mem.eql(u8, name, "dracula")) return dracula;
    if (std.mem.eql(u8, name, "gruvbox-dark") or std.mem.eql(u8, name, "gruvbox")) return gruvbox_dark;
    if (std.mem.eql(u8, name, "solarized-dark") or std.mem.eql(u8, name, "solarized")) return solarized_dark;
    if (std.mem.eql(u8, name, "tokyo-night") or std.mem.eql(u8, name, "tokyonight") or std.mem.eql(u8, name, "tokyo")) return tokyo_night;
    if (std.mem.eql(u8, name, "catppuccin-mocha") or std.mem.eql(u8, name, "catppuccin") or std.mem.eql(u8, name, "mocha")) return catppuccin_mocha;
    if (std.mem.eql(u8, name, "orbit-dark") or std.mem.eql(u8, name, "dark")) return orbit_dark;
    return orbit_dark;
}

pub fn indexOfName(name: []const u8) usize {
    for (builtin_names, 0..) |n, i| {
        if (std.mem.eql(u8, n, name)) return i;
        // aliases
        if (std.mem.eql(u8, name, "light") and std.mem.eql(u8, n, "orbit-light")) return i;
        if (std.mem.eql(u8, name, "gruvbox") and std.mem.eql(u8, n, "gruvbox-dark")) return i;
        if (std.mem.eql(u8, name, "solarized") and std.mem.eql(u8, n, "solarized-dark")) return i;
        if (std.mem.eql(u8, name, "dark") and std.mem.eql(u8, n, "orbit-dark")) return i;
        if (std.mem.eql(u8, name, "tokyo") and std.mem.eql(u8, n, "tokyo-night")) return i;
        if (std.mem.eql(u8, name, "tokyonight") and std.mem.eql(u8, n, "tokyo-night")) return i;
        if (std.mem.eql(u8, name, "catppuccin") and std.mem.eql(u8, n, "catppuccin-mocha")) return i;
        if (std.mem.eql(u8, name, "mocha") and std.mem.eql(u8, n, "catppuccin-mocha")) return i;
    }
    return 0;
}

pub fn nextName(current: []const u8, delta: i32) []const u8 {
    const n: i32 = @intCast(builtin_names.len);
    var idx: i32 = @intCast(indexOfName(current));
    idx = @mod(idx + delta, n);
    if (idx < 0) idx += n;
    return builtin_names[@intCast(idx)];
}

/// Independent text (foreground) colors — cycle in Appearance Settings.
/// `"theme"` keeps the theme’s default foreground.
pub const FgPreset = struct {
    id: []const u8,
    label: []const u8,
    /// `null` = use the active theme’s foreground.
    color: ?Color,
};

pub const fg_presets = [_]FgPreset{
    .{ .id = "theme", .label = "theme", .color = null },
    .{ .id = "soft-white", .label = "soft white", .color = Color.rgb(232, 236, 242) },
    .{ .id = "bright", .label = "bright", .color = Color.rgb(255, 255, 255) },
    .{ .id = "cool-gray", .label = "cool gray", .color = Color.rgb(176, 188, 200) },
    .{ .id = "warm-gray", .label = "warm gray", .color = Color.rgb(200, 188, 170) },
    .{ .id = "mint", .label = "mint", .color = Color.rgb(160, 220, 190) },
    .{ .id = "green", .label = "green", .color = Color.rgb(120, 200, 140) },
    .{ .id = "amber", .label = "amber", .color = Color.rgb(240, 200, 120) },
    .{ .id = "sky", .label = "sky", .color = Color.rgb(140, 190, 230) },
    .{ .id = "lavender", .label = "lavender", .color = Color.rgb(200, 170, 230) },
    .{ .id = "rose", .label = "rose", .color = Color.rgb(230, 160, 180) },
};

pub fn indexOfFgPreset(id: []const u8) usize {
    for (fg_presets, 0..) |p, i| {
        if (std.mem.eql(u8, p.id, id)) return i;
    }
    return 0;
}

pub fn fgPresetById(id: []const u8) FgPreset {
    return fg_presets[indexOfFgPreset(id)];
}

pub fn nextFgPresetId(current: []const u8, delta: i32) []const u8 {
    const n: i32 = @intCast(fg_presets.len);
    var idx: i32 = @intCast(indexOfFgPreset(current));
    idx = @mod(idx + delta, n);
    if (idx < 0) idx += n;
    return fg_presets[@intCast(idx)].id;
}

/// Apply a text-color override onto a theme copy (cursor follows text for consistency).
pub fn withFgOverride(base: Theme, fg_id: []const u8) Theme {
    var t = base;
    const preset = fgPresetById(fg_id);
    if (preset.color) |c| {
        t.foreground = c;
        t.cursor = c;
    }
    return t;
}
