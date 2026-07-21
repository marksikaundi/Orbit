//! Startup home — minimal Ghostty-like welcome (no heavy chrome).

const std = @import("std");
const Renderer = @import("../renderer/renderer.zig").Renderer;
const Color = @import("../terminal/cell.zig").Color;
const app_version = @import("../version.zig");

pub const version = app_version.string;

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

/// One row in the Help & Shortcuts overlay.
pub const HelpRow = union(enum) {
    heading: []const u8,
    item: struct { keys: []const u8, desc: []const u8 },
    note: []const u8,
    spacer,
};

/// Full keyboard / usage reference (scrollable in the Help overlay).
pub const help_rows = [_]HelpRow{
    .{ .heading = "Home screen" },
    .{ .item = .{ .keys = "Enter / 1", .desc = "Open a new terminal tab" } },
    .{ .item = .{ .keys = "O / 2", .desc = "Open a folder as workspace" } },
    .{ .item = .{ .keys = "P / 3", .desc = "Open the command palette" } },
    .{ .item = .{ .keys = "S / 4", .desc = "Show settings / config paths" } },
    .{ .item = .{ .keys = "H / 5", .desc = "Open this Help reference" } },
    .{ .item = .{ .keys = "Q / 6", .desc = "Quit Orbit" } },
    .{ .item = .{ .keys = "↑ ↓", .desc = "Move selection" } },
    .{ .spacer = {} },

    .{ .heading = "App — quit & close" },
    .{ .item = .{ .keys = "Cmd+Q / Ctrl+Q", .desc = "Quit Orbit (works anywhere)" } },
    .{ .item = .{ .keys = "Cmd+W", .desc = "Close tab; on home → quit" } },
    .{ .item = .{ .keys = "Ctrl+Shift+W", .desc = "Same as Cmd+W" } },
    .{ .item = .{ .keys = "exit / Ctrl+D", .desc = "End the shell; closes that tab" } },
    .{ .item = .{ .keys = "Window ✕", .desc = "Close the Orbit window" } },
    .{ .spacer = {} },

    .{ .heading = "Navigation" },
    .{ .item = .{ .keys = "Ctrl+Shift+H", .desc = "Return to the home screen" } },
    .{ .item = .{ .keys = "Ctrl+Shift+P", .desc = "Command palette (fuzzy actions)" } },
    .{ .item = .{ .keys = "Esc", .desc = "Close overlay / dialog / Help" } },
    .{ .spacer = {} },

    .{ .heading = "Tabs" },
    .{ .item = .{ .keys = "Ctrl+Shift+T", .desc = "New tab" } },
    .{ .item = .{ .keys = "Ctrl+Tab", .desc = "Next tab" } },
    .{ .item = .{ .keys = "Ctrl+Shift+Tab", .desc = "Previous tab" } },
    .{ .item = .{ .keys = "Ctrl+Shift+]", .desc = "Next tab" } },
    .{ .item = .{ .keys = "Ctrl+Shift+[", .desc = "Previous tab" } },
    .{ .spacer = {} },

    .{ .heading = "Splits & panes" },
    .{ .item = .{ .keys = "Ctrl+Shift+D", .desc = "Split pane right (horizontal)" } },
    .{ .item = .{ .keys = "Ctrl+Shift+E", .desc = "Split pane down (vertical)" } },
    .{ .item = .{ .keys = "Ctrl+PageDown", .desc = "Focus the next pane" } },
    .{ .spacer = {} },

    .{ .heading = "Font size" },
    .{ .item = .{ .keys = "Ctrl+= / Cmd+=", .desc = "Larger (+1pt)" } },
    .{ .item = .{ .keys = "Ctrl+- / Cmd+-", .desc = "Smaller (−1pt)" } },
    .{ .item = .{ .keys = "Ctrl+0 / Cmd+0", .desc = "Reset to 14pt" } },
    .{ .spacer = {} },

    .{ .heading = "Clipboard & search" },
    .{ .item = .{ .keys = "Cmd+Shift+C", .desc = "Copy selection" } },
    .{ .item = .{ .keys = "Ctrl+Shift+C", .desc = "Copy selection" } },
    .{ .item = .{ .keys = "Cmd+Shift+V", .desc = "Paste from clipboard" } },
    .{ .item = .{ .keys = "Ctrl+Shift+V", .desc = "Paste from clipboard" } },
    .{ .item = .{ .keys = "Ctrl+Shift+F", .desc = "Search in the active screen" } },
    .{ .item = .{ .keys = "Enter", .desc = "Find next (while searching)" } },
    .{ .item = .{ .keys = "Esc", .desc = "Close search" } },
    .{ .spacer = {} },

    .{ .heading = "Workspaces" },
    .{ .item = .{ .keys = "Ctrl+Shift+O", .desc = "Open a folder from disk (native picker)" } },
    .{ .item = .{ .keys = "Ctrl+Shift+S", .desc = "Save current tabs/splits" } },
    .{ .item = .{ .keys = "Palette → Load Saved", .desc = "Restore a previously saved layout" } },
    .{ .item = .{ .keys = "↑ ↓ Enter", .desc = "Choose a saved workspace" } },
    .{ .item = .{ .keys = "Delete", .desc = "Delete selected saved workspace" } },
    .{ .spacer = {} },

    .{ .heading = "Terminal scrollback" },
    .{ .item = .{ .keys = "Page Up", .desc = "Scroll view up" } },
    .{ .item = .{ .keys = "Page Down", .desc = "Scroll view down" } },
    .{ .item = .{ .keys = "Mouse wheel", .desc = "Scroll the active pane" } },
    .{ .spacer = {} },

    .{ .heading = "Command palette" },
    .{ .item = .{ .keys = "Type", .desc = "Filter actions & plugin commands" } },
    .{ .item = .{ .keys = "↑ ↓", .desc = "Move selection" } },
    .{ .item = .{ .keys = "Enter", .desc = "Run the selected action" } },
    .{ .item = .{ .keys = "Backspace", .desc = "Edit the filter" } },
    .{ .item = .{ .keys = "Esc", .desc = "Close palette" } },
    .{ .note = "Includes themes, font, reload config/plugins, SSH…" },
    .{ .spacer = {} },

    .{ .heading = "Appearance" },
    .{ .item = .{ .keys = "S / Settings", .desc = "Theme, text color, cursor, shell (Left/Right to change)" } },
    .{ .item = .{ .keys = "Ctrl+Shift+P", .desc = "Palette -> Theme: ... / Cursor: ..." } },
    .{ .note = "Prompt text (zsh/bash) comes from your shell rc — Orbit styles colors & cursor" },
    .{ .spacer = {} },

    .{ .heading = "Config & plugins" },
    .{ .item = .{ .keys = "config.toml", .desc = "~/.config/orbit/config.toml" } },
    .{ .item = .{ .keys = "plugins/", .desc = "~/.config/orbit/plugins/<name>/" } },
    .{ .note = "Palette → Reload Config / Reload Plugins after edits" },
    .{ .spacer = {} },

    .{ .heading = "This Help panel" },
    .{ .item = .{ .keys = "↑ ↓", .desc = "Scroll one line" } },
    .{ .item = .{ .keys = "Page Up/Down", .desc = "Scroll a page" } },
    .{ .item = .{ .keys = "Mouse wheel", .desc = "Scroll" } },
    .{ .item = .{ .keys = "Esc / H", .desc = "Close Help" } },
};

