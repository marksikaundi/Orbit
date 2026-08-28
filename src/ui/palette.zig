//! Command palette — fuzzy filterable action list (Ctrl+Shift+P).
//! Combines built-in actions with plugin-registered commands.

const std = @import("std");

pub const Action = enum {
    new_tab,
    close_tab,
    split_right,
    split_down,
    next_tab,
    prev_tab,
    focus_next_pane,
    open_workspace,
    load_saved_workspace,
    save_workspace,
    search,
    open_file,
    ssh,
    theme_orbit_dark,
    theme_orbit_light,
    theme_nord,
    theme_dracula,
    theme_gruvbox,
    theme_solarized,
    cursor_block,
    cursor_underline,
    cursor_bar,
    cursor_blink_toggle,
    font_larger,
    font_smaller,
    font_reset,
    settings,
    go_home,
    quit,
    reload_config,
    reload_plugins,
    list_plugins,
};

pub const BuiltinEntry = struct {
    action: Action,
    label: []const u8,
    hint: []const u8 = "",
};

pub const catalog = [_]BuiltinEntry{
    .{ .action = .new_tab, .label = "New Tab", .hint = "Ctrl+Shift+T" },
    .{ .action = .close_tab, .label = "Close Tab", .hint = "Ctrl+Shift+W" },
    .{ .action = .split_right, .label = "Split Right", .hint = "Ctrl+Shift+D" },
    .{ .action = .split_down, .label = "Split Down", .hint = "Ctrl+Shift+E" },
    .{ .action = .next_tab, .label = "Next Tab", .hint = "Ctrl+Tab" },
    .{ .action = .prev_tab, .label = "Previous Tab", .hint = "Ctrl+Shift+Tab" },
    .{ .action = .focus_next_pane, .label = "Focus Next Pane", .hint = "Ctrl+PageDown" },
    .{ .action = .open_workspace, .label = "Open Workspace", .hint = "Ctrl+Shift+O" },
    .{ .action = .load_saved_workspace, .label = "Load Saved Workspace", .hint = "saved" },
    .{ .action = .save_workspace, .label = "Save Workspace", .hint = "Ctrl+Shift+S" },
    .{ .action = .search, .label = "Search", .hint = "Ctrl+Shift+F" },
    .{ .action = .open_file, .label = "Open File", .hint = "edit" },
    .{ .action = .ssh, .label = "SSH…", .hint = "ssh host" },
    .{ .action = .theme_orbit_dark, .label = "Theme: Orbit Dark", .hint = "" },
    .{ .action = .theme_orbit_light, .label = "Theme: Orbit Light", .hint = "" },
    .{ .action = .theme_nord, .label = "Theme: Nord", .hint = "" },
    .{ .action = .theme_dracula, .label = "Theme: Dracula", .hint = "" },
    .{ .action = .theme_gruvbox, .label = "Theme: Gruvbox Dark", .hint = "" },
    .{ .action = .theme_solarized, .label = "Theme: Solarized Dark", .hint = "" },
    .{ .action = .cursor_block, .label = "Cursor: Block", .hint = "" },
    .{ .action = .cursor_underline, .label = "Cursor: Underline", .hint = "" },
    .{ .action = .cursor_bar, .label = "Cursor: Bar", .hint = "" },
    .{ .action = .cursor_blink_toggle, .label = "Cursor: Toggle Blink", .hint = "" },
    .{ .action = .font_larger, .label = "Font: Larger", .hint = "Ctrl+=" },
    .{ .action = .font_smaller, .label = "Font: Smaller", .hint = "Ctrl+-" },
    .{ .action = .font_reset, .label = "Font: Reset Size", .hint = "Ctrl+0" },
    .{ .action = .settings, .label = "Appearance Settings", .hint = "S" },
    .{ .action = .go_home, .label = "Go Home", .hint = "Ctrl+Shift+H" },
    .{ .action = .quit, .label = "Quit Orbit", .hint = "Ctrl+Q" },
    .{ .action = .reload_config, .label = "Reload Config", .hint = "" },
    .{ .action = .reload_plugins, .label = "Reload Plugins", .hint = "" },
    .{ .action = .list_plugins, .label = "Plugins…", .hint = "L on home" },
};

