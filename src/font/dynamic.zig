//! On-demand Unicode glyph cache with fallback fonts and synthesized box drawing.

const std = @import("std");
const builtin = @import("builtin");
const atlas_root = @import("atlas.zig");
const faces = @import("faces.zig");
const width = @import("width.zig");
const paths = @import("../platform/paths.zig");

const c = @cImport({
    @cInclude("stb_truetype.h");
});

pub const Slot = struct {
    u0: f32 = 0,
    v0: f32 = 0,
    u1: f32 = 0,
    v1: f32 = 0,
    columns: u8 = 1,
    ok: bool = false,
};

const LoadedFont = struct {
    data: []u8,
    info: c.stbtt_fontinfo,
};

pub const Cache = struct {
    allocator: std.mem.Allocator,
    rgba: []u8,
    tex_w: u32,
    tex_h: u32,
    cell_w: u32,
    cell_h: u32,
    baseline: i32,
    pack_x: u32 = 0,
    pack_y: u32 = 0,
    pack_row_h: u32 = 0,
    map: std.AutoHashMap(u21, Slot),
    fonts: std.ArrayList(LoadedFont),
    dirty: bool = true,

    pub fn create(allocator: std.mem.Allocator, pixel_size: u32, preferred_path: ?[:0]const u8) !Cache {
        const px = @max(10, @min(96, pixel_size));
        var fonts: std.ArrayList(LoadedFont) = .empty;
        errdefer {
            for (fonts.items) |f| allocator.free(f.data);
            fonts.deinit(allocator);
        }

        try loadFont(allocator, &fonts, preferred_path);
        for (faces.catalog) |face| {
            if (preferred_path) |p| {
                if (std.mem.eql(u8, p, face.path)) continue;
            }
            try loadFont(allocator, &fonts, face.path);
        }
        for (fallbackPaths()) |p| {
            try loadFont(allocator, &fonts, p);
        }
        if (fonts.items.len == 0) return error.FontNotFound;

        var ascent: c_int = 0;
        var descent: c_int = 0;
        var line_gap: c_int = 0;
        const scale = c.stbtt_ScaleForPixelHeight(&fonts.items[0].info, @floatFromInt(px));
        c.stbtt_GetFontVMetrics(&fonts.items[0].info, &ascent, &descent, &line_gap);
        const baseline: i32 = @intFromFloat(@ceil(@as(f32, @floatFromInt(ascent)) * scale));
        var advance: c_int = 0;
        var lsb: c_int = 0;
        c.stbtt_GetCodepointHMetrics(&fonts.items[0].info, 'M', &advance, &lsb);
        const cell_w: u32 = @max(1, @as(u32, @intFromFloat(@ceil(@as(f32, @floatFromInt(advance)) * scale))));
        const cell_h: u32 = @max(
            px + 2,
            @as(u32, @intFromFloat(@ceil(@as(f32, @floatFromInt(ascent - descent)) * scale))) + 2,
        );

        const tex_w: u32 = 1024;
        const tex_h: u32 = 1024;
        const rgba = try allocator.alloc(u8, tex_w * tex_h * 4);
        errdefer allocator.free(rgba);
        @memset(rgba, 0);

        var cache: Cache = .{
            .allocator = allocator,
            .rgba = rgba,
            .tex_w = tex_w,
            .tex_h = tex_h,
            .cell_w = cell_w,
            .cell_h = cell_h,
            .baseline = baseline,
            .map = std.AutoHashMap(u21, Slot).init(allocator),
            .fonts = fonts,
        };

        var cp: u21 = atlas_root.first_codepoint;
        while (cp <= atlas_root.last_codepoint) : (cp += 1) {
            _ = cache.ensure(cp);
        }
        // Common TUI / Latin extras so the first frame is not a storm of rasterization.
        var extra: u21 = 0xA0;
        while (extra <= 0xFF) : (extra += 1) {
            _ = cache.ensure(extra);
        }
        extra = 0x2500;
        while (extra <= 0x259F) : (extra += 1) {
            _ = cache.ensure(extra);
        }
        return cache;
    }

    pub fn deinit(self: *Cache) void {
        self.map.deinit();
        for (self.fonts.items) |f| self.allocator.free(f.data);
        self.fonts.deinit(self.allocator);
        self.allocator.free(self.rgba);
        self.* = undefined;
    }

    pub fn lookup(self: *Cache, cp: u21) Slot {
        if (self.map.get(cp)) |s| return s;
        return self.ensure(cp);
    }

    pub fn ensure(self: *Cache, cp: u21) Slot {
        if (self.map.get(cp)) |s| return s;
        const slot = self.rasterize(cp);
        self.map.put(cp, slot) catch {};
        return slot;
    }

    fn rasterize(self: *Cache, cp: u21) Slot {
        const cols = width.columns(cp);
        if (cols == 0) return .{};

        if (width.isBoxDrawing(cp)) {
            if (self.packBox(cp, cols)) |s| return s;
        }

        var fi: usize = 0;
        while (fi < self.fonts.items.len) : (fi += 1) {
            const font = &self.fonts.items[fi];
            if (c.stbtt_FindGlyphIndex(&font.info, @intCast(cp)) == 0) continue;
            const scale = c.stbtt_ScaleForPixelHeight(&font.info, @floatFromInt(self.cell_h -| 2));
            var gw: c_int = 0;
            var gh: c_int = 0;
            var xoff: c_int = 0;
            var yoff: c_int = 0;
            const bmp = c.stbtt_GetCodepointBitmap(&font.info, scale, scale, @intCast(cp), &gw, &gh, &xoff, &yoff);
            // Space and other no-ink glyphs are valid — do not fall through to LastResort-style tofu.
            if (bmp == null or gw <= 0 or gh <= 0) {
                if (bmp) |p| c.stbtt_FreeBitmap(p, null);
                return self.packBlank(cols);
            }
            defer c.stbtt_FreeBitmap(bmp, null);

            const slot_w = self.cell_w * @max(@as(u32, 1), cols);
            const dest = self.reserve(slot_w, self.cell_h) orelse return .{ .columns = cols };
            blitAlpha(self, dest.x, dest.y, bmp, gw, gh, xoff, self.baseline + yoff, slot_w, self.cell_h);
            self.dirty = true;
            return uvSlot(self, dest.x, dest.y, slot_w, self.cell_h, cols);
        }

        if (width.isBoxDrawing(cp)) {
            if (self.packBox(cp, cols)) |s| return s;
        }
        return .{ .columns = cols };
    }

    fn packBlank(self: *Cache, cols: u8) Slot {
        const slot_w = self.cell_w * @max(@as(u32, 1), cols);
        const dest = self.reserve(slot_w, self.cell_h) orelse return .{ .columns = cols, .ok = true };
        self.dirty = true;
        return uvSlot(self, dest.x, dest.y, slot_w, self.cell_h, cols);
    }

    fn packBox(self: *Cache, cp: u21, cols: u8) ?Slot {
        const slot_w = self.cell_w * @max(@as(u32, 1), cols);
        const dest = self.reserve(slot_w, self.cell_h) orelse return null;
        drawBox(self, dest.x, dest.y, slot_w, self.cell_h, cp);
        self.dirty = true;
        return uvSlot(self, dest.x, dest.y, slot_w, self.cell_h, cols);
    }

    fn reserve(self: *Cache, w: u32, h: u32) ?struct { x: u32, y: u32 } {
        if (w == 0 or h == 0) return null;
        if (self.pack_x + w > self.tex_w) {
            self.pack_x = 0;
            self.pack_y += self.pack_row_h;
            self.pack_row_h = 0;
        }
        if (self.pack_y + h > self.tex_h) return null;
        const x = self.pack_x;
        const y = self.pack_y;
        self.pack_x += w;
        self.pack_row_h = @max(self.pack_row_h, h);
        return .{ .x = x, .y = y };
    }
};

