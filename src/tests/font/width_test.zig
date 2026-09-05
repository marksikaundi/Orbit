const std = @import("std");
const width = @import("../../font/width.zig");

test "ASCII is narrow" {
    try std.testing.expectEqual(@as(u8, 1), width.columns('A'));
    try std.testing.expectEqual(@as(u8, 1), width.columns(' '));
}

test "control is empty" {
    try std.testing.expectEqual(@as(u8, 0), width.columns(0x07));
}

test "CJK is wide" {
    try std.testing.expectEqual(@as(u8, 2), width.columns(0x4E2D)); // 中
    try std.testing.expect(width.isWide(0x3042)); // あ
}

test "box drawing is narrow" {
    try std.testing.expectEqual(@as(u8, 1), width.columns(0x2500));
    try std.testing.expect(width.isBoxDrawing(0x2502));
}