pub const Home = struct {
    selected: usize = 0,
    show_help: bool = false,
    help_scroll: usize = 0,

    pub fn moveUp(self: *Home) void {
        if (self.show_help) {
            self.scrollHelp(-1);
            return;
        }
        if (self.selected > 0) self.selected -= 1;
    }

    pub fn moveDown(self: *Home) void {
        if (self.show_help) {
            self.scrollHelp(1);
            return;
        }
        if (self.selected + 1 < entries.len) self.selected += 1;
    }

    pub fn openHelp(self: *Home) void {
        self.show_help = true;
        self.help_scroll = 0;
    }

    pub fn closeHelp(self: *Home) void {
        self.show_help = false;
        self.help_scroll = 0;
    }

    pub fn scrollHelp(self: *Home, delta: i32) void {
        if (!self.show_help) return;
        // Clamp against full catalog; drawHelp trims to the visible window.
        const max: usize = if (help_rows.len == 0) 0 else help_rows.len -| 1;
        if (delta < 0) {
            const steps: usize = @intCast(-delta);
            self.help_scroll -|= steps;
        } else if (delta > 0) {
            const steps: usize = @intCast(delta);
            if (self.help_scroll >= max) {
                self.help_scroll = max;
            } else {
                self.help_scroll = @min(self.help_scroll + steps, max);
            }
        }
    }

    pub fn selectedAction(self: *const Home) Action {
        return entries[self.selected].action;
    }
};

