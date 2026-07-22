//! GPU font atlas — TrueType (SF Mono / Menlo via stb) with bitmap fallback.

const std = @import("std");
const builtin = @import("builtin");
const bitmap = @import("bitmap.zig");

pub const first_codepoint: u21 = 32;
pub const last_codepoint: u21 = 126;
pub const glyph_count: u32 = last_codepoint - first_codepoint + 1;

pub const Atlas = struct {
    rgba: []u8,
    width: u32,
    height: u32,
    cell_w: u32,
    cell_h: u32,
    allocator: std.mem.Allocator,
    source: enum { truetype, bitmap } = .bitmap,

    pub fn deinit(self: *Atlas) void {
        self.allocator.free(self.rgba);
        self.* = undefined;
    }

    pub fn create(allocator: std.mem.Allocator, pixel_size: u32) !Atlas {
        const px = @max(10, @min(64, pixel_size));
        if (builtin.os.tag == .macos or builtin.os.tag == .linux or builtin.os.tag == .windows) {
            const ttf = @import("ttf_atlas.zig");
            if (ttf.build(allocator, px)) |atlas| return atlas else |_| {}
        }
        return createBitmapScaled(allocator, px);
    }

    fn createBitmapScaled(allocator: std.mem.Allocator, pixel_size: u32) !Atlas {
        const scale: u32 = @max(1, (pixel_size + bitmap.glyph_height / 2) / bitmap.glyph_height);
        const cell_w = bitmap.glyph_width * scale;
        const cell_h = bitmap.glyph_height * scale;
        const width = cell_w * glyph_count;
        const height = cell_h;
        const rgba = try allocator.alloc(u8, width * height * 4);
        errdefer allocator.free(rgba);
        @memset(rgba, 0);

        var cp: u21 = first_codepoint;
        while (cp <= last_codepoint) : (cp += 1) {
            const g = bitmap.glyph(cp) orelse continue;
            const slot: u32 = cp - first_codepoint;
            var row: u32 = 0;
            while (row < bitmap.glyph_height) : (row += 1) {
                const bits = g[row];
                var col: u32 = 0;
                while (col < bitmap.glyph_width) : (col += 1) {
                    const on = (bits & (@as(u8, 0x80) >> @intCast(col))) != 0;
                    if (!on) continue;
                    var sy: u32 = 0;
                    while (sy < scale) : (sy += 1) {
                        var sx: u32 = 0;
                        while (sx < scale) : (sx += 1) {
                            const x = slot * cell_w + col * scale + sx;
                            const y = row * scale + sy;
                            const p = (y * width + x) * 4;
                            rgba[p + 0] = 235;
                            rgba[p + 1] = 235;
                            rgba[p + 2] = 235;
                            rgba[p + 3] = 255;
                        }
                    }
                }
            }
        }

        return .{
            .rgba = rgba,
            .width = width,
            .height = height,
            .cell_w = cell_w,
            .cell_h = cell_h,
            .allocator = allocator,
            .source = .bitmap,
        };
    }
};