fn uvSlot(self: *const Cache, x: u32, y: u32, w: u32, h: u32, cols: u8) Slot {
    const tw: f32 = @floatFromInt(self.tex_w);
    const th: f32 = @floatFromInt(self.tex_h);
    return .{
        .u0 = @as(f32, @floatFromInt(x)) / tw,
        .v0 = @as(f32, @floatFromInt(y)) / th,
        .u1 = @as(f32, @floatFromInt(x + w)) / tw,
        .v1 = @as(f32, @floatFromInt(y + h)) / th,
        .columns = cols,
        .ok = true,
    };
}

fn blitAlpha(
    self: *Cache,
    ox: u32,
    oy: u32,
    bmp: [*]u8,
    gw: c_int,
    gh: c_int,
    xoff: c_int,
    yoff: i32,
    clip_w: u32,
    clip_h: u32,
) void {
    var row: c_int = 0;
    while (row < gh) : (row += 1) {
        const dy = @as(i32, @intCast(oy)) + yoff + row;
        if (dy < @as(i32, @intCast(oy)) or dy >= @as(i32, @intCast(oy + clip_h))) continue;
        var col: c_int = 0;
        while (col < gw) : (col += 1) {
            const dx = @as(i32, @intCast(ox)) + xoff + col;
            if (dx < @as(i32, @intCast(ox)) or dx >= @as(i32, @intCast(ox + clip_w))) continue;
            const src = bmp[@as(usize, @intCast(row * gw + col))];
            if (src == 0) continue;
            const p = (@as(usize, @intCast(dy)) * self.tex_w + @as(usize, @intCast(dx))) * 4;
            self.rgba[p + 0] = 255;
            self.rgba[p + 1] = 255;
            self.rgba[p + 2] = 255;
            self.rgba[p + 3] = src;
        }
    }
}

