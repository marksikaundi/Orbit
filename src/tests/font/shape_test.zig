const std = @import("std");
const shape = @import("../../font/shape.zig");

test "matches longest ligature first" {
    const seq = [_]u21{ '=', '=', '=' };
    const hit = shape.match(&seq) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 3), hit.len);
}

test "matches two-char arrows" {
    const arrows = [_][]const u21{
        &[_]u21{ '=', '>' },
        &[_]u21{ '-', '>' },
        &[_]u21{ '!', '=' },
    };
    for (arrows) |a| {
        const hit = shape.match(a) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(@as(usize, 2), hit.len);
    }
}

test "no ligature for a single glyph" {
    try std.testing.expect(shape.match(&[_]u21{'='}) == null);
}
