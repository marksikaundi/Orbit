//! Unit tests — plugin type helpers.

const std = @import("std");
const types = @import("../../plugins/types.zig");
const Color = @import("../../terminal/cell.zig").Color;

test "parseHexColor accepts hash and quotes" {
    const a = types.parseHexColor("#ff00aa") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u8, 0xff), a.r);
    try std.testing.expectEqual(@as(u8, 0x00), a.g);
    try std.testing.expectEqual(@as(u8, 0xaa), a.b);

    const b = types.parseHexColor("\"#112233\"") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u8, 0x11), b.r);
}

test "parseHexColor rejects invalid" {
    try std.testing.expect(types.parseHexColor("ff00") == null);
    try std.testing.expect(types.parseHexColor("not-a-color") == null);
    try std.testing.expect(types.parseHexColor("#gg0000") == null);
}

test "themeFromColors sets name and fg slot" {
    const fg = Color.rgb(200, 200, 200);
    const bg = Color.rgb(10, 10, 10);
    const t = types.themeFromColors("custom", fg, bg, fg, bg);
    try std.testing.expectEqualStrings("custom", t.name);
    try std.testing.expect(t.foreground.eql(fg));
    try std.testing.expect(t.background.eql(bg));
    try std.testing.expect(t.ansi[7].eql(fg));
}
