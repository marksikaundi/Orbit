//! Ghostty-style terminal looks: padding, opacity, line height, and prompt.

const std = @import("std");

/// Named visual profiles (window padding + line spacing + opacity).
pub const Look = enum {
    compact,
    comfortable,
    airy,
    glass,

    pub fn fromString(s: []const u8) Look {
        if (std.mem.eql(u8, s, "comfortable") or std.mem.eql(u8, s, "ghostty")) return .comfortable;
        if (std.mem.eql(u8, s, "airy") or std.mem.eql(u8, s, "relaxed")) return .airy;
        if (std.mem.eql(u8, s, "glass") or std.mem.eql(u8, s, "transparent")) return .glass;
        return .compact;
    }

    pub fn name(self: Look) []const u8 {
        return switch (self) {
            .compact => "compact",
            .comfortable => "comfortable",
            .airy => "airy",
            .glass => "glass",
        };
    }

    pub fn next(self: Look) Look {
        return switch (self) {
            .compact => .comfortable,
            .comfortable => .airy,
            .airy => .glass,
            .glass => .compact,
        };
    }

    pub fn prev(self: Look) Look {
        return switch (self) {
            .compact => .glass,
            .comfortable => .compact,
            .airy => .comfortable,
            .glass => .airy,
        };
    }

    pub fn paddingX(self: Look) i32 {
        return switch (self) {
            .compact => 10,
            .comfortable => 16,
            .airy => 24,
            .glass => 16,
        };
    }

    pub fn paddingY(self: Look) i32 {
        return switch (self) {
            .compact => 6,
            .comfortable => 10,
            .airy => 16,
            .glass => 10,
        };
    }

    pub fn lineHeight(self: Look) f32 {
        return switch (self) {
            .compact => 1.00,
            .comfortable => 1.12,
            .airy => 1.24,
            .glass => 1.12,
        };
    }

    pub fn opacity(self: Look) f32 {
        return switch (self) {
            .compact => 1.00,
            .comfortable => 1.00,
            .airy => 1.00,
            .glass => 0.86,
        };
    }
};

/// Prompt overlay applied inside Orbit (new tabs). `default` keeps the user's rc.
pub const PromptStyle = enum {
    default,
    ghostty,
    minimal,
    starship,

    pub fn fromString(s: []const u8) PromptStyle {
        if (std.mem.eql(u8, s, "ghostty") or std.mem.eql(u8, s, "pretty") or std.mem.eql(u8, s, "nice")) return .ghostty;
        if (std.mem.eql(u8, s, "minimal") or std.mem.eql(u8, s, "min")) return .minimal;
        if (std.mem.eql(u8, s, "starship")) return .starship;
        return .default;
    }

    pub fn name(self: PromptStyle) []const u8 {
        return switch (self) {
            .default => "default",
            .ghostty => "ghostty",
            .minimal => "minimal",
            .starship => "starship",
        };
    }

    pub fn next(self: PromptStyle) PromptStyle {
        return switch (self) {
            .default => .ghostty,
            .ghostty => .minimal,
            .minimal => .starship,
            .starship => .default,
        };
    }

    pub fn prev(self: PromptStyle) PromptStyle {
        return switch (self) {
            .default => .starship,
            .ghostty => .default,
            .minimal => .ghostty,
            .starship => .minimal,
        };
    }
};

pub const padding_steps = [_]i32{ 4, 6, 10, 14, 16, 18, 22, 28 };
pub const opacity_steps = [_]f32{ 1.00, 0.95, 0.90, 0.86, 0.80, 0.70 };
pub const line_height_steps = [_]f32{ 1.00, 1.08, 1.12, 1.18, 1.24, 1.32 };

pub fn cyclePadding(current_x: i32, delta: i32) i32 {
    return cycleI32(&padding_steps, current_x, delta);
}

pub fn cycleOpacity(current: f32, delta: i32) f32 {
    return cycleF32(&opacity_steps, current, delta, 0.02);
}

pub fn cycleLineHeight(current: f32, delta: i32) f32 {
    return cycleF32(&line_height_steps, current, delta, 0.02);
}

pub fn lineHeightLabel(h: f32) []const u8 {
    if (h <= 1.02) return "tight";
    if (h <= 1.10) return "snug";
    if (h <= 1.15) return "comfortable";
    if (h <= 1.21) return "roomy";
    if (h <= 1.28) return "airy";
    return "loose";
}

