//! Command palette — fuzzy filterable action list (Ctrl+Shift+P).

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
    save_workspace,
    search,
    ssh,
    theme_orbit_dark,
    theme_orbit_light,
    theme_nord,
    font_larger,
    font_smaller,
    font_reset,
    settings,
    reload_config,
};

pub const Entry = struct {
    action: Action,
    label: []const u8,
    hint: []const u8 = "",
};

pub const catalog = [_]Entry{
    .{ .action = .new_tab, .label = "New Tab", .hint = "Ctrl+Shift+T" },
    .{ .action = .close_tab, .label = "Close Tab", .hint = "Ctrl+Shift+W" },
    .{ .action = .split_right, .label = "Split Right", .hint = "Ctrl+Shift+D" },
    .{ .action = .split_down, .label = "Split Down", .hint = "Ctrl+Shift+E" },
    .{ .action = .next_tab, .label = "Next Tab", .hint = "Ctrl+Tab" },
    .{ .action = .prev_tab, .label = "Previous Tab", .hint = "Ctrl+Shift+Tab" },
    .{ .action = .focus_next_pane, .label = "Focus Next Pane", .hint = "Ctrl+PageDown" },
    .{ .action = .open_workspace, .label = "Open Workspace", .hint = "Ctrl+Shift+O" },
    .{ .action = .save_workspace, .label = "Save Workspace", .hint = "Ctrl+Shift+S" },
    .{ .action = .search, .label = "Search", .hint = "Ctrl+Shift+F" },
    .{ .action = .ssh, .label = "SSH…", .hint = "new tab + ssh" },
    .{ .action = .theme_orbit_dark, .label = "Theme: Orbit Dark", .hint = "" },
    .{ .action = .theme_orbit_light, .label = "Theme: Orbit Light", .hint = "" },
    .{ .action = .theme_nord, .label = "Theme: Nord", .hint = "" },
    .{ .action = .font_larger, .label = "Font: Larger", .hint = "" },
    .{ .action = .font_smaller, .label = "Font: Smaller", .hint = "" },
    .{ .action = .font_reset, .label = "Font: Reset Size", .hint = "" },
    .{ .action = .settings, .label = "Settings", .hint = "show config" },
    .{ .action = .reload_config, .label = "Reload Config", .hint = "" },
};

pub const Palette = struct {
    active: bool = false,
    query: [64]u8 = undefined,
    query_len: usize = 0,
    selected: usize = 0,
    /// Filtered indices into `catalog` (valid while active).
    matches: [catalog.len]usize = undefined,
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

    pub fn selectedAction(self: *const Palette) ?Action {
        if (self.match_count == 0 or self.selected >= self.match_count) return null;
        return catalog[self.matches[self.selected]].action;
    }

    pub fn refilter(self: *Palette) void {
        self.match_count = 0;
        const q = self.querySlice();
        for (catalog, 0..) |entry, i| {
            if (matchesFilter(entry.label, q) or matchesFilter(entry.hint, q)) {
                self.matches[self.match_count] = i;
                self.match_count += 1;
            }
        }
    }

    /// Case-insensitive subsequence match (type "nt" → "New Tab").
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

test "palette filters new tab" {
    var p: Palette = .{};
    p.open();
    p.inputChar('n');
    p.inputChar('t');
    try std.testing.expect(p.match_count >= 1);
    try std.testing.expect(p.selectedAction() == .new_tab or blk: {
        // "nt" may match multiple; ensure New Tab is among matches
        var found = false;
        var i: usize = 0;
        while (i < p.match_count) : (i += 1) {
            if (catalog[p.matches[i]].action == .new_tab) found = true;
        }
        break :blk found;
    });
}