fn helpScrollMax(visible: usize) usize {
    if (help_rows.len <= visible) return 0;
    return help_rows.len - visible;
}

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
        try drawHelp(renderer, fb_w, fb_h, cx, home.help_scroll, bg, fg, muted, dim);
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
    if (y + ch < fb_h - ch * 3) {
        try renderer.drawText(foot_x, y, foot_line, dim);
    }

    const credit = "Created by Mark Sikaundi - Lupleg Studios";
    const credit_x = cx - @divTrunc(@as(i32, @intCast(credit.len)) * cw, 2);
    const credit_y = fb_h - ch * 2;
    try renderer.drawText(credit_x, credit_y, credit, dim);
}

fn drawHelp(
    renderer: *Renderer,
    fb_w: i32,
    fb_h: i32,
    cx: i32,
    scroll: usize,
    bg: Color,
    fg: Color,
    muted: Color,
    dim: Color,
) !void {
    const cw = @as(i32, @intFromFloat(renderer.cell_w));
    const ch = @as(i32, @intFromFloat(renderer.cell_h));
    const accent = Color.rgb(90, 175, 220);
    const panel_w: i32 = @min(cw * 56, fb_w - cw * 2);
    const panel_x = cx - @divTrunc(panel_w, 2);
    const panel_y = @max(ch, @divTrunc(fb_h, 12));
    const panel_h = fb_h - panel_y - ch;
    const header_h = ch * 2;
    const footer_h = ch + 4;
    const row_gap = 2;
    const row_h = ch + row_gap;
    const body_h = panel_h - header_h - footer_h;
    const visible: usize = @intCast(@max(1, @divTrunc(body_h, row_h)));
    const max_scroll = helpScrollMax(visible);
    const start = @min(scroll, max_scroll);
    const end = @min(start + visible, help_rows.len);

    try renderer.drawRect(panel_x, panel_y, panel_w, panel_h, Color.rgb(
        @intCast(@min(255, @as(i32, bg.r) + 8)),
        @intCast(@min(255, @as(i32, bg.g) + 8)),
        @intCast(@min(255, @as(i32, bg.b) + 10)),
    ), 1.0);

    try renderer.drawText(panel_x + cw, panel_y + @divTrunc(ch, 2), "Help & Shortcuts", fg);
    var hint_buf: [48]u8 = undefined;
    const hint = std.fmt.bufPrint(
        &hint_buf,
        "{d}–{d} / {d}",
        .{ start + 1, end, help_rows.len },
    ) catch "";
    const hint_x = panel_x + panel_w - cw - @as(i32, @intCast(hint.len)) * cw;
    try renderer.drawText(hint_x, panel_y + @divTrunc(ch, 2), hint, dim);

    const keys_col_w = cw * 22;
    var ly = panel_y + header_h;
    var i = start;
    while (i < end) : (i += 1) {
        const row = help_rows[i];
        switch (row) {
            .heading => |title| {
                try renderer.drawText(panel_x + cw, ly, title, accent);
            },
            .item => |it| {
                try renderer.drawText(panel_x + cw, ly, it.keys, fg);
                const desc_x = panel_x + cw + keys_col_w;
                const max_desc = @max(0, @divTrunc(panel_x + panel_w - cw - desc_x, cw));
                if (it.desc.len > 0 and max_desc > 0) {
                    const shown = it.desc[0..@min(it.desc.len, @as(usize, @intCast(max_desc)))];
                    try renderer.drawText(desc_x, ly, shown, muted);
                }
            },
            .note => |text| {
                try renderer.drawText(panel_x + cw, ly, text, dim);
            },
            .spacer => {},
        }
        ly += row_h;
    }

    const foot = "↑↓ / wheel scroll   Esc or H close";
    try renderer.drawText(panel_x + cw, panel_y + panel_h - footer_h, foot, dim);
}
