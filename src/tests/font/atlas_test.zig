//! Unit tests — GPU font atlas (TTF or bitmap fallback).

const std = @import("std");
const atlas_mod = @import("../../font/atlas.zig");

test "create produces non-empty atlas at 14px" {
    var atlas = try atlas_mod.Atlas.create(std.testing.allocator, 14);
    defer atlas.deinit();
    try std.testing.expect(atlas.cell_w >= 6);
    try std.testing.expect(atlas.cell_h >= 10);
    try std.testing.expectEqual(atlas.cell_w * atlas_mod.glyph_count, atlas.width);
    try std.testing.expectEqual(atlas.cell_h, atlas.height);
    try std.testing.expect(atlas.rgba.len == atlas.width * atlas.height * 4);
}

test "pixel size is clamped" {
    var tiny = try atlas_mod.Atlas.create(std.testing.allocator, 1);
    defer tiny.deinit();
    try std.testing.expect(tiny.cell_h >= 10);

    var huge = try atlas_mod.Atlas.create(std.testing.allocator, 200);
    defer huge.deinit();
    try std.testing.expect(huge.cell_h <= 80);
}

test "atlas has ink for letter M" {
    var atlas = try atlas_mod.Atlas.create(std.testing.allocator, 16);
    defer atlas.deinit();
    const slot: u32 = 'M' - atlas_mod.first_codepoint;
    var lit: bool = false;
    var y: u32 = 0;
    while (y < atlas.cell_h) : (y += 1) {
        var x: u32 = 0;
        while (x < atlas.cell_w) : (x += 1) {
            const px = (y * atlas.width + slot * atlas.cell_w + x) * 4;
            if (atlas.rgba[px + 3] > 0) lit = true;
        }
    }
    try std.testing.expect(lit);
}
