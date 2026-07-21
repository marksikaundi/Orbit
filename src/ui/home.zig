//! Startup home screen — welcome, logo, version, and quick actions.

const std = @import("std");
const Renderer = @import("../renderer/renderer.zig").Renderer;
const Color = @import("../terminal/cell.zig").Color;
const bitmap = @import("../font/bitmap.zig");

pub const version = "0.1.0";

pub const Action = enum {
    new_terminal,
    open_workspace,
    command_palette,
    settings,
    help,
};

pub const Entry = struct {
    action: Action,
    label: []const u8,
    key: []const u8,
};

pub const entries = [_]Entry{
    .{ .action = .new_terminal, .label = "New Terminal", .key = "Enter" },
    .{ .action = .open_workspace, .label = "Open Workspace", .key = "O" },
    .{ .action = .command_palette, .label = "Command Palette", .key = "P" },
    .{ .action = .settings, .label = "Settings / Config", .key = "S" },
    .{ .action = .help, .label = "Help & Shortcuts", .key = "H" },
};

pub const Home = struct {
    selected: usize = 0,
    show_help: bool = false,

    pub fn moveUp(self: *Home) void {
        if (self.show_help) return;
        if (self.selected > 0) self.selected -= 1;
    }

    pub fn moveDown(self: *Home) void {
        if (self.show_help) return;
        if (self.selected + 1 < entries.len) self.selected += 1;
    }

    pub fn selectedAction(self: *const Home) Action {
        return entries[self.selected].action;
    }
};

pub fn draw(
    renderer: *Renderer,
    fb_w: i32,
    fb_h: i32,
    home: *const Home,
    theme_name: []const u8,
    font_scale: f32,
    plugin_count: usize,
) !void {
    // Atmosphere — deep slate bands (not flat)
    try renderer.drawRect(0, 0, fb_w, fb_h, Color.rgb(12, 14, 18), 1.0);
    try renderer.drawRect(0, 0, fb_w, @divTrunc(fb_h, 3), Color.rgb(16, 22, 30), 1.0);
    try renderer.drawRect(0, @divTrunc(fb_h * 2, 3), fb_w, @divTrunc(fb_h, 3) + 8, Color.rgb(10, 12, 16), 1.0);

    const cx = @divTrunc(fb_w, 2);
    const top = @max(36, @divTrunc(fb_h, 10));

    try drawLogo(renderer, cx, top);

    // Brand
    const brand = "Orbit";
    const brand_x = cx - @divTrunc(@as(i32, @intCast(brand.len)) * @as(i32, @intFromFloat(renderer.cell_w)), 2);
    try renderer.drawText(brand_x, top + 78, brand, Color.rgb(236, 242, 248));

    const tag = "Stay in the flow.";
    const tag_x = cx - @divTrunc(@as(i32, @intCast(tag.len)) * @as(i32, @intFromFloat(renderer.cell_w)), 2);
    try renderer.drawText(tag_x, top + 78 + @as(i32, @intFromFloat(renderer.cell_h)) + 6, tag, Color.rgb(140, 165, 190));

    var meta: [80]u8 = undefined;
    const meta_line = std.fmt.bufPrint(&meta, "v{s}  ·  theme {s}  ·  scale {d:.1}", .{ version, theme_name, font_scale }) catch "v0.1.0";
    const meta_x = cx - @divTrunc(@as(i32, @intCast(meta_line.len)) * @as(i32, @intFromFloat(renderer.cell_w)), 2);
    try renderer.drawText(meta_x, top + 78 + @as(i32, @intFromFloat(renderer.cell_h)) * 2 + 14, meta_line, Color.rgb(100, 115, 130));

    if (home.show_help) {
        try drawHelp(renderer, fb_w, fb_h, cx);
        return;
    }

    // Welcome panel
    const panel_w: i32 = @min(520, fb_w - 48);
    const row_h: i32 = @max(26, @as(i32, @intFromFloat(renderer.cell_h)) + 10);
    const panel_h: i32 = 36 + @as(i32, @intCast(entries.len)) * row_h + 56;
    const panel_x = cx - @divTrunc(panel_w, 2);
    const panel_y = top + 150;

    try renderer.drawRect(panel_x, panel_y, panel_w, panel_h, Color.rgb(20, 24, 32), 0.96);
    // Accent edge
    try renderer.drawRect(panel_x, panel_y, 3, panel_h, Color.rgb(70, 140, 200), 1.0);

    try renderer.drawText(panel_x + 20, panel_y + 14, "Welcome — what would you like to do?", Color.rgb(210, 220, 230));

    for (entries, 0..) |entry, i| {
        const ry = panel_y + 40 + @as(i32, @intCast(i)) * row_h;
        if (i == home.selected) {
            try renderer.drawRect(panel_x + 10, ry - 2, panel_w - 20, row_h - 2, Color.rgb(40, 70, 105), 1.0);
        }
        var line: [64]u8 = undefined;
        const label = std.fmt.bufPrint(&line, "  {s}", .{entry.label}) catch entry.label;
        try renderer.drawText(panel_x + 16, ry + 4, label, Color.rgb(230, 235, 240));
        const key_x = panel_x + panel_w - 20 - @as(i32, @intCast(entry.key.len)) * @as(i32, @intFromFloat(renderer.cell_w));
        try renderer.drawText(key_x, ry + 4, entry.key, Color.rgb(120, 160, 200));
    }

    var foot: [96]u8 = undefined;
    const foot_line = std.fmt.bufPrint(
        &foot,
        "config ~/.config/orbit/  ·  plugins {d}  ·  Up/Down + Enter",
        .{plugin_count},
    ) catch "config ~/.config/orbit/";
    const foot_y = panel_y + panel_h + 18;
    const foot_x = cx - @divTrunc(@as(i32, @intCast(foot_line.len)) * @as(i32, @intFromFloat(renderer.cell_w)), 2);
    if (foot_y + 20 < fb_h) {
        try renderer.drawText(foot_x, foot_y, foot_line, Color.rgb(90, 105, 120));
    }

    _ = bitmap;
}

