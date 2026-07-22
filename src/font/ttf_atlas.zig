//! stb_truetype atlas builder — loads SF Mono / Menlo from disk (Ghostty-like AA).

const std = @import("std");
const atlas_root = @import("atlas.zig");

const c = @cImport({
    @cInclude("stb_truetype.h");
});

const font_paths = [_][:0]const u8{
    "/System/Library/Fonts/SFNSMono.ttf",
    "/System/Library/Fonts/Menlo.ttc",
    "/System/Library/Fonts/Supplemental/Andale Mono.ttf",
    "/Library/Fonts/JetBrainsMono-Regular.ttf",
};

pub fn build(allocator: std.mem.Allocator, pixel_size: u32) !atlas_root.Atlas {
    var font_data: ?[]u8 = null;
    for (font_paths) |path| {
        font_data = readAbsolute(allocator, path) catch continue;
        break;
    }
    const data = font_data orelse return error.FontNotFound;
    defer allocator.free(data);

    var info: c.stbtt_fontinfo = undefined;
    if (c.stbtt_InitFont(&info, data.ptr, c.stbtt_GetFontOffsetForIndex(data.ptr, 0)) == 0) {
        return error.FontInitFailed;
    }

    const scale = c.stbtt_ScaleForPixelHeight(&info, @floatFromInt(pixel_size));
    var ascent: c_int = 0;
    var descent: c_int = 0;
    var line_gap: c_int = 0;
    c.stbtt_GetFontVMetrics(&info, &ascent, &descent, &line_gap);
    const baseline: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(ascent)) * scale));

    var advance: c_int = 0;
    var lsb: c_int = 0;
    c.stbtt_GetCodepointHMetrics(&info, 'M', &advance, &lsb);
    const cell_w: u32 = @max(1, @as(u32, @intFromFloat(@ceil(@as(f32, @floatFromInt(advance)) * scale))));
    const cell_h: u32 = @max(
        pixel_size + 2,
        @as(u32, @intFromFloat(@ceil(@as(f32, @floatFromInt(ascent - descent)) * scale))) + 2,
    );

    const width = cell_w * atlas_root.glyph_count;
    const height = cell_h;
    const rgba = try allocator.alloc(u8, width * height * 4);
    errdefer allocator.free(rgba);
    @memset(rgba, 0);

    var cp: u21 = atlas_root.first_codepoint;
    while (cp <= atlas_root.last_codepoint) : (cp += 1) {
        var x0: c_int = 0;
        var y0: c_int = 0;
        var x1: c_int = 0;
        var y1: c_int = 0;
        c.stbtt_GetCodepointBitmapBox(&info, @intCast(cp), scale, scale, &x0, &y0, &x1, &y1);

        var gw: c_int = 0;
        var gh: c_int = 0;
        const bmp = c.stbtt_GetCodepointBitmap(&info, scale, scale, @intCast(cp), &gw, &gh, null, null);
        if (bmp == null or gw <= 0 or gh <= 0) continue;
        defer c.stbtt_FreeBitmap(bmp, null);

        const slot: u32 = cp - atlas_root.first_codepoint;
        const ox: i32 = @intCast(slot * cell_w);
        const dest_x = ox + x0;
        const dest_y = baseline + y0;

        var row: c_int = 0;
        while (row < gh) : (row += 1) {
            const dy = dest_y + row;
            if (dy < 0 or dy >= @as(i32, @intCast(cell_h))) continue;
            var col: c_int = 0;
            while (col < gw) : (col += 1) {
                const dx = dest_x + col;
                if (dx < ox or dx >= ox + @as(i32, @intCast(cell_w))) continue;
                const src = bmp[@as(usize, @intCast(row * gw + col))];
                if (src == 0) continue;
                const p = (@as(usize, @intCast(dy)) * width + @as(usize, @intCast(dx))) * 4;
                rgba[p + 0] = 255;
                rgba[p + 1] = 255;
                rgba[p + 2] = 255;
                rgba[p + 3] = src;
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
        .source = .truetype,
    };
}

fn readAbsolute(allocator: std.mem.Allocator, path: [:0]const u8) ![]u8 {
    const fd = std.c.open(path.ptr, @bitCast(@as(c_uint, 0))); // O_RDONLY
    if (fd < 0) return error.OpenFailed;
    defer _ = std.c.close(fd);

    // Avoid std.c.fstat — it is void on Linux in Zig 0.16 (use chunked read instead).
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    var chunk: [16 * 1024]u8 = undefined;
    while (true) {
        const n = std.c.read(fd, &chunk, chunk.len);
        if (n < 0) return error.ReadFailed;
        if (n == 0) break;
        try list.appendSlice(allocator, chunk[0..@intCast(n)]);
        if (list.items.len > 32 * 1024 * 1024) return error.BadSize;
    }
    if (list.items.len == 0) return error.BadSize;
    return try list.toOwnedSlice(allocator);
}
