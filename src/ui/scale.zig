//! Shared UI scale for home and overlays on large / Retina framebuffers.
//! Keeps panels readable without becoming full-bleed on ultrawide screens.

const std = @import("std");

/// Scale UI with window size (1.0 at ~default framebuffer, up to ~2.2 in fullscreen).
pub fn uiScale(fb_w: i32, fb_h: i32) f32 {
    _ = fb_w;
    // ~1120px is a typical Retina height for the default 560pt window.
    const ref_h: f32 = 1100.0;
    const s = @as(f32, @floatFromInt(@max(fb_h, 1))) / ref_h;
    return @min(2.2, @max(1.0, s));
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

test "uiScale grows on tall framebuffers" {
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), uiScale(1800, 900), 0.05);
    try std.testing.expect(uiScale(1800, 2200) > 1.8);
    try std.testing.expect(uiScale(1800, 2200) <= 2.2);
}

test "panelWidth stays within framebuffer" {
    const cw: i32 = 16;
    const fb_w: i32 = 2400;
    const w = panelWidth(fb_w, cw, 52, 560);
    try std.testing.expect(w < fb_w);
    try std.testing.expect(w >= 560);
    try std.testing.expect(w <= @divTrunc(fb_w * 12, 25) + 1);
}
