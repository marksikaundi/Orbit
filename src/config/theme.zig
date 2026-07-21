//! Built-in color themes.

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

pub const orbit_dark: Theme = .{
    .name = "orbit-dark",
    // Ghostty-adjacent dark neutrals
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

pub fn byName(name: []const u8) Theme {
    if (std.mem.eql(u8, name, "orbit-light") or std.mem.eql(u8, name, "light")) return orbit_light;
    if (std.mem.eql(u8, name, "nord")) return nord;
    return orbit_dark;
}

const std = @import("std");
