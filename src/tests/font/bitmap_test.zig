//! Unit tests — embedded bitmap font.

const std = @import("std");
const bitmap = @import("../../font/bitmap.zig");

test "glyph range ASCII printable" {
    try std.testing.expect(bitmap.glyph(' ') != null);
    try std.testing.expect(bitmap.glyph('A') != null);
    try std.testing.expect(bitmap.glyph('~') != null);
    try std.testing.expect(bitmap.glyph(31) == null);
    try std.testing.expect(bitmap.glyph(127) == null);
}

test "atlas dimensions" {
    try std.testing.expectEqual(bitmap.glyph_width * (bitmap.last_codepoint - bitmap.first_codepoint + 1), bitmap.atlasWidth());
    try std.testing.expectEqual(bitmap.glyph_height, bitmap.atlasHeight());
}

test "buildAtlas paints letter A and leaves space empty" {
    const w = bitmap.atlasWidth();
    const h = bitmap.atlasHeight();
    const buf = try std.testing.allocator.alloc(u8, w * h * 4);
    defer std.testing.allocator.free(buf);
    bitmap.buildAtlas(buf);

    const a_idx: usize = 'A' - bitmap.first_codepoint;
    var a_lit: bool = false;
    var row: u32 = 0;
    while (row < h) : (row += 1) {
        var col: u32 = 0;
        while (col < bitmap.glyph_width) : (col += 1) {
            const x = a_idx * bitmap.glyph_width + col;
            const p = (row * w + x) * 4;
            if (buf[p + 3] != 0) a_lit = true;
        }
    }
    try std.testing.expect(a_lit);

    // space glyph (index 0) should be empty
    var space_lit: bool = false;
    row = 0;
    while (row < h) : (row += 1) {
        var col: u32 = 0;
        while (col < bitmap.glyph_width) : (col += 1) {
            const p = (row * w + col) * 4;
            if (buf[p + 3] != 0) space_lit = true;
        }
    }
    try std.testing.expect(!space_lit);
}
