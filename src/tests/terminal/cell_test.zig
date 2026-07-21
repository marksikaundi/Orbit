//! Unit tests — terminal cell colors & attributes.

const std = @import("std");
const cell = @import("../../terminal/cell.zig");
const Color = cell.Color;
const Cell = cell.Cell;
const Attrs = cell.Attrs;
const ansi256 = cell.ansi256;

test "Color.rgb and eql" {
    const a = Color.rgb(10, 20, 30);
    const b = Color.rgb(10, 20, 30);
    const c = Color.rgb(11, 20, 30);
    try std.testing.expect(a.eql(b));
    try std.testing.expect(!a.eql(c));
}

test "Color.fromIndex classic and bright" {
    const red = Color.fromIndex(1);
    try std.testing.expectEqual(@as(u8, 205), red.r);
    const bright = Color.fromIndex(9);
    try std.testing.expectEqual(@as(u8, 241), bright.r);
}

test "ansi256 classic cube and gray" {
    try std.testing.expectEqual(@as(u8, 205), ansi256(1).r);
    // cube index 16 = 0,0,0
    try std.testing.expectEqual(@as(u8, 0), ansi256(16).r);
    // gray 232
    try std.testing.expectEqual(@as(u8, 8), ansi256(232).r);
    try std.testing.expectEqual(@as(u8, 8), ansi256(232).g);
    // last gray 255
    try std.testing.expectEqual(@as(u8, 238), ansi256(255).r);
}

test "Cell.blank and set dirty tracking" {
    var c = Cell.blank();
    try std.testing.expectEqual(@as(u21, ' '), c.codepoint);
    c.dirty = false;

    c.set('A', Color.rgb(255, 255, 255), Color.rgb(0, 0, 0), Attrs.none());
    try std.testing.expect(c.dirty);
    try std.testing.expectEqual(@as(u21, 'A'), c.codepoint);

    c.dirty = false;
    c.set('A', Color.rgb(255, 255, 255), Color.rgb(0, 0, 0), Attrs.none());
    try std.testing.expect(!c.dirty); // unchanged
}

test "Cell.blankWith theme colors" {
    const fg = Color.rgb(1, 2, 3);
    const bg = Color.rgb(4, 5, 6);
    const c = Cell.blankWith(fg, bg);
    try std.testing.expect(c.fg.eql(fg));
    try std.testing.expect(c.bg.eql(bg));
}