fn setPx(self: *Cache, x: u32, y: u32, a: u8) void {
    if (x >= self.tex_w or y >= self.tex_h) return;
    const p = (y * self.tex_w + x) * 4;
    self.rgba[p + 0] = 255;
    self.rgba[p + 1] = 255;
    self.rgba[p + 2] = 255;
    self.rgba[p + 3] = @max(self.rgba[p + 3], a);
}

fn hline(self: *Cache, x0: u32, x1: u32, y: u32, a: u8) void {
    var x = x0;
    while (x <= x1) : (x += 1) setPx(self, x, y, a);
}

fn vline(self: *Cache, x: u32, y0: u32, y1: u32, a: u8) void {
    var y = y0;
    while (y <= y1) : (y += 1) setPx(self, x, y, a);
}

fn fill(self: *Cache, x0: u32, y0: u32, x1: u32, y1: u32, a: u8) void {
    var y = y0;
    while (y <= y1) : (y += 1) {
        var x = x0;
        while (x <= x1) : (x += 1) setPx(self, x, y, a);
    }
}

fn drawBox(self: *Cache, ox: u32, oy: u32, w: u32, h: u32, cp: u21) void {
    if (w < 2 or h < 2) return;
    const mid_x = ox + w / 2;
    const mid_y = oy + h / 2;
    const x0 = ox;
    const x1 = ox + w - 1;
    const y0 = oy;
    const y1 = oy + h - 1;
    const a: u8 = 230;

    if (cp >= 0x2580 and cp <= 0x259F) {
        switch (cp) {
            0x2580 => fill(self, x0, y0, x1, mid_y, a), // upper half
            0x2584 => fill(self, x0, mid_y, x1, y1, a), // lower half
            0x2588 => fill(self, x0, y0, x1, y1, a), // full
            0x258C => fill(self, x0, y0, mid_x, y1, a), // left half
            0x2590 => fill(self, mid_x, y0, x1, y1, a), // right half
            0x2591 => fill(self, x0, y0, x1, y1, 70),
            0x2592 => fill(self, x0, y0, x1, y1, 130),
            0x2593 => fill(self, x0, y0, x1, y1, 190),
            else => fill(self, x0, mid_y, x1, y1, a),
        }
        return;
    }

    const bits = boxBits(cp);
    if (bits.l) hline(self, x0, mid_x, mid_y, a);
    if (bits.r) hline(self, mid_x, x1, mid_y, a);
    if (bits.u) vline(self, mid_x, y0, mid_y, a);
    if (bits.d) vline(self, mid_x, mid_y, y1, a);
}

const BoxBits = struct { l: bool = false, r: bool = false, u: bool = false, d: bool = false };

