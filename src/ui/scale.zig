//! Shared UI scale for home and overlays on large / Retina framebuffers.
//! Keeps panels readable without becoming full-bleed on ultrawide screens.

const std = @import("std");

/// Layout/text scale from *logical* window height (framebuffer ÷ content scale).
/// Atlas glyphs are already Retina-sized — keep this gentle so UI text isn't stretched.
pub fn uiScale(fb_w: i32, fb_h: i32, content_scale: f32) f32 {
    _ = fb_w;
    const cs = @max(1.0, content_scale);
    const logical_h = @as(f32, @floatFromInt(@max(fb_h, 1))) / cs;
    // Default window height in points.
    const ref_h: f32 = 560.0;
    const s = logical_h / ref_h;
    return @min(1.35, @max(1.0, s));
}

pub fn scaled(base: i32, scale: f32) i32 {
    return @max(1, @as(i32, @intFromFloat(@round(@as(f32, @floatFromInt(base)) * scale))));
}

/// Overlay panel width: grows with cell size and screen, capped ~48% of framebuffer.
pub fn panelWidth(fb_w: i32, cw: i32, preferred_cols: i32, min_px: i32) i32 {
    const margin = @max(cw * 3, 24);
    const preferred = @max(cw * preferred_cols, min_px);
    const max_by_frac = @divTrunc(fb_w * 12, 25); // ~48%
    const max_w = fb_w - margin * 2;
    // Prefer a comfortable column count, but allow growth toward the fraction cap.
    const target = @max(preferred, @min(max_by_frac, cw * (preferred_cols + 12)));
    return @min(target, max_w);
}

test "uiScale is gentle on Retina fullscreen" {
    // Default 560pt @2x → fb_h ≈ 1120 → logical 560 → scale 1.0
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), uiScale(1800, 1120, 2.0), 0.05);
    // Tall logical window grows a little, but never double-stretches glyphs.
    try std.testing.expect(uiScale(1800, 2200, 2.0) <= 1.35);
    try std.testing.expect(uiScale(1800, 2200, 2.0) >= 1.0);
}

test "panelWidth stays within framebuffer" {
    const cw: i32 = 16;
    const fb_w: i32 = 2400;
    const w = panelWidth(fb_w, cw, 52, 560);
    try std.testing.expect(w < fb_w);
    try std.testing.expect(w >= 560);
    try std.testing.expect(w <= @divTrunc(fb_w * 12, 25) + 1);
}