fn drawLogo(renderer: *Renderer, cx: i32, top: i32) !void {
    // Orbit mark: planet + ring + satellite (rect geometry)
    const planet: i32 = 28;
    const px = cx - @divTrunc(planet, 2);
    const py = top;

    // Soft glow
    try renderer.drawRect(px - 10, py - 8, planet + 20, planet + 16, Color.rgb(28, 48, 72), 0.5);

    // Ring (horizontal ellipse approximation)
    const ring_w: i32 = 72;
    const ring_h: i32 = 18;
    const rx = cx - @divTrunc(ring_w, 2);
    const ry = py + @divTrunc(planet, 2) - @divTrunc(ring_h, 2);
    try renderer.drawRect(rx, ry, ring_w, 3, Color.rgb(90, 160, 220), 0.9);
    try renderer.drawRect(rx, ry + ring_h - 3, ring_w, 3, Color.rgb(60, 110, 160), 0.7);
    try renderer.drawRect(rx, ry, 3, ring_h, Color.rgb(80, 140, 190), 0.6);
    try renderer.drawRect(rx + ring_w - 3, ry, 3, ring_h, Color.rgb(80, 140, 190), 0.6);

    // Planet
    try renderer.drawRect(px, py, planet, planet, Color.rgb(70, 150, 210), 1.0);
    try renderer.drawRect(px + 4, py + 4, planet - 10, planet - 10, Color.rgb(40, 100, 160), 1.0);
    try renderer.drawRect(px + 8, py + 8, 8, 8, Color.rgb(180, 220, 255), 0.85);

    // Satellite
    try renderer.drawRect(cx + 34, py + 4, 8, 8, Color.rgb(230, 200, 120), 1.0);
    try renderer.drawRect(cx + 28, py + 7, 6, 2, Color.rgb(160, 140, 80), 0.8);
}

fn drawHelp(renderer: *Renderer, fb_w: i32, fb_h: i32, cx: i32) !void {
    const panel_w: i32 = @min(560, fb_w - 40);
    const panel_h: i32 = @min(340, fb_h - 80);
    const panel_x = cx - @divTrunc(panel_w, 2);
    const panel_y = @divTrunc(fb_h - panel_h, 2);

    try renderer.drawRect(panel_x, panel_y, panel_w, panel_h, Color.rgb(18, 22, 28), 0.98);
    try renderer.drawRect(panel_x, panel_y, panel_w, 3, Color.rgb(70, 140, 200), 1.0);
    try renderer.drawText(panel_x + 20, panel_y + 16, "Help & Shortcuts", Color.rgb(230, 235, 240));

    const lines = [_][]const u8{
        "Ctrl+Shift+P   Command palette",
        "Ctrl+= / - / 0 Font larger / smaller / reset",
        "Ctrl+Shift+T   New tab",
        "Ctrl+Shift+D/E Split right / down",
        "Ctrl+Shift+O/S Open / save workspace",
        "Ctrl+Shift+F   Search",
        "Ctrl+Shift+H   Return to home",
        "",
        "Config:  ~/.config/orbit/config.toml",
        "Plugins: ~/.config/orbit/plugins/",
        "",
        "Esc  back to home",
    };

    var y = panel_y + 48;
    const step = @max(18, @as(i32, @intFromFloat(renderer.cell_h)) + 4);
    for (lines) |line| {
        if (line.len > 0) {
            try renderer.drawText(panel_x + 24, y, line, Color.rgb(180, 195, 210));
        }
        y += step;
        if (y > panel_y + panel_h - 24) break;
    }
}