fn boxBits(cp: u21) BoxBits {
    return switch (cp) {
        0x2500, 0x2501, 0x2504, 0x2505, 0x2508, 0x2509, 0x254C, 0x254D => .{ .l = true, .r = true },
        0x2502, 0x2503, 0x2506, 0x2507, 0x250A, 0x250B, 0x254E, 0x254F => .{ .u = true, .d = true },
        0x250C, 0x250D, 0x250E, 0x250F => .{ .r = true, .d = true },
        0x2510, 0x2511, 0x2512, 0x2513 => .{ .l = true, .d = true },
        0x2514, 0x2515, 0x2516, 0x2517 => .{ .r = true, .u = true },
        0x2518, 0x2519, 0x251A, 0x251B => .{ .l = true, .u = true },
        0x251C, 0x251D, 0x251E, 0x251F, 0x2520, 0x2521, 0x2522, 0x2523 => .{ .u = true, .d = true, .r = true },
        0x2524, 0x2525, 0x2526, 0x2527, 0x2528, 0x2529, 0x252A, 0x252B => .{ .u = true, .d = true, .l = true },
        0x252C, 0x252D, 0x252E, 0x252F, 0x2530, 0x2531, 0x2532, 0x2533 => .{ .l = true, .r = true, .d = true },
        0x2534, 0x2535, 0x2536, 0x2537, 0x2538, 0x2539, 0x253A, 0x253B => .{ .l = true, .r = true, .u = true },
        0x253C...0x254B, 0x256A...0x256C => .{ .l = true, .r = true, .u = true, .d = true },
        0x2550 => .{ .l = true, .r = true },
        0x2551 => .{ .u = true, .d = true },
        0x2552, 0x2553, 0x2554 => .{ .r = true, .d = true },
        0x2555, 0x2556, 0x2557 => .{ .l = true, .d = true },
        0x2558, 0x2559, 0x255A => .{ .r = true, .u = true },
        0x255B, 0x255C, 0x255D => .{ .l = true, .u = true },
        0x255E, 0x255F, 0x2560 => .{ .u = true, .d = true, .r = true },
        0x2561, 0x2562, 0x2563 => .{ .u = true, .d = true, .l = true },
        0x2564, 0x2565, 0x2566 => .{ .l = true, .r = true, .d = true },
        0x2567, 0x2568, 0x2569 => .{ .l = true, .r = true, .u = true },
        else => .{ .l = true, .r = true },
    };
}

fn loadFont(allocator: std.mem.Allocator, fonts: *std.ArrayList(LoadedFont), path: ?[:0]const u8) !void {
    const p = path orelse return;
    if (!paths.pathExists(p)) return;
    const data = readAbsolute(allocator, p) catch return;
    errdefer allocator.free(data);
    var info: c.stbtt_fontinfo = undefined;
    if (c.stbtt_InitFont(&info, data.ptr, c.stbtt_GetFontOffsetForIndex(data.ptr, 0)) == 0) {
        allocator.free(data);
        return;
    }
    try fonts.append(allocator, .{ .data = data, .info = info });
}

fn fallbackPaths() []const [:0]const u8 {
    return if (builtin.os.tag == .windows)
        &[_][:0]const u8{
            "C:\\Windows\\Fonts\\seguiemj.ttf",
            "C:\\Windows\\Fonts\\seguisym.ttf",
            "C:\\Windows\\Fonts\\msyh.ttc",
            "C:\\Windows\\Fonts\\msgothic.ttc",
            "C:\\Windows\\Fonts\\malgun.ttf",
        }
    else if (builtin.os.tag == .linux)
        &[_][:0]const u8{
            "/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf",
            "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
            "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
            "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/symbola/Symbola.ttf",
        }
    else
        &[_][:0]const u8{
            "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
            "/System/Library/Fonts/Apple Symbols.ttf",
            "/System/Library/Fonts/Hiragino Sans GB.ttc",
            "/System/Library/Fonts/AppleSDGothicNeo.ttc",
            "/System/Library/Fonts/PingFang.ttc",
            "/Library/Fonts/NerdFonts/SymbolsNerdFontMono-Regular.ttf",
        };
}

fn readAbsolute(allocator: std.mem.Allocator, path: [:0]const u8) ![]u8 {
    const ttf = @import("ttf_atlas.zig");
    return ttf.readFile(allocator, path);
}
