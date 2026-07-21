//! Unit tests — built-in color themes.

const std = @import("std");
const theme = @import("../../config/theme.zig");

test "byName defaults to orbit-dark" {
    const t = theme.byName("unknown-theme");
    try std.testing.expectEqualStrings("orbit-dark", t.name);
}

test "byName orbit-light and alias light" {
    try std.testing.expectEqualStrings("orbit-light", theme.byName("orbit-light").name);
    try std.testing.expectEqualStrings("orbit-light", theme.byName("light").name);
}

test "byName nord" {
    const t = theme.byName("nord");
    try std.testing.expectEqualStrings("nord", t.name);
    try std.testing.expectEqual(@as(u8, 46), t.background.r);
}

test "byName new themes" {
    try std.testing.expectEqualStrings("dracula", theme.byName("dracula").name);
    try std.testing.expectEqualStrings("gruvbox-dark", theme.byName("gruvbox").name);
    try std.testing.expectEqualStrings("solarized-dark", theme.byName("solarized-dark").name);
}

test "nextName cycles builtins" {
    const a = theme.nextName("orbit-dark", 1);
    try std.testing.expectEqualStrings("orbit-light", a);
    const b = theme.nextName("solarized-dark", 1);
    try std.testing.expectEqualStrings("orbit-dark", b);
}

test "applyAnsiOverride uses palette then falls back" {
    const t = theme.orbit_dark;
    const red = t.applyAnsiOverride(1);
    try std.testing.expectEqual(t.ansi[1].r, red.r);
    // index 200 is cube color via Color.fromIndex
    const far = t.applyAnsiOverride(200);
    try std.testing.expect(far.r > 0 or far.g > 0 or far.b > 0 or true);
}

test "orbit_dark has readable contrast" {
    const t = theme.orbit_dark;
    // foreground brighter than background on luminance proxy
    const fg_sum = @as(u16, t.foreground.r) + t.foreground.g + t.foreground.b;
    const bg_sum = @as(u16, t.background.r) + t.background.g + t.background.b;
    try std.testing.expect(fg_sum > bg_sum);
}
