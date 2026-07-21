//! Startup home screen — welcome, logo, version, and quick actions.

const std = @import("std");
const Renderer = @import("../renderer/renderer.zig").Renderer;
const Color = @import("../terminal/cell.zig").Color;

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
    const top = @max(28, @divTrunc(fb_h, 12));
    const logo_h = try drawLogo(renderer, cx, top);

    // Brand — hero signal under the mark
    const brand = "Orbit";
    const brand_y = top + logo_h + 18;
    const brand_x = cx - @divTrunc(@as(i32, @intCast(brand.len)) * @as(i32, @intFromFloat(renderer.cell_w)), 2);
    try renderer.drawText(brand_x, brand_y, brand, Color.rgb(236, 242, 248));

    const tag = "Stay in the flow.";
    const tag_y = brand_y + @as(i32, @intFromFloat(renderer.cell_h)) + 6;
    const tag_x = cx - @divTrunc(@as(i32, @intCast(tag.len)) * @as(i32, @intFromFloat(renderer.cell_w)), 2);
    try renderer.drawText(tag_x, tag_y, tag, Color.rgb(140, 165, 190));

    var meta: [80]u8 = undefined;
    const meta_line = std.fmt.bufPrint(&meta, "v{s}  ·  theme {s}  ·  scale {d:.1}", .{ version, theme_name, font_scale }) catch "v0.1.0";
    const meta_y = tag_y + @as(i32, @intFromFloat(renderer.cell_h)) + 10;
    const meta_x = cx - @divTrunc(@as(i32, @intCast(meta_line.len)) * @as(i32, @intFromFloat(renderer.cell_w)), 2);
    try renderer.drawText(meta_x, meta_y, meta_line, Color.rgb(100, 115, 130));

    if (home.show_help) {
        try drawHelp(renderer, fb_w, fb_h, cx);
        return;
    }

    // Welcome panel
    const panel_w: i32 = @min(520, fb_w - 48);
    const row_h: i32 = @max(26, @as(i32, @intFromFloat(renderer.cell_h)) + 10);
    const panel_h: i32 = 36 + @as(i32, @intCast(entries.len)) * row_h + 56;
    const panel_x = cx - @divTrunc(panel_w, 2);
    const panel_y = meta_y + @as(i32, @intFromFloat(renderer.cell_h)) + 28;

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
}

/// Terminal-window brand mark. Returns drawn height for layout.
fn drawLogo(renderer: *Renderer, cx: i32, top: i32) !i32 {
    const win_w: i32 = 148;
    const title_h: i32 = 22;
    const body_h: i32 = 72;
    const win_h = title_h + body_h;
    const wx = cx - @divTrunc(win_w, 2);
    const wy = top;

    // Soft ambient behind the window (subtle orbit glow)
    try renderer.drawRect(wx - 14, wy - 8, win_w + 28, win_h + 16, Color.rgb(22, 36, 52), 0.35);

    // Outer frame / shadow
    try renderer.drawRect(wx - 2, wy + 3, win_w + 4, win_h + 2, Color.rgb(6, 8, 12), 0.55);
    try renderer.drawRect(wx, wy, win_w, win_h, Color.rgb(28, 34, 44), 1.0);

    // Title bar
    try renderer.drawRect(wx, wy, win_w, title_h, Color.rgb(38, 46, 58), 1.0);
    try renderer.drawRect(wx, wy + title_h - 1, win_w, 1, Color.rgb(18, 22, 28), 1.0);

    // Traffic lights
    const dot_y = wy + 7;
    try renderer.drawRect(wx + 10, dot_y, 8, 8, Color.rgb(232, 98, 92), 1.0);
    try renderer.drawRect(wx + 24, dot_y, 8, 8, Color.rgb(230, 176, 72), 1.0);
    try renderer.drawRect(wx + 38, dot_y, 8, 8, Color.rgb(88, 186, 110), 1.0);

    // Title caption
    const caption = "orbit";
    const cap_x = wx + 58;
    try renderer.drawText(cap_x, wy + 4, caption, Color.rgb(150, 165, 185));

    // Screen body
    const screen_x = wx + 4;
    const screen_y = wy + title_h + 4;
    const screen_w = win_w - 8;
    const screen_h = body_h - 8;
    try renderer.drawRect(screen_x, screen_y, screen_w, screen_h, Color.rgb(10, 12, 16), 1.0);

    // Left accent rail (terminal feel)
    try renderer.drawRect(screen_x, screen_y, 2, screen_h, Color.rgb(55, 120, 175), 0.9);

    // Prompt lines inside the window
    const cw = @as(i32, @intFromFloat(renderer.cell_w));
    const ch = @as(i32, @intFromFloat(renderer.cell_h));
    const line1_y = screen_y + 10;
    const line2_y = line1_y + ch + 6;
    try renderer.drawText(screen_x + 10, line1_y, "~", Color.rgb(120, 160, 140));
    try renderer.drawText(screen_x + 10 + cw + 2, line1_y, ">", Color.rgb(90, 175, 220));

    // Block cursor after the prompt
    const cursor_x = screen_x + 10 + cw * 2 + 8;
    const cursor_h = @max(12, ch - 2);
    try renderer.drawRect(cursor_x, line1_y + 1, @max(8, cw - 2), cursor_h, Color.rgb(200, 220, 240), 0.95);

    // Dim second line — keep short so it fits the window
    if (line2_y + ch < screen_y + screen_h - 4) {
        try renderer.drawText(screen_x + 10, line2_y, "$ orbit", Color.rgb(70, 85, 100));
    }

    // Thin orbit ring under the window (brand cue, not the main mark)
    const ring_y = wy + win_h + 2;
    try renderer.drawRect(cx - 40, ring_y, 80, 2, Color.rgb(55, 110, 160), 0.45);
    try renderer.drawRect(cx + 36, ring_y - 2, 5, 5, Color.rgb(200, 180, 100), 0.7);

    return win_h + 8;
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
