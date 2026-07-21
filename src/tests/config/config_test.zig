//! Unit tests — TOML config parsing.

const std = @import("std");
const Config = @import("../../config/config.zig").Config;
const CursorStyle = @import("../../config/config.zig").CursorStyle;

test "parse shell cursor and blink" {
    var cfg: Config = .{};
    defer cfg.deinit(std.testing.allocator);
    Config.parseInto(&cfg, std.testing.allocator,
        \\[terminal]
        \\shell = "/bin/bash"
        \\cursor_style = "underline"
        \\cursor_blink = false
    );
    try std.testing.expectEqualStrings("/bin/bash", cfg.shell.?);
    try std.testing.expectEqual(CursorStyle.underline, cfg.cursor_style);
    try std.testing.expect(!cfg.cursor_blink);
}

test "parse window theme and terminal sections" {
    var cfg: Config = .{};
    defer cfg.deinit(std.testing.allocator);
    Config.parseInto(&cfg, std.testing.allocator,
        \\[window]
        \\width = 1200
        \\height = 800
        \\opacity = 0.85
        \\[theme]
        \\name = "nord"
        \\[terminal]
        \\scrollback = 5000
        \\font_size = 16
        \\padding_x = 12
        \\padding_y = 8
    );
    try std.testing.expectEqual(@as(i32, 1200), cfg.window_width);
    try std.testing.expectEqual(@as(i32, 800), cfg.window_height);
    try std.testing.expectEqual(@as(f32, 0.85), cfg.opacity);
    try std.testing.expectEqualStrings("nord", cfg.theme_name);
    try std.testing.expectEqual(@as(usize, 5000), cfg.scrollback);
    try std.testing.expectEqual(@as(f32, 16), cfg.font_size);
    try std.testing.expectEqual(@as(i32, 12), cfg.padding_x);
    try std.testing.expectEqual(@as(i32, 8), cfg.padding_y);
}

test "opacity is clamped" {
    var cfg: Config = .{};
    defer cfg.deinit(std.testing.allocator);
    Config.parseInto(&cfg, std.testing.allocator,
        \\[window]
        \\opacity = 2.5
    );
    try std.testing.expectEqual(@as(f32, 1.0), cfg.opacity);

    cfg = .{};
    Config.parseInto(&cfg, std.testing.allocator,
        \\[window]
        \\opacity = 0.01
    );
    try std.testing.expectEqual(@as(f32, 0.15), cfg.opacity);
}

test "font_scale maps to font_size" {
    var cfg: Config = .{};
    defer cfg.deinit(std.testing.allocator);
    Config.parseInto(&cfg, std.testing.allocator,
        \\[terminal]
        \\font_scale = 2.0
    );
    try std.testing.expectEqual(@as(f32, 14.0), cfg.font_size);
}

test "font_size is clamped" {
    var cfg: Config = .{};
    defer cfg.deinit(std.testing.allocator);
    Config.parseInto(&cfg, std.testing.allocator,
        \\[terminal]
        \\font_size = 99
    );
    try std.testing.expectEqual(@as(f32, 28.0), cfg.font_size);
}

test "theme() resolves by name" {
    var cfg: Config = .{};
    defer cfg.deinit(std.testing.allocator);
    try cfg.setThemeName(std.testing.allocator, "orbit-light");
    const t = cfg.theme();
    try std.testing.expectEqualStrings("orbit-light", t.name);
}

test "comments and blank lines ignored" {
    var cfg: Config = .{};
    defer cfg.deinit(std.testing.allocator);
    Config.parseInto(&cfg, std.testing.allocator,
        \\# comment
        \\
        \\[window]
        \\# another
        \\width = 640
    );
    try std.testing.expectEqual(@as(i32, 640), cfg.window_width);
}
