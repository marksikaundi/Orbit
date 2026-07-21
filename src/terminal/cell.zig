//! Terminal cell: glyph + colors + SGR attributes.

pub const Color = packed struct(u32) {
    r: u8 = 200,
    g: u8 = 200,
    b: u8 = 200,
    a: u8 = 255,

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = 255 };
    }

    pub fn fromIndex(index: u8) Color {
        return ansi256(index);
    }

    pub fn eql(self: Color, other: Color) bool {
        return @as(u32, @bitCast(self)) == @as(u32, @bitCast(other));
    }
};

pub const Attrs = packed struct(u8) {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    blink: bool = false,
    reverse: bool = false,
    hidden: bool = false,
    strikethrough: bool = false,

    pub fn none() Attrs {
        return .{};
    }
};

pub const Cell = struct {
    codepoint: u21 = ' ',
    fg: Color = Color.rgb(230, 235, 240),
    bg: Color = Color.rgb(18, 20, 26),
    attrs: Attrs = .{},
    dirty: bool = true,

    pub fn blank() Cell {
        return .{};
    }

    pub fn blankWith(fg: Color, bg: Color) Cell {
        return .{ .fg = fg, .bg = bg };
    }

    pub fn set(self: *Cell, codepoint: u21, fg: Color, bg: Color, attrs: Attrs) void {
        if (self.codepoint != codepoint or !self.fg.eql(fg) or !self.bg.eql(bg) or @as(u8, @bitCast(self.attrs)) != @as(u8, @bitCast(attrs))) {
            self.codepoint = codepoint;
            self.fg = fg;
            self.bg = bg;
            self.attrs = attrs;
            self.dirty = true;
        }
    }
};

/// Standard ANSI / xterm 256-color palette.
pub fn ansi256(index: u8) Color {
    // 0–15: classic ANSI
    const classic = [_]Color{
        Color.rgb(0, 0, 0),
        Color.rgb(205, 49, 49),
        Color.rgb(13, 188, 121),
        Color.rgb(229, 229, 16),
        Color.rgb(36, 114, 200),
        Color.rgb(188, 63, 188),
        Color.rgb(17, 168, 205),
        Color.rgb(229, 229, 229),
        Color.rgb(102, 102, 102),
        Color.rgb(241, 76, 76),
        Color.rgb(35, 209, 139),
        Color.rgb(245, 245, 67),
        Color.rgb(59, 142, 234),
        Color.rgb(214, 112, 214),
        Color.rgb(41, 184, 219),
        Color.rgb(255, 255, 255),
    };
    if (index < 16) return classic[index];

    // 16–231: 6×6×6 color cube
    if (index < 232) {
        const i = index - 16;
        const r6 = i / 36;
        const g6 = (i % 36) / 6;
        const b6 = i % 6;
        const levels = [_]u8{ 0, 95, 135, 175, 215, 255 };
        return Color.rgb(levels[r6], levels[g6], levels[b6]);
    }

    // 232–255: grayscale ramp
    const gray: u8 = @intCast(8 + (index - 232) * 10);
    return Color.rgb(gray, gray, gray);
}
