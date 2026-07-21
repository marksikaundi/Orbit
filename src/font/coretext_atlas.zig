//! CoreText glyph atlas builder (macOS) — SF Mono / Menlo like Ghostty.

const std = @import("std");
const atlas_root = @import("atlas.zig");

const c = @cImport({
    @cInclude("CoreText/CoreText.h");
    @cInclude("CoreGraphics/CoreGraphics.h");
});

pub fn build(allocator: std.mem.Allocator, pixel_size: u32) !atlas_root.Atlas {
    const size_f: f64 = @floatFromInt(pixel_size);

    // Prefer SF Mono (Ghostty-adjacent on macOS), then Menlo.
    const names = [_][:0]const u8{ "SF Mono", "Menlo", "Andale Mono", "Courier" };
    var font: c.CTFontRef = null;
    for (names) |name| {
        const cf = c.CFStringCreateWithCString(null, name.ptr, c.kCFStringEncodingUTF8);
        defer c.CFRelease(cf);
        font = c.CTFontCreateWithName(cf, size_f, null);
        if (font != null) break;
    }
    if (font == null) return error.FontNotFound;
    defer c.CFRelease(font);

    const ascent = c.CTFontGetAscent(font);
    const descent = c.CTFontGetDescent(font);
    const leading = c.CTFontGetLeading(font);
    const advance = c.CTFontGetAdvancesForGlyphs(font, c.kCTFontOrientationDefault, &[_]c.CGGlyph{0}, null, 0);
    _ = advance;

    // Measure 'M' for mono cell width.
    var cell_w: u32 = pixel_size;
    {
        const m_str = c.CFStringCreateWithCString(null, "M", c.kCFStringEncodingUTF8);
        defer c.CFRelease(m_str);
        var glyphs: [1]c.CGGlyph = undefined;
        var advances: [1]c.CGSize = undefined;
        if (c.CTFontGetGlyphsForCharacters(font, &[_]u16{'M'}, &glyphs, 1)) {
            _ = c.CTFontGetAdvancesForGlyphs(font, c.kCTFontOrientationHorizontal, &glyphs, &advances, 1);
            cell_w = @max(1, @as(u32, @intFromFloat(@ceil(advances[0].width))));
        }
    }

    const line_h = ascent + descent + leading;
    var cell_h: u32 = @max(pixel_size + 2, @as(u32, @intFromFloat(@ceil(line_h))));
    // Tight Ghostty-like line height: ascent+descent with small pad.
    cell_h = @max(pixel_size + 2, @as(u32, @intFromFloat(@ceil(ascent + descent))) + 2);

    const width = cell_w * atlas_root.glyph_count;
    const height = cell_h;
    const rgba = try allocator.alloc(u8, width * height * 4);
    errdefer allocator.free(rgba);
    @memset(rgba, 0);

    // Per-glyph grayscale buffer (cell-sized).
    const gray = try allocator.alloc(u8, cell_w * cell_h);
    defer allocator.free(gray);

    var cp: u21 = atlas_root.first_codepoint;
    while (cp <= atlas_root.last_codepoint) : (cp += 1) {
        @memset(gray, 0);

        var utf16: [1]u16 = .{@intCast(cp)};
        var glyphs: [1]c.CGGlyph = undefined;
        if (!c.CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, 1)) continue;

        var advances: [1]c.CGSize = undefined;
        _ = c.CTFontGetAdvancesForGlyphs(font, c.kCTFontOrientationHorizontal, &glyphs, &advances, 1);

        var bounds: c.CGRect = undefined;
        _ = c.CTFontGetBoundingRectsForGlyphs(font, c.kCTFontOrientationHorizontal, &glyphs, &bounds, 1);

        // Draw into a temporary CG bitmap (Gray).
        const bytes_per_row = cell_w;
        const color_space = c.CGColorSpaceCreateDeviceGray();
        defer c.CGColorSpaceRelease(color_space);

        const ctx = c.CGBitmapContextCreate(
            gray.ptr,
            cell_w,
            cell_h,
            8,
            bytes_per_row,
            color_space,
            c.kCGImageAlphaNone,
        );
        if (ctx == null) continue;
        defer c.CGContextRelease(ctx);

        // Flip to top-left origin for our atlas.
        c.CGContextSetShouldAntialias(ctx, true);
        c.CGContextSetAllowsAntialiasing(ctx, true);
        c.CGContextSetShouldSmoothFonts(ctx, true);
        c.CGContextSetGrayFillColor(ctx, 1.0, 1.0);
        c.CGContextTranslateCTM(ctx, 0, @floatFromInt(cell_h));
        c.CGContextScaleCTM(ctx, 1.0, -1.0);

        // Baseline from top: ascent pixels down.
        const baseline_y = ascent;
        const pos = c.CGPointMake(0, baseline_y);
        c.CTFontDrawGlyphs(font, &glyphs, &pos, 1, ctx);

        const slot: u32 = cp - atlas_root.first_codepoint;
        const ox = slot * cell_w;
        var y: u32 = 0;
        while (y < cell_h) : (y += 1) {
            var x: u32 = 0;
            while (x < cell_w) : (x += 1) {
                const g = gray[y * cell_w + x];
                if (g == 0) continue;
                const p = (y * width + ox + x) * 4;
                rgba[p + 0] = 255;
                rgba[p + 1] = 255;
                rgba[p + 2] = 255;
                rgba[p + 3] = g;
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
        .source = .coretext,
    };
}
