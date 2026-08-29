//! Startup home — minimal Ghostty-like welcome (no heavy chrome).

const std = @import("std");
const Renderer = @import("../renderer/renderer.zig").Renderer;
const Color = @import("../terminal/cell.zig").Color;
const app_version = @import("../version.zig");
const ui_scale = @import("scale.zig");
const ui_chrome = @import("chrome.zig");

pub const version = app_version.string;

pub const Action = enum {
    new_terminal,
    open_workspace,
    command_palette,
    settings,
    plugins,
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
    .{ .action = .plugins, .label = "Plugins", .key = "L" },
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
    .{ .item = .{ .keys = "L / 5", .desc = "Plugins — format, lint, AI, shortcuts, themes you own" } },
    .{ .item = .{ .keys = "H / 6", .desc = "Open this Help reference" } },
    .{ .item = .{ .keys = "Q / 7", .desc = "Quit Orbit" } },
    .{ .item = .{ .keys = "↑ ↓", .desc = "Move selection" } },
    .{ .spacer = {} },

    .{ .heading = "App — quit & close" },
    .{ .item = .{ .keys = "Cmd+Q / Ctrl+Q", .desc = "Quit Orbit (works anywhere)" } },
    .{ .item = .{ .keys = "Cmd+W", .desc = "Close tab; on home → quit" } },
    .{ .item = .{ .keys = "Ctrl+Shift+W", .desc = "Close tab (same as Cmd+W)" } },
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
    .{ .item = .{ .keys = "Cmd+C / Cmd+V", .desc = "Copy / paste (macOS)" } },
    .{ .item = .{ .keys = "Ctrl+C", .desc = "Copy selection (Windows/Linux; else interrupt)" } },
    .{ .item = .{ .keys = "Ctrl+V", .desc = "Paste (Windows/Linux)" } },
    .{ .item = .{ .keys = "Ctrl/Cmd+Shift+C / V", .desc = "Copy / paste (all platforms)" } },
    .{ .item = .{ .keys = "Right-click", .desc = "Copy / Paste context menu" } },
    .{ .item = .{ .keys = "Cmd/Ctrl+Shift+F", .desc = "Search terminal, file names, or code in files" } },
    .{ .item = .{ .keys = "Tab", .desc = "Switch Terminal / Files / Code in search" } },
    .{ .item = .{ .keys = "Enter (Files / Code)", .desc = "Open the file in the editor (Code jumps to the line)" } },
    .{ .item = .{ .keys = "Shift+Enter (Files)", .desc = "Insert the file path into the shell" } },
    .{ .item = .{ .keys = "Up/Down Enter", .desc = "Move hits / jump to a terminal match" } },
    .{ .item = .{ .keys = "Esc", .desc = "Close search" } },
    .{ .spacer = {} },

    .{ .heading = "File editor" },
    .{ .item = .{ .keys = "Palette → Open File", .desc = "Open a file with language colors, then type to edit" } },
    .{ .item = .{ .keys = "Type / arrows", .desc = "Insert text and move the caret" } },
    .{ .item = .{ .keys = "Autocomplete popup", .desc = "Keywords, common APIs, and names already in the file (with a short meaning)" } },
    .{ .item = .{ .keys = "Ctrl+Space", .desc = "Show completions (Tab or Enter to insert)" } },
    .{ .item = .{ .keys = "⌘/Ctrl+S", .desc = "Save the file" } },
    .{ .item = .{ .keys = "⌘/Ctrl+F", .desc = "Find text in the open file (Enter next, Esc close find)" } },
    .{ .item = .{ .keys = "⌘/Ctrl+Shift+F", .desc = "Search code across files, then Enter to open at the line" } },
    .{ .item = .{ .keys = "Esc", .desc = "Close the editor (twice if unsaved)" } },
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
    .{ .item = .{ .keys = "S / Settings", .desc = "Theme, look, opacity, padding, prompt, shell" } },
    .{ .item = .{ .keys = "Left/Right", .desc = "Change the selected Appearance value" } },
    .{ .item = .{ .keys = "Ctrl+=/-/0", .desc = "Font size up / down / reset (everywhere)" } },
    .{ .item = .{ .keys = "Ctrl+Shift+P", .desc = "Palette -> Theme: ... / Cursor: ..." } },
    .{ .note = "Look: compact / comfortable / airy / glass (Ghostty-style padding + opacity)" },
    .{ .spacer = {} },

    .{ .heading = "Custom keybindings" },
    .{ .item = .{ .keys = "keybind =", .desc = "Ghostty syntax in config.toml: trigger=action" } },
    .{ .item = .{ .keys = "ctrl+shift+t=new_tab", .desc = "Example — modifiers + key = action" } },
    .{ .item = .{ .keys = "unbind / clear", .desc = "Remove one chord, or wipe all defaults first" } },
    .{ .item = .{ .keys = "ctrl+a>n", .desc = "Sequence (leader then key)" } },
    .{ .item = .{ .keys = "text: / csi: / esc:", .desc = "Send bytes to the shell" } },
    .{ .item = .{ .keys = "performable:", .desc = "Only consume the key if the action can run (e.g. copy)" } },
    .{ .note = "Edit ~/.config/orbit/config.toml — Reload Config in the palette. User guide: docs/" },
    .{ .spacer = {} },
    .{ .item = .{ .keys = "L / Plugins", .desc = "Manage plugins: format, lint, AI, shortcuts, themes" } },
    .{ .item = .{ .keys = "I", .desc = "Install / update the bundled plugin pack" } },
    .{ .item = .{ .keys = "U / Delete", .desc = "Uninstall the selected plugin from disk" } },
    .{ .item = .{ .keys = "Space", .desc = "Enable / disable selected plugin" } },
    .{ .item = .{ .keys = "R", .desc = "Reload plugins from ~/.config/orbit/plugins/" } },
    .{ .item = .{ .keys = "Ctrl+Shift+I", .desc = "Format the open file (format plugin)" } },
    .{ .item = .{ .keys = "Ctrl+Shift+A", .desc = "AI: Explain selection (ai plugin; never auto-runs)" } },
    .{ .item = .{ .keys = "shortcut=", .desc = "In plugin.toml: your own key chords" } },
    .{ .item = .{ .keys = "[tool]", .desc = "Run your formatter, linter, or AI CLI" } },
    .{ .item = .{ .keys = "plugins/", .desc = "~/.config/orbit/plugins/<name>/" } },
    .{ .item = .{ .keys = "config.toml", .desc = "~/.config/orbit/config.toml — appearance + keybind =" } },
    .{ .note = "Plugins are yours — edit the script, press R" },
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
    const chrome = ui_chrome.fromTheme(renderer.theme);
    const bg = chrome.bg;
    const fg = chrome.fg;
    const muted = chrome.muted;
    const dim = chrome.dim;
    const accent = chrome.accent;

    try renderer.drawRect(0, 0, fb_w, fb_h, bg, 1.0);

    // Grow with framebuffer so fullscreen isn't a tiny island of terminal-sized text.
    const ui = ui_scale.uiScale(fb_w, fb_h, renderer.content_scale);
    const base_cw = @as(i32, @intFromFloat(renderer.cell_w));
    const base_ch = @as(i32, @intFromFloat(renderer.cell_h));
    const body: f32 = ui;
    // Keep brand close to body size — heavy stretch looked soft/warped on Retina.
    const brand_s: f32 = ui * 1.35;
    const tag_s: f32 = ui * 1.1;
    const cw = ui_scale.scaled(base_cw, body);
    const ch = ui_scale.scaled(base_ch, body);
    const brand_cw = ui_scale.scaled(base_cw, brand_s);
    const brand_ch = ui_scale.scaled(base_ch, brand_s);
    const tag_cw = ui_scale.scaled(base_cw, tag_s);
    const tag_ch = ui_scale.scaled(base_ch, tag_s);
    const cx = @divTrunc(fb_w, 2);

    if (home.show_help) {
        try drawHelp(renderer, fb_w, fb_h, cx, home.help_scroll, fg, muted, dim, body);
        return;
    }

    const brand = "Orbit";
    const tag = "Stay in the flow.";
    const row_h = ch + @divTrunc(ch, 2);
    const list_w: i32 = @min(cw * 34, fb_w - cw * 4);
    const logo_size = @max(ch * 5, @as(i32, @intFromFloat(@round(72.0 * ui))));

    // Approximate stacked height so we can vertically center on tall displays.
    const block_h = logo_size + brand_ch + tag_ch + ch * 3 + row_h * @as(i32, @intCast(entries.len)) + ch * 5;
    const pad_y = @max(ch * 2, @divTrunc(fb_h - block_h, 3));
    var y = @min(@max(ch * 2, pad_y), @divTrunc(fb_h, 4));

    // Brand logo — hero visual (Orbit app icon)
    try renderer.drawLogo(cx, y, logo_size);
    y += logo_size + @divTrunc(ch, 2);

    // Brand wordmark
    const brand_x = cx - @divTrunc(@as(i32, @intCast(brand.len)) * brand_cw, 2);
    try renderer.drawTextScaled(brand_x, y, brand, fg, brand_s);
    y += brand_ch + @divTrunc(ch, 3);

    const tag_x = cx - @divTrunc(@as(i32, @intCast(tag.len)) * tag_cw, 2);
    try renderer.drawTextScaled(tag_x, y, tag, muted, tag_s);
    y += tag_ch + @divTrunc(ch, 2);

    var meta: [96]u8 = undefined;
    const meta_line = std.fmt.bufPrint(
        &meta,
        "v{s}  {s}  {d:.0}pt",
        .{ version, theme_name, font_size },
    ) catch "v0.1.0";
    const meta_x = cx - @divTrunc(@as(i32, @intCast(meta_line.len)) * cw, 2);
    try renderer.drawTextScaled(meta_x, y, meta_line, dim, body);
    y += ch * 2;

    // Action list
    const list_x = cx - @divTrunc(list_w, 2);
    try renderer.drawTextScaled(list_x, y, "What would you like to do?", muted, body);
    y += ch + @divTrunc(ch, 2);

    for (entries, 0..) |entry, i| {
        const ry = y + @as(i32, @intCast(i)) * row_h;
        if (i == home.selected) {
            try renderer.drawRect(list_x - 10, ry - 4, list_w + 20, row_h - 2, chrome.sel_bg, 1.0);
            try renderer.drawRect(list_x - 10, ry - 4, @max(3, @divTrunc(cw, 3)), row_h - 2, accent, 1.0);
        }
        try renderer.drawTextScaled(list_x + 10, ry + 2, entry.label, fg, body);
        const key_x = list_x + list_w - @as(i32, @intCast(entry.key.len)) * cw;
        try renderer.drawTextScaled(key_x, ry + 2, entry.key, muted, body);
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
        try renderer.drawTextScaled(foot_x, y, foot_line, dim, body);
    }

    const credit = "Created by Mark Sikaundi - Lupleg Studios";
    const credit_x = cx - @divTrunc(@as(i32, @intCast(credit.len)) * cw, 2);
    const credit_y = fb_h - ch * 2;
    try renderer.drawTextScaled(credit_x, credit_y, credit, dim, body);
}

