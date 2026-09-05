//! Kitty graphics + iTerm OSC 1337 inline images.

const std = @import("std");

pub const max_payload = 512 * 1024;
pub const max_dim = 4096;

pub const Kind = enum { kitty, iterm };

pub const Placement = struct {
    id: u32 = 0,
    col: u16 = 0,
    row: u16 = 0,
    cols: u16 = 0,
    rows: u16 = 0,
    px_w: u32 = 0,
    px_h: u32 = 0,
    rgba: []u8 = &.{},

    pub fn deinit(self: *Placement, allocator: std.mem.Allocator) void {
        if (self.rgba.len > 0) allocator.free(self.rgba);
        self.rgba = &.{};
    }
};

pub const KittyKeys = struct {
    action: u8 = 'T', // T transmit+display, t transmit, d delete
    format: u16 = 100, // 24/32 rgb(a), 100 png
    more: bool = false,
    id: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    cols: u16 = 0,
    rows: u16 = 0,
};

pub fn parseKittyKeys(header: []const u8) KittyKeys {
    var k: KittyKeys = .{};
    var it = std.mem.splitScalar(u8, header, ',');
    while (it.next()) |part| {
        const eq = std.mem.indexOfScalar(u8, part, '=') orelse continue;
        const key = part[0..eq];
        const val = part[eq + 1 ..];
        if (key.len == 0 or val.len == 0) continue;
        switch (key[0]) {
            'a' => k.action = val[0],
            'f' => k.format = std.fmt.parseInt(u16, val, 10) catch k.format,
            'm' => k.more = val[0] == '1',
            'i' => k.id = std.fmt.parseInt(u32, val, 10) catch 0,
            's' => k.width = std.fmt.parseInt(u32, val, 10) catch 0,
            'v' => k.height = std.fmt.parseInt(u32, val, 10) catch 0,
            'c' => k.cols = std.fmt.parseInt(u16, val, 10) catch 0,
            'r' => k.rows = std.fmt.parseInt(u16, val, 10) catch 0,
            else => {},
        }
    }
    return k;
}

pub fn decodeBase64(allocator: std.mem.Allocator, b64: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, b64, " \t\r\n");
    if (trimmed.len == 0) return error.Empty;
    const dec = std.base64.standard.Decoder;
    const n = dec.calcSizeForSlice(trimmed) catch return error.BadBase64;
    if (n > max_payload) return error.TooLarge;
    const out = try allocator.alloc(u8, n);
    errdefer allocator.free(out);
    dec.decode(out, trimmed) catch {
        allocator.free(out);
        return error.BadBase64;
    };
    return out;
}

/// OSC 1337;File=...:payload  — return the base64 payload after the last `:`.
pub fn itermPayload(osc: []const u8) ?[]const u8 {
    const rest = if (std.mem.startsWith(u8, osc, "1337;")) osc["1337;".len..] else osc;
    if (!std.mem.startsWith(u8, rest, "File=")) return null;
    const colon = std.mem.lastIndexOfScalar(u8, rest, ':') orelse return null;
    const payload = rest[colon + 1 ..];
    if (payload.len == 0) return null;
    return payload;
}

pub fn isInlineIterm(osc: []const u8) bool {
    const rest = if (std.mem.startsWith(u8, osc, "1337;")) osc["1337;".len..] else osc;
    if (!std.mem.startsWith(u8, rest, "File=")) return false;
    const meta = if (std.mem.lastIndexOfScalar(u8, rest, ':')) |c| rest[0..c] else rest;
    return std.mem.indexOf(u8, meta, "inline=1") != null or std.mem.indexOf(u8, meta, "inline=true") != null;
}

extern fn stbi_load_from_memory(
    buffer: [*]const u8,
    len: c_int,
    x: *c_int,
    y: *c_int,
    channels_in_file: *c_int,
    desired_channels: c_int,
) ?[*]u8;
extern fn stbi_image_free(retval_from_stbi_load: ?*anyopaque) void;

pub fn decodeKitty(allocator: std.mem.Allocator, keys: KittyKeys, payload: []const u8) !Placement {
    const raw = try decodeBase64(allocator, payload);
    defer allocator.free(raw);
    return pixelsFromRaw(allocator, keys, raw);
}

pub fn decodeIterm(allocator: std.mem.Allocator, osc: []const u8) !Placement {
    const b64 = itermPayload(osc) orelse return error.NoPayload;
    const raw = try decodeBase64(allocator, b64);
    defer allocator.free(raw);
    return pixelsFromRaw(allocator, .{ .format = 100 }, raw);
}

fn pixelsFromRaw(allocator: std.mem.Allocator, keys: KittyKeys, raw: []const u8) !Placement {
    var px_w: u32 = keys.width;
    var px_h: u32 = keys.height;
    var rgba: []u8 = &.{};

    if (keys.format == 24 or keys.format == 32) {
        if (px_w == 0 or px_h == 0) return error.NeedSize;
        if (px_w > max_dim or px_h > max_dim) return error.TooLarge;
        const bpp: usize = if (keys.format == 24) 3 else 4;
        if (raw.len < @as(usize, px_w) * @as(usize, px_h) * bpp) return error.Short;
        rgba = try allocator.alloc(u8, @as(usize, px_w) * @as(usize, px_h) * 4);
        errdefer allocator.free(rgba);
        var i: usize = 0;
        while (i < @as(usize, px_w) * @as(usize, px_h)) : (i += 1) {
            if (keys.format == 24) {
                rgba[i * 4 + 0] = raw[i * 3 + 0];
                rgba[i * 4 + 1] = raw[i * 3 + 1];
                rgba[i * 4 + 2] = raw[i * 3 + 2];
                rgba[i * 4 + 3] = 255;
            } else {
                @memcpy(rgba[i * 4 ..][0..4], raw[i * 4 ..][0..4]);
            }
        }
    } else {
        var w: c_int = 0;
        var h: c_int = 0;
        var ch: c_int = 0;
        const pixels = stbi_load_from_memory(raw.ptr, @intCast(raw.len), &w, &h, &ch, 4) orelse return error.BadImage;
        defer stbi_image_free(pixels);
        if (w <= 0 or h <= 0 or w > max_dim or h > max_dim) return error.TooLarge;
        px_w = @intCast(w);
        px_h = @intCast(h);
        const n = @as(usize, px_w) * @as(usize, px_h) * 4;
        rgba = try allocator.dupe(u8, pixels[0..n]);
    }

    var cols = keys.cols;
    var rows = keys.rows;
    if (cols == 0) cols = 1;
    if (rows == 0) rows = 1;
    return .{
        .id = keys.id,
        .cols = cols,
        .rows = rows,
        .px_w = px_w,
        .px_h = px_h,
        .rgba = rgba,
    };
}
