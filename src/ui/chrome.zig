//! Theme-derived overlay chrome — same recipe as Help & Shortcuts.
//! Panels lift from the active theme background so Appearance / Plugins /
//! Palette stay uniform when the theme changes.

const Color = @import("../terminal/cell.zig").Color;
const theme_mod = @import("../config/theme.zig");

pub const Chrome = struct {
    /// Theme background (backdrop / clear).
    bg: Color,
    /// Slightly lifted panel fill (Help-style).
    panel: Color,
    fg: Color,
    muted: Color,
    dim: Color,
    /// Theme blue (ansi[4]) — headings, selection bar, value accents.
    accent: Color,
    sel_bg: Color,
    rule: Color,
    /// Inset field (search box) — a touch darker than the panel.
    field: Color,
    on_col: Color,
    off_col: Color,
};

pub fn fromTheme(theme: theme_mod.Theme) Chrome {
    const bg = theme.background;
    const fg = theme.foreground;
    return .{
        .bg = bg,
        .panel = lift(bg, 8, 8, 10),
        .fg = fg,
        .muted = mix(fg, bg, 1, 2),
        .dim = mix(fg, bg, 1, 4),
        .accent = theme.ansi[4],
        .sel_bg = theme.selection_bg,
        .rule = lift(bg, 22, 22, 26),
        .field = lift(bg, -6, -6, -6),
        .on_col = theme.ansi[2],
        .off_col = theme.ansi[1],
    };
}

fn lift(c: Color, dr: i32, dg: i32, db: i32) Color {
    return Color.rgb(
        @intCast(@max(0, @min(255, @as(i32, c.r) + dr))),
        @intCast(@max(0, @min(255, @as(i32, c.g) + dg))),
        @intCast(@max(0, @min(255, @as(i32, c.b) + db))),
    );
}

/// Weighted mix: `(fg * a + bg * b) / (a + b)`.
fn mix(fg: Color, bg: Color, a: i32, b: i32) Color {
    const den = a + b;
    return Color.rgb(
        @intCast(@divTrunc(@as(i32, fg.r) * a + @as(i32, bg.r) * b, den)),
        @intCast(@divTrunc(@as(i32, fg.g) * a + @as(i32, bg.g) * b, den)),
        @intCast(@divTrunc(@as(i32, fg.b) * a + @as(i32, bg.b) * b, den)),
    );
}
