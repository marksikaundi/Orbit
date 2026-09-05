//! stb_truetype atlas builder — loads a system monospace font from disk.

const std = @import("std");
const builtin = @import("builtin");
const atlas_root = @import("atlas.zig");
const faces = @import("faces.zig");

const c = @cImport({
    @cInclude("stb_truetype.h");
});

pub fn build(allocator: std.mem.Allocator, pixel_size: u32, preferred_path: ?[:0]const u8) !atlas_root.Atlas {
    var font_data: ?[]u8 = null;
    if (preferred_path) |path| {
        font_data = readAbsolute(allocator, path) catch null;
    }
    if (font_data == null) {
        for (faces.catalog) |face| {
            font_data = readAbsolute(allocator, face.path) catch continue;
            break;
        }
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

pub fn readFile(allocator: std.mem.Allocator, path: [:0]const u8) ![]u8 {
    return readAbsolute(allocator, path);
}

fn readAbsolute(allocator: std.mem.Allocator, path: [:0]const u8) ![]u8 {
    if (builtin.os.tag == .windows) {
        const w = struct {
            extern "kernel32" fn CreateFileA(
                lpFileName: [*:0]const u8,
                dwDesiredAccess: u32,
                dwShareMode: u32,
                lpSecurityAttributes: ?*anyopaque,
                dwCreationDisposition: u32,
                dwFlagsAndAttributes: u32,
                hTemplateFile: ?*anyopaque,
            ) callconv(.winapi) ?*anyopaque;
            extern "kernel32" fn ReadFile(
                hFile: *anyopaque,
                lpBuffer: [*]u8,
                nNumberOfBytesToRead: u32,
                lpNumberOfBytesRead: ?*u32,
                lpOverlapped: ?*anyopaque,
            ) callconv(.winapi) std.os.windows.BOOL;
            extern "kernel32" fn CloseHandle(hObject: *anyopaque) callconv(.winapi) std.os.windows.BOOL;
            const GENERIC_READ: u32 = 0x80000000;
            const FILE_SHARE_READ: u32 = 0x00000001;
            const OPEN_EXISTING: u32 = 3;
            const INVALID: usize = std.math.maxInt(usize);
        };
        const handle = w.CreateFileA(path.ptr, w.GENERIC_READ, w.FILE_SHARE_READ, null, w.OPEN_EXISTING, 0, null);
        if (handle == null or @intFromPtr(handle) == w.INVALID) return error.OpenFailed;
        defer _ = w.CloseHandle(handle.?);

        var list: std.ArrayList(u8) = .empty;
        errdefer list.deinit(allocator);
        var chunk: [16 * 1024]u8 = undefined;
        while (true) {
            var got: u32 = 0;
            if (!w.ReadFile(handle.?, &chunk, chunk.len, &got, null).toBool()) return error.ReadFailed;
            if (got == 0) break;
            try list.appendSlice(allocator, chunk[0..got]);
            if (list.items.len > 32 * 1024 * 1024) return error.BadSize;
        }
        if (list.items.len == 0) return error.BadSize;
        return try list.toOwnedSlice(allocator);
    }

    const fd = std.c.open(path.ptr, @bitCast(@as(c_uint, 0))); // O_RDONLY
    if (fd < 0) return error.OpenFailed;
    defer _ = std.c.close(fd);

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