fn drawHelp(
    renderer: *Renderer,
    fb_w: i32,
    fb_h: i32,
    cx: i32,
    scroll: usize,
    fg: Color,
    muted: Color,
    dim: Color,
    ui: f32,
) !void {
    const base_cw = @as(i32, @intFromFloat(renderer.cell_w));
    const base_ch = @as(i32, @intFromFloat(renderer.cell_h));
    const cw = ui_scale.scaled(base_cw, ui);
    const ch = ui_scale.scaled(base_ch, ui);
    const chrome = ui_chrome.fromTheme(renderer.theme);
    const accent = chrome.accent;
    const panel_w = ui_scale.panelWidth(fb_w, cw, 52, 560);
    const panel_x = cx - @divTrunc(panel_w, 2);
    const panel_y = @max(ch, @divTrunc(fb_h, 14));
    const panel_h = fb_h - panel_y - ch;
    const header_h = ch * 2;
    const footer_h = ch + 4;
    const row_gap = @max(2, @divTrunc(ch, 6));
    const row_h = ch + row_gap;
    const body_h = panel_h - header_h - footer_h;
    const visible: usize = @intCast(@max(1, @divTrunc(body_h, row_h)));
    const max_scroll = helpScrollMax(visible);
    const start = @min(scroll, max_scroll);
    const end = @min(start + visible, help_rows.len);

    try renderer.drawRect(panel_x, panel_y, panel_w, panel_h, chrome.panel, 1.0);

    try renderer.drawTextScaled(panel_x + cw, panel_y + @divTrunc(ch, 2), "Help & Shortcuts", fg, ui);
    var hint_buf: [48]u8 = undefined;
    const hint = std.fmt.bufPrint(
        &hint_buf,
        "{d}–{d} / {d}",
        .{ start + 1, end, help_rows.len },
    ) catch "";
    const hint_x = panel_x + panel_w - cw - @as(i32, @intCast(hint.len)) * cw;
    try renderer.drawTextScaled(hint_x, panel_y + @divTrunc(ch, 2), hint, dim, ui);

    const keys_col_w = cw * 20;
    var ly = panel_y + header_h;
    var i = start;
    while (i < end) : (i += 1) {
        const row = help_rows[i];
        switch (row) {
            .heading => |title| {
                try renderer.drawTextScaled(panel_x + cw, ly, title, accent, ui);
            },
            .item => |it| {
                try renderer.drawTextScaled(panel_x + cw, ly, it.keys, fg, ui);
                const desc_x = panel_x + cw + keys_col_w;
                const max_desc = @max(0, @divTrunc(panel_x + panel_w - cw - desc_x, cw));
                if (it.desc.len > 0 and max_desc > 0) {
                    const shown = it.desc[0..@min(it.desc.len, @as(usize, @intCast(max_desc)))];
                    try renderer.drawTextScaled(desc_x, ly, shown, muted, ui);
                }
            },
            .note => |text| {
                try renderer.drawTextScaled(panel_x + cw, ly, text, dim, ui);
            },
            .spacer => {},
        }
        ly += row_h;
    }

    const foot = "↑↓ / wheel scroll   Esc or H close";
    try renderer.drawTextScaled(panel_x + cw, panel_y + panel_h - footer_h, foot, dim, ui);
}

