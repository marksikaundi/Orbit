//! Optional HarfBuzz OpenType shaping (`zig build -Dharfbuzz`).
//! When the library is not linked, this returns empty and `shape.zig` is used.

const std = @import("std");
const build_options = @import("build_options");

pub const enabled = build_options.harfbuzz;

pub fn shapeFile(path: [*:0]const u8, px: i32, cps: []const u32, out: []u32) usize {
    if (comptime !enabled) return 0;
    if (cps.len == 0 or out.len == 0) return 0;
    const c = struct {
        extern fn orbit_hb_shape(
            font_path: [*:0]const u8,
            px: c_int,
            cps: [*]const u32,
            cp_count: c_int,
            out_glyphs: [*]u32,
            out_cap: c_int,
        ) c_int;
    };
    const n = c.orbit_hb_shape(path, px, cps.ptr, @intCast(cps.len), out.ptr, @intCast(out.len));
    return if (n <= 0) 0 else @intCast(n);
}