pub const Item = struct {
    label: []const u8,
    hint: []const u8,
    source: union(enum) {
        builtin: Action,
        plugin: struct {
            plugin_name: []const u8,
            command_id: []const u8,
        },
    },
};

pub const max_items = 128;

pub const Palette = struct {
    active: bool = false,
    query: [64]u8 = undefined,
    query_len: usize = 0,
    selected: usize = 0,
    items: [max_items]Item = undefined,
    item_count: usize = 0,
    matches: [max_items]usize = undefined,
    match_count: usize = 0,

    pub fn open(self: *Palette) void {
        self.active = true;
        self.query_len = 0;
        self.selected = 0;
        self.refilter();
    }

    pub fn close(self: *Palette) void {
        self.active = false;
        self.query_len = 0;
        self.match_count = 0;
    }

    pub fn querySlice(self: *const Palette) []const u8 {
        return self.query[0..self.query_len];
    }

    pub fn clearItems(self: *Palette) void {
        self.item_count = 0;
    }

    pub fn addBuiltin(self: *Palette, entry: BuiltinEntry) void {
        if (self.item_count >= max_items) return;
        self.items[self.item_count] = .{
            .label = entry.label,
            .hint = entry.hint,
            .source = .{ .builtin = entry.action },
        };
        self.item_count += 1;
    }

    pub fn addPluginCommand(self: *Palette, label: []const u8, hint: []const u8, plugin_name: []const u8, command_id: []const u8) void {
        if (self.item_count >= max_items) return;
        self.items[self.item_count] = .{
            .label = label,
            .hint = hint,
            .source = .{ .plugin = .{ .plugin_name = plugin_name, .command_id = command_id } },
        };
        self.item_count += 1;
    }

    pub fn addAllBuiltins(self: *Palette) void {
        for (catalog) |e| self.addBuiltin(e);
    }

    pub fn inputChar(self: *Palette, codepoint: u32) void {
        if (!self.active) return;
        if (codepoint < 32 or codepoint > 126) return;
        if (self.query_len + 1 >= self.query.len) return;
        self.query[self.query_len] = @intCast(codepoint);
        self.query_len += 1;
        self.refilter();
        self.selected = 0;
    }

    pub fn backspace(self: *Palette) void {
        if (self.query_len > 0) self.query_len -= 1;
        self.refilter();
        if (self.selected >= self.match_count and self.match_count > 0) {
            self.selected = self.match_count - 1;
        } else if (self.match_count == 0) {
            self.selected = 0;
        }
    }

    pub fn moveUp(self: *Palette) void {
        if (self.selected > 0) self.selected -= 1;
    }

    pub fn moveDown(self: *Palette) void {
        if (self.match_count > 0 and self.selected + 1 < self.match_count) {
            self.selected += 1;
        }
    }

    pub fn selectedItem(self: *const Palette) ?Item {
        if (self.match_count == 0 or self.selected >= self.match_count) return null;
        return self.items[self.matches[self.selected]];
    }

    pub fn refilter(self: *Palette) void {
        self.match_count = 0;
        const q = self.querySlice();
        var i: usize = 0;
        while (i < self.item_count) : (i += 1) {
            const entry = self.items[i];
            if (matchesFilter(entry.label, q) or matchesFilter(entry.hint, q)) {
                self.matches[self.match_count] = i;
                self.match_count += 1;
            }
        }
    }

    fn matchesFilter(text: []const u8, query: []const u8) bool {
        if (query.len == 0) return true;
        var ti: usize = 0;
        for (query) |qc| {
            const want = toLower(qc);
            var found = false;
            while (ti < text.len) : (ti += 1) {
                if (toLower(text[ti]) == want) {
                    ti += 1;
                    found = true;
                    break;
                }
            }
            if (!found) return false;
        }
        return true;
    }

    fn toLower(ch: u8) u8 {
        if (ch >= 'A' and ch <= 'Z') return ch + 32;
        return ch;
    }
};
