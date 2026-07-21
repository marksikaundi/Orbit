//! Startup home — minimal Ghostty-like welcome (no heavy chrome).

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
    quit,
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
    .{ .action = .settings, .label = "Settings", .key = "S" },
    .{ .action = .help, .label = "Help", .key = "H" },
    .{ .action = .quit, .label = "Quit Orbit", .key = "Q" },
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
    font_size: f32,
    plugin_count: usize,
) !void {
    const bg = renderer.theme.background;
    const fg = renderer.theme.foreground;
    const muted = Color.rgb(
        @intCast(@divTrunc(@as(i32, fg.r) + @as(i32, bg.r) * 2, 3)),
        @intCast(@divTrunc(@as(i32, fg.g) + @as(i32, bg.g) * 2, 3)),
        @intCast(@divTrunc(@as(i32, fg.b) + @as(i32, bg.b) * 2, 3)),
    );
    const dim = Color.rgb(
        @intCast(@divTrunc(@as(i32, fg.r) + @as(i32, bg.r) * 4, 5)),
        @intCast(@divTrunc(@as(i32, fg.g) + @as(i32, bg.g) * 4, 5)),
        @intCast(@divTrunc(@as(i32, fg.b) + @as(i32, bg.b) * 4, 5)),
    );

    try renderer.drawRect(0, 0, fb_w, fb_h, bg, 1.0);

    const cw = @as(i32, @intFromFloat(renderer.cell_w));
    const ch = @as(i32, @intFromFloat(renderer.cell_h));
    const cx = @divTrunc(fb_w, 2);

    // Ghostty-like: generous outer padding, single vertical composition.
    const pad_y = @max(ch * 2, @divTrunc(fb_h, 8));
    var y = pad_y;

    // Prompt mark instead of a heavy logo
    const prompt = "~ >";
    const prompt_x = cx - @divTrunc(@as(i32, @intCast(prompt.len)) * cw, 2);
    try renderer.drawText(prompt_x, y, "~", Color.rgb(120, 160, 140));
    try renderer.drawText(prompt_x + cw + @divTrunc(cw, 4), y, ">", Color.rgb(90, 175, 220));
    try renderer.drawRect(prompt_x + cw * 2 + @divTrunc(cw, 2), y + 2, @max(6, cw - 4), ch - 4, fg, 0.85);
    y += ch + @divTrunc(ch, 2);

    // Brand — hero
    const brand = "Orbit";
    const brand_x = cx - @divTrunc(@as(i32, @intCast(brand.len)) * cw, 2);
    try renderer.drawText(brand_x, y, brand, fg);
    y += ch + 6;

    const tag = "Stay in the flow.";
    const tag_x = cx - @divTrunc(@as(i32, @intCast(tag.len)) * cw, 2);
    try renderer.drawText(tag_x, y, tag, muted);
    y += ch + @divTrunc(ch, 2);

    var meta: [96]u8 = undefined;
    const meta_line = std.fmt.bufPrint(
        &meta,
        "v{s}  {s}  {d:.0}pt",
        .{ version, theme_name, font_size },
    ) catch "v0.1.0";
    const meta_x = cx - @divTrunc(@as(i32, @intCast(meta_line.len)) * cw, 2);
    try renderer.drawText(meta_x, y, meta_line, dim);
    y += ch * 2;

    if (home.show_help) {
        try drawHelp(renderer, fb_w, fb_h, cx, bg, fg, muted);
        return;
    }

    // Action list — no cards; selection is a quiet bar only
    const list_w: i32 = @min(cw * 36, fb_w - cw * 4);
    const list_x = cx - @divTrunc(list_w, 2);
    const row_h = ch + @divTrunc(ch, 3);

    try renderer.drawText(list_x, y, "What would you like to do?", muted);
    y += ch + @divTrunc(ch, 2);

    for (entries, 0..) |entry, i| {
        const ry = y + @as(i32, @intCast(i)) * row_h;
        if (i == home.selected) {
            try renderer.drawRect(list_x - 8, ry - 2, list_w + 16, row_h - 2, Color.rgb(
                @intCast(@min(255, @as(i32, bg.r) + 18)),
                @intCast(@min(255, @as(i32, bg.g) + 22)),
                @intCast(@min(255, @as(i32, bg.b) + 28)),
            ), 1.0);
            try renderer.drawRect(list_x - 8, ry - 2, 3, row_h - 2, Color.rgb(90, 175, 220), 1.0);
        }
        try renderer.drawText(list_x + 8, ry + 2, entry.label, fg);
        const key_x = list_x + list_w - @as(i32, @intCast(entry.key.len)) * cw;
        try renderer.drawText(key_x, ry + 2, entry.key, muted);
    }

    y += @as(i32, @intCast(entries.len)) * row_h + ch;

    var foot: [96]u8 = undefined;
    const foot_line = std.fmt.bufPrint(
        &foot,
        "~/.config/orbit  ·  {d} plugins  ·  up/down enter",
        .{plugin_count},
    ) catch "~/.config/orbit";
    const foot_x = cx - @divTrunc(@as(i32, @intCast(foot_line.len)) * cw, 2);
    if (y + ch < fb_h - ch) {
        try renderer.drawText(foot_x, y, foot_line, dim);
    }
}

fn drawHelp(
    renderer: *Renderer,
    fb_w: i32,
    fb_h: i32,
    cx: i32,
    bg: Color,
    fg: Color,
    muted: Color,
) !void {
    const cw = @as(i32, @intFromFloat(renderer.cell_w));
    const ch = @as(i32, @intFromFloat(renderer.cell_h));
    const panel_w: i32 = @min(cw * 48, fb_w - cw * 4);
    const lines = [_][]const u8{
        "Ctrl+Shift+P     Command palette",
        "Ctrl+= / - / 0   Font larger / smaller / reset",
        "Ctrl+Shift+T     New tab",
        "Ctrl+Shift+D/E   Split right / down",
        "Ctrl+Shift+O/S   Open / save workspace",
        "Ctrl+Shift+F     Search",
        "Ctrl+Shift+H     Home",
        "Cmd+W / Ctrl+Shift+W  Close tab",
        "Cmd+Q / Ctrl+Q   Quit Orbit",
        "",
        "~/.config/orbit/config.toml",
        "",
        "Esc  back",
    };
    const panel_h = ch * 2 + @as(i32, @intCast(lines.len)) * (ch + 4) + ch;
    const panel_x = cx - @divTrunc(panel_w, 2);
    const panel_y = @max(ch, @divTrunc(fb_h - panel_h, 2));

    try renderer.drawRect(panel_x, panel_y, panel_w, panel_h, Color.rgb(
        @intCast(@min(255, @as(i32, bg.r) + 8)),
        @intCast(@min(255, @as(i32, bg.g) + 8)),
        @intCast(@min(255, @as(i32, bg.b) + 10)),
    ), 1.0);
    try renderer.drawText(panel_x + cw, panel_y + @divTrunc(ch, 2), "Help", fg);

    var ly = panel_y + ch * 2;
    for (lines) |line| {
        if (line.len > 0) {
            try renderer.drawText(panel_x + cw, ly, line, muted);
        }
        ly += ch + 4;
    }
}