fn cycleI32(steps: []const i32, current: i32, delta: i32) i32 {
    var idx: i32 = 0;
    var best_dist: u32 = std.math.maxInt(u32);
    for (steps, 0..) |s, i| {
        const dist = @abs(s - current);
        if (dist < best_dist) {
            best_dist = dist;
            idx = @intCast(i);
        }
    }
    const n: i32 = @intCast(steps.len);
    idx = @mod(idx + delta, n);
    if (idx < 0) idx += n;
    return steps[@intCast(idx)];
}

fn cycleF32(steps: []const f32, current: f32, delta: i32, eps: f32) f32 {
    var idx: i32 = 0;
    var best: f32 = 999.0;
    for (steps, 0..) |s, i| {
        const dist = @abs(s - current);
        if (dist < best) {
            best = dist;
            idx = @intCast(i);
        } else if (dist <= eps and @abs(s - current) <= eps) {
            idx = @intCast(i);
        }
    }
    const n: i32 = @intCast(steps.len);
    idx = @mod(idx + delta, n);
    if (idx < 0) idx += n;
    return steps[@intCast(idx)];
}

/// Parse Ghostty-style cell height: `1.12`, `+12%`, `12%`, or `2` (pixels ≈ +2/16).
pub fn parseLineHeight(s: []const u8) ?f32 {
    var t = std.mem.trim(u8, s, " \t");
    if (t.len == 0) return null;
    if (t[t.len - 1] == '%') {
        const num = std.fmt.parseFloat(f32, t[0 .. t.len - 1]) catch return null;
        if (num >= 50.0) return std.math.clamp(num / 100.0, 1.0, 1.5);
        return std.math.clamp(1.0 + num / 100.0, 1.0, 1.5);
    }
    const v = std.fmt.parseFloat(f32, t) catch return null;
    if (v >= 1.0 and v <= 1.5) return v;
    if (v > 1.5 and v < 50.0) {
        // Pixel bump, Ghostty `adjust-cell-height = 2`.
        return std.math.clamp(1.0 + v / 16.0, 1.0, 1.5);
    }
    return std.math.clamp(v, 1.0, 1.5);
}

test "look cycle wraps" {
    try std.testing.expectEqual(Look.comfortable, Look.compact.next());
    try std.testing.expectEqual(Look.compact, Look.glass.next());
    try std.testing.expectEqual(Look.glass, Look.compact.prev());
}

test "look fromString aliases" {
    try std.testing.expectEqual(Look.comfortable, Look.fromString("ghostty"));
    try std.testing.expectEqual(Look.glass, Look.fromString("transparent"));
    try std.testing.expectEqual(Look.compact, Look.fromString("nope"));
}

test "prompt cycle and names" {
    try std.testing.expectEqual(PromptStyle.ghostty, PromptStyle.default.next());
    try std.testing.expectEqualStrings("starship", PromptStyle.starship.name());
    try std.testing.expectEqual(PromptStyle.ghostty, PromptStyle.fromString("pretty"));
}

test "padding and opacity cycle" {
    try std.testing.expectEqual(@as(i32, 14), cyclePadding(10, 1));
    try std.testing.expectEqual(@as(i32, 28), cyclePadding(4, -1));
    try std.testing.expectEqual(@as(f32, 0.95), cycleOpacity(1.00, 1));
    try std.testing.expectEqual(@as(f32, 0.70), cycleOpacity(1.00, -1));
}

test "parseLineHeight accepts percent and multiplier" {
    try std.testing.expectEqual(@as(f32, 1.12), parseLineHeight("1.12").?);
    try std.testing.expectEqual(@as(f32, 1.20), parseLineHeight("20%").?);
    try std.testing.expectEqual(@as(f32, 1.12), parseLineHeight("12%").?);
    try std.testing.expect(parseLineHeight("abc") == null);
}

test "lineHeightLabel buckets" {
    try std.testing.expectEqualStrings("tight", lineHeightLabel(1.0));
    try std.testing.expectEqualStrings("comfortable", lineHeightLabel(1.12));
    try std.testing.expectEqualStrings("airy", lineHeightLabel(1.24));
}
