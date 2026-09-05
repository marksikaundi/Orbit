//! Ghostty-compatible custom keybindings.
//!
//! Config form (same as https://ghostty.org/docs/config/keybind):
//!
//!     keybind = trigger=action
//!
//! Examples:
//!     keybind = ctrl+shift+t=new_tab
//!     keybind = performable:ctrl+c=copy_to_clipboard
//!     keybind = ctrl+a>n=new_tab
//!     keybind = ctrl+k=unbind
//!     keybind = clear
//!     keybind = chain=reload_config

const std = @import("std");
const builtin = @import("builtin");
const bindings = @import("../ui/bindings.zig");
const palette_mod = @import("../ui/palette.zig");

pub const Mods = bindings.Mods;
pub const AppAction = palette_mod.Action;

pub const max_sequence: u8 = 4;
pub const max_chain: u8 = 8;
pub const max_bindings: usize = 256;

pub const Prefixes = struct {
    /// Send to every surface (parsed; Orbit runs the action once).
    all: bool = false,
    /// OS-global shortcut (parsed; requires platform support — ignored for now).
    global: bool = false,
    /// Run the action and still encode the key to the PTY.
    unconsumed: bool = false,
    /// Only consume the key if the action can run (e.g. copy with a selection).
    performable: bool = false,
};

pub const Trigger = struct {
    mods: Mods = .{},
    key: [32]u8 = undefined,
    key_len: u8 = 0,
    catch_all: bool = false,

    pub fn from(mods: Mods, name: []const u8) Trigger {
        var t: Trigger = .{ .mods = mods };
        t.setKey(name);
        return t;
    }

    pub fn setKey(self: *Trigger, name: []const u8) void {
        const norm = normalizeKey(name);
        if (eql(norm, "catch_all") or eql(norm, "catchall")) {
            self.catch_all = true;
            self.key_len = 0;
            return;
        }
        const n = @min(norm.len, self.key.len);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            self.key[i] = std.ascii.toLower(norm[i]);
        }
        self.key_len = @intCast(n);
        self.catch_all = false;
    }

    pub fn keySlice(self: *const Trigger) []const u8 {
        return self.key[0..self.key_len];
    }

    pub fn matches(self: Trigger, actual: Trigger) bool {
        if (self.mods.ctrl != actual.mods.ctrl) return false;
        if (self.mods.shift != actual.mods.shift) return false;
        if (self.mods.super != actual.mods.super) return false;
        if (self.mods.alt != actual.mods.alt) return false;
        if (self.catch_all) return true;
        if (actual.catch_all) return false;
        return std.ascii.eqlIgnoreCase(self.keySlice(), actual.keySlice());
    }
};

pub const Action = union(enum) {
    ignore,
    unbind,
    app: AppAction,
    text: []u8,
    csi: []u8,
    esc: []u8,

    pub fn deinit(self: *Action, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .text, .csi, .esc => |s| allocator.free(s),
            else => {},
        }
        self.* = .ignore;
    }
};

pub const Binding = struct {
    sequence: [max_sequence]Trigger = undefined,
    sequence_len: u8 = 1,
    prefixes: Prefixes = .{},
    actions: [max_chain]Action = undefined,
    action_len: u8 = 1,

    pub fn deinit(self: *Binding, allocator: std.mem.Allocator) void {
        var i: u8 = 0;
        while (i < self.action_len) : (i += 1) {
            self.actions[i].deinit(allocator);
        }
        self.action_len = 0;
    }

    pub fn sequenceSlice(self: *const Binding) []const Trigger {
        return self.sequence[0..self.sequence_len];
    }

    pub fn actionsSlice(self: *const Binding) []const Action {
        return self.actions[0..self.action_len];
    }

    pub fn isQuitOrClose(self: *const Binding) bool {
        if (self.action_len == 0) return false;
        return switch (self.actions[0]) {
            .app => |a| a == .quit or a == .close_tab,
            else => false,
        };
    }
};

pub const Advance = union(enum) {
    fire: *const Binding,
    wait,
    miss,
};

pub const Keymap = struct {
    bindings: std.ArrayList(Binding) = .empty,

    pub fn deinit(self: *Keymap, allocator: std.mem.Allocator) void {
        for (self.bindings.items) |*b| b.deinit(allocator);
        self.bindings.deinit(allocator);
        self.bindings = .empty;
    }

    pub fn clear(self: *Keymap, allocator: std.mem.Allocator) void {
        for (self.bindings.items) |*b| b.deinit(allocator);
        self.bindings.clearRetainingCapacity();
    }

    /// Built-in chords + clipboard / palette / scroll (Ghostty-style names).
    pub fn loadDefaults(self: *Keymap, allocator: std.mem.Allocator) !void {
        for (bindings.app_chords) |chord| {
            try self.addAppChord(allocator, chord, .{});
        }
        for (extra_defaults) |spec| {
            try self.applyLine(allocator, spec);
        }
        if (builtin.os.tag == .macos) {
            try self.applyLine(allocator, "super+c=copy_to_clipboard");
            try self.applyLine(allocator, "super+v=paste_from_clipboard");
        } else {
            try self.applyLine(allocator, "performable:ctrl+c=copy_to_clipboard");
            try self.applyLine(allocator, "ctrl+v=paste_from_clipboard");
        }
    }

    pub fn applyLine(self: *Keymap, allocator: std.mem.Allocator, raw: []const u8) !void {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) return;
        if (eql(line, "clear")) {
            self.clear(allocator);
            return;
        }
        if (std.mem.startsWith(u8, line, "chain=") or std.mem.startsWith(u8, line, "chain:")) {
            const param = line["chain=".len..];
            try self.appendChain(allocator, param);
            return;
        }
        try self.applySpec(allocator, line);
    }

    pub fn advance(self: *const Keymap, pending: []const Trigger, next: Trigger) Advance {
        if (pending.len + 1 > max_sequence) return .miss;

        var combined: [max_sequence]Trigger = undefined;
        for (pending, 0..) |t, i| combined[i] = t;
        combined[pending.len] = next;
        const seq = combined[0 .. pending.len + 1];

        const exact = self.lookup(seq);
        if (exact != .miss) return exact;

        if (next.catch_all) return .miss;

        var with_mods = next;
        with_mods.catch_all = true;
        with_mods.key_len = 0;
        for (pending, 0..) |t, i| combined[i] = t;
        combined[pending.len] = with_mods;
        const by_mods = self.lookup(combined[0 .. pending.len + 1]);
        if (by_mods != .miss) return by_mods;

        if (next.mods.ctrl or next.mods.shift or next.mods.super or next.mods.alt) {
            var bare = with_mods;
            bare.mods = .{};
            for (pending, 0..) |t, i| combined[i] = t;
            combined[pending.len] = bare;
            return self.lookup(combined[0 .. pending.len + 1]);
        }
        return .miss;
    }

    fn lookup(self: *const Keymap, seq: []const Trigger) Advance {
        var fire: ?*const Binding = null;
        var waiting = false;
        for (self.bindings.items) |*b| {
            if (b.sequence_len < seq.len) continue;
            if (!sequencePrefixMatch(b.sequence[0..seq.len], seq)) continue;
            if (b.sequence_len == seq.len) {
                fire = b;
            } else {
                waiting = true;
            }
        }
        if (waiting) return .wait;
        if (fire) |b| {
            if (b.action_len == 1 and std.meta.activeTag(b.actions[0]) == .unbind) return .miss;
            return .{ .fire = b };
        }
        return .miss;
    }

    fn addAppChord(self: *Keymap, allocator: std.mem.Allocator, chord: bindings.Chord, prefixes: Prefixes) !void {
        var b = Binding{
            .sequence_len = 1,
            .prefixes = prefixes,
            .action_len = 1,
        };
        b.sequence[0] = Trigger.from(chord.mods, chord.key);
        b.actions[0] = .{ .app = chord.action };
        try self.install(allocator, b);
    }

    fn applySpec(self: *Keymap, allocator: std.mem.Allocator, spec: []const u8) !void {
        const parsed = try parseSpec(allocator, spec);
        if (parsed.action_len == 1 and std.meta.activeTag(parsed.actions[0]) == .unbind) {
            self.removeExact(allocator, parsed.sequenceSlice());
            var tmp = parsed;
            tmp.deinit(allocator);
            return;
        }
        try self.install(allocator, parsed);
    }

    fn appendChain(self: *Keymap, allocator: std.mem.Allocator, raw_action: []const u8) !void {
        if (self.bindings.items.len == 0) return error.NoBindingToChain;
        const last = &self.bindings.items[self.bindings.items.len - 1];
        if (last.action_len >= max_chain) return error.ChainTooLong;
        last.actions[last.action_len] = try parseAction(allocator, raw_action);
        last.action_len += 1;
    }

    fn install(self: *Keymap, allocator: std.mem.Allocator, binding: Binding) !void {
        if (self.bindings.items.len >= max_bindings) {
            var tmp = binding;
            tmp.deinit(allocator);
            return error.TooManyBindings;
        }
        if (binding.sequence_len == 1) {
            self.removeSequencesStartingWith(allocator, binding.sequence[0]);
        }
        self.removeExact(allocator, binding.sequenceSlice());
        try self.bindings.append(allocator, binding);
    }

    fn removeExact(self: *Keymap, allocator: std.mem.Allocator, seq: []const Trigger) void {
        var i: usize = 0;
        while (i < self.bindings.items.len) {
            const b = &self.bindings.items[i];
            if (b.sequence_len == seq.len and sequenceExactMatch(b.sequence[0..b.sequence_len], seq)) {
                var old = self.bindings.orderedRemove(i);
                old.deinit(allocator);
            } else {
                i += 1;
            }
        }
    }

    fn removeSequencesStartingWith(self: *Keymap, allocator: std.mem.Allocator, first: Trigger) void {
        var i: usize = 0;
        while (i < self.bindings.items.len) {
            const b = &self.bindings.items[i];
            if (b.sequence_len > 1 and b.sequence[0].matches(first)) {
                var old = self.bindings.orderedRemove(i);
                old.deinit(allocator);
            } else {
                i += 1;
            }
        }
    }
};

const extra_defaults = [_][]const u8{
    "ctrl+shift+c=copy_to_clipboard",
    "ctrl+shift+v=paste_from_clipboard",
    "super+shift+c=copy_to_clipboard",
    "super+shift+v=paste_from_clipboard",
    "pageup=scroll_page_up",
    "pagedown=scroll_page_down",
};

fn sequencePrefixMatch(expected: []const Trigger, actual: []const Trigger) bool {
    if (expected.len != actual.len) return false;
    for (expected, actual) |e, a| {
        if (!e.matches(a)) return false;
    }
    return true;
}

fn sequenceExactMatch(a: []const Trigger, b: []const Trigger) bool {
    if (a.len != b.len) return false;
    for (a, b) |l, r| {
        if (l.catch_all != r.catch_all) return false;
        if (l.mods.ctrl != r.mods.ctrl) return false;
        if (l.mods.shift != r.mods.shift) return false;
        if (l.mods.super != r.mods.super) return false;
        if (l.mods.alt != r.mods.alt) return false;
        if (!l.catch_all and !std.ascii.eqlIgnoreCase(l.keySlice(), r.keySlice())) return false;
    }
    return true;
}

/// Parse `trigger=action` (optional prefixes, sequences with `>`).
pub fn parseSpec(allocator: std.mem.Allocator, spec: []const u8) !Binding {
    const trimmed = std.mem.trim(u8, spec, " \t\r");
    if (trimmed.len == 0) return error.EmptySpec;

    var rest = trimmed;
    var prefixes: Prefixes = .{};

    while (true) {
        if (consumePrefix(&rest, "all:")) {
            prefixes.all = true;
            continue;
        }
        if (consumePrefix(&rest, "global:")) {
            prefixes.global = true;
            prefixes.all = true;
            continue;
        }
        if (consumePrefix(&rest, "unconsumed:")) {
            prefixes.unconsumed = true;
            continue;
        }
        if (consumePrefix(&rest, "performable:")) {
            prefixes.performable = true;
            continue;
        }
        if (consumePrefix(&rest, "physical:")) {
            continue;
        }
        break;
    }

    // Key tables (`copy/ctrl+c=…`) are not activated yet; ignore the table name
    // so a copied Ghostty snippet still binds in the default table.
    if (std.mem.indexOfScalar(u8, rest, '/')) |slash| {
        const eq_at = std.mem.indexOfScalar(u8, rest, '=') orelse return error.MissingAction;
        if (slash < eq_at) {
            rest = rest[slash + 1 ..];
        }
    }

    const eq = std.mem.indexOfScalar(u8, rest, '=') orelse return error.MissingAction;
    const trigger_raw = std.mem.trim(u8, rest[0..eq], " \t");
    const action_raw = std.mem.trim(u8, rest[eq + 1 ..], " \t");
    if (trigger_raw.len == 0 or action_raw.len == 0) return error.MissingAction;

    var binding = Binding{
        .prefixes = prefixes,
        .sequence_len = 0,
        .action_len = 0,
    };
    errdefer binding.deinit(allocator);

    var parts = std.mem.splitScalar(u8, trigger_raw, '>');
    while (parts.next()) |part| {
        if (binding.sequence_len >= max_sequence) return error.SequenceTooLong;
        binding.sequence[binding.sequence_len] = try parseTrigger(part);
        binding.sequence_len += 1;
    }
    if (binding.sequence_len == 0) return error.EmptyTrigger;

    binding.actions[0] = try parseAction(allocator, action_raw);
    binding.action_len = 1;
    return binding;
}

pub fn parseTrigger(raw: []const u8) !Trigger {
    var mods: Mods = .{};
    var key_name: ?[]const u8 = null;
    var saw_ctrl = false;
    var saw_shift = false;
    var saw_super = false;
    var saw_alt = false;

    var it = std.mem.splitScalar(u8, raw, '+');
    while (it.next()) |part_raw| {
        const part = std.mem.trim(u8, part_raw, " \t");
        if (part.len == 0) continue;
        if (eql(part, "ctrl") or eql(part, "control")) {
            if (saw_ctrl) return error.DuplicateModifier;
            saw_ctrl = true;
            mods.ctrl = true;
        } else if (eql(part, "shift")) {
            if (saw_shift) return error.DuplicateModifier;
            saw_shift = true;
            mods.shift = true;
        } else if (eql(part, "super") or eql(part, "cmd") or eql(part, "command") or eql(part, "meta")) {
            if (saw_super) return error.DuplicateModifier;
            saw_super = true;
            mods.super = true;
        } else if (eql(part, "alt") or eql(part, "opt") or eql(part, "option")) {
            if (saw_alt) return error.DuplicateModifier;
            saw_alt = true;
            mods.alt = true;
        } else {
            if (key_name != null) return error.MultipleKeys;
            key_name = part;
        }
    }

    const kn = key_name orelse return error.MissingKey;
    return Trigger.from(mods, kn);
}

pub fn parseAction(allocator: std.mem.Allocator, raw: []const u8) !Action {
    const s = std.mem.trim(u8, raw, " \t");
    if (s.len == 0) return error.EmptyAction;

    if (eql(s, "ignore")) return .ignore;
    if (eql(s, "unbind")) return .unbind;

    if (std.mem.startsWith(u8, s, "text:")) {
        const payload = try unescapeZigString(allocator, s["text:".len..]);
        return .{ .text = payload };
    }
    if (std.mem.startsWith(u8, s, "csi:")) {
        const payload = try allocator.dupe(u8, s["csi:".len..]);
        return .{ .csi = payload };
    }
    if (std.mem.startsWith(u8, s, "esc:")) {
        const payload = try allocator.dupe(u8, s["esc:".len..]);
        return .{ .esc = payload };
    }

    const name, const param = splitAction(s);
    if (mapAppAction(name, param)) |app| {
        return .{ .app = app };
    }
    return error.UnknownAction;
}

fn splitAction(s: []const u8) struct { []const u8, []const u8 } {
    if (std.mem.indexOfScalar(u8, s, ':')) |colon| {
        return .{ s[0..colon], s[colon + 1 ..] };
    }
    return .{ s, "" };
}

fn mapAppAction(name: []const u8, param: []const u8) ?AppAction {
    if (eql(name, "new_tab")) return .new_tab;
    if (eql(name, "close_tab") or eql(name, "close_surface") or eql(name, "close_window")) return .close_tab;
    if (eql(name, "quit")) return .quit;

    if (eql(name, "new_split") or eql(name, "split")) {
        if (eql(param, "right") or eql(param, "left") or eql(param, "horizontal")) return .split_right;
        if (eql(param, "down") or eql(param, "up") or eql(param, "vertical")) return .split_down;
        return .split_right;
    }
    if (eql(name, "split_right") or eql(name, "split_horizontal")) return .split_right;
    if (eql(name, "split_down") or eql(name, "split_vertical")) return .split_down;

    if (eql(name, "goto_tab")) {
        if (eql(param, "next") or eql(param, "current+1")) return .next_tab;
        if (eql(param, "previous") or eql(param, "prev") or eql(param, "current-1")) return .prev_tab;
        return .next_tab;
    }
    if (eql(name, "next_tab")) return .next_tab;
    if (eql(name, "previous_tab") or eql(name, "prev_tab")) return .prev_tab;

    if (eql(name, "goto_split")) {
        return .focus_next_pane;
    }
    if (eql(name, "focus_next_pane") or eql(name, "next_split")) return .focus_next_pane;

    if (eql(name, "increase_font_size") or eql(name, "font_larger") or eql(name, "font-increase")) return .font_larger;
    if (eql(name, "decrease_font_size") or eql(name, "font_smaller") or eql(name, "font-decrease")) return .font_smaller;
    if (eql(name, "reset_font_size") or eql(name, "font_reset") or eql(name, "font-reset")) return .font_reset;

    if (eql(name, "copy_to_clipboard") or eql(name, "copy") or eql(name, "copy_selection")) return .copy_selection;
    if (eql(name, "paste_from_clipboard") or eql(name, "paste") or eql(name, "paste_clipboard")) return .paste_clipboard;

    if (eql(name, "toggle_command_palette") or eql(name, "toggle_palette") or eql(name, "command_palette") or eql(name, "open_palette") or eql(name, "palette")) {
        return .toggle_palette;
    }

    if (eql(name, "scroll_page_up") or eql(name, "scroll-page-up")) return .scroll_page_up;
    if (eql(name, "scroll_page_down") or eql(name, "scroll-page-down")) return .scroll_page_down;
    if (eql(name, "scroll_to_top") or eql(name, "scroll-to-top")) return .scroll_to_top;
    if (eql(name, "scroll_to_bottom") or eql(name, "scroll-to-bottom")) return .scroll_to_bottom;

    if (eql(name, "reload_config") or eql(name, "reload-config")) return .reload_config;
    if (eql(name, "reload_plugins")) return .reload_plugins;
    if (eql(name, "check_updates") or eql(name, "check_for_updates")) return .check_updates;
    if (eql(name, "update_orbit")) return .update_orbit;
    if (eql(name, "open_config") or eql(name, "settings")) return .settings;
    if (eql(name, "go_home") or eql(name, "home")) return .go_home;
    if (eql(name, "open_workspace")) return .open_workspace;
    if (eql(name, "save_workspace")) return .save_workspace;
    if (eql(name, "load_saved_workspace") or eql(name, "load_workspace")) return .load_saved_workspace;
    if (eql(name, "search") or eql(name, "toggle_search")) return .search;
    if (eql(name, "open_file")) return .open_file;
    if (eql(name, "ssh")) return .ssh;
    if (eql(name, "list_plugins") or eql(name, "plugins")) return .list_plugins;
    if (eql(name, "format_document") or eql(name, "format")) return .format_document;
    if (eql(name, "lint_file") or eql(name, "lint")) return .lint_file;
    if (eql(name, "ai_explain")) return .ai_explain;
    if (eql(name, "ai_suggest")) return .ai_suggest;

    if (eql(name, "cursor_block")) return .cursor_block;
    if (eql(name, "cursor_underline")) return .cursor_underline;
    if (eql(name, "cursor_bar") or eql(name, "cursor_beam")) return .cursor_bar;
    if (eql(name, "cursor_blink_toggle") or eql(name, "toggle_cursor_blink")) return .cursor_blink_toggle;

    if (eql(name, "theme") or eql(name, "set_theme")) {
        return themeFromName(param);
    }
    if (eql(name, "theme_orbit_dark")) return .theme_orbit_dark;
    if (eql(name, "theme_orbit_light")) return .theme_orbit_light;
    if (eql(name, "theme_nord")) return .theme_nord;
    if (eql(name, "theme_dracula")) return .theme_dracula;
    if (eql(name, "theme_gruvbox") or eql(name, "theme_gruvbox_dark")) return .theme_gruvbox;
    if (eql(name, "theme_solarized") or eql(name, "theme_solarized_dark")) return .theme_solarized;
    if (eql(name, "theme_catppuccin") or eql(name, "theme_catppuccin_mocha")) return .theme_catppuccin;
    if (eql(name, "theme_tokyo_night")) return .theme_tokyo_night;

    return null;
}

fn themeFromName(name: []const u8) ?AppAction {
    if (eql(name, "orbit-dark") or eql(name, "orbit_dark")) return .theme_orbit_dark;
    if (eql(name, "orbit-light") or eql(name, "orbit_light")) return .theme_orbit_light;
    if (eql(name, "nord")) return .theme_nord;
    if (eql(name, "dracula")) return .theme_dracula;
    if (eql(name, "gruvbox") or eql(name, "gruvbox-dark")) return .theme_gruvbox;
    if (eql(name, "solarized") or eql(name, "solarized-dark")) return .theme_solarized;
    if (eql(name, "catppuccin") or eql(name, "catppuccin-mocha")) return .theme_catppuccin;
    if (eql(name, "tokyo-night") or eql(name, "tokyo_night")) return .theme_tokyo_night;
    return null;
}

pub fn normalizeKey(part: []const u8) []const u8 {
    const from_bindings = bindings.normalizeKeyToken(part);
    if (!std.mem.eql(u8, from_bindings, part)) return from_bindings;

    if (eql(part, "esc") or eql(part, "escape")) return "escape";
    if (eql(part, "return") or eql(part, "enter") or eql(part, "kp_enter")) return "enter";
    if (eql(part, "space") or eql(part, "spacebar")) return "space";
    if (eql(part, "backspace") or eql(part, "bksp")) return "backspace";
    if (eql(part, "delete") or eql(part, "del")) return "delete";
    if (eql(part, "insert") or eql(part, "ins")) return "insert";
    if (eql(part, "arrow_up") or eql(part, "arrowup") or eql(part, "up")) return "up";
    if (eql(part, "arrow_down") or eql(part, "arrowdown") or eql(part, "down")) return "down";
    if (eql(part, "arrow_left") or eql(part, "arrowleft") or eql(part, "left")) return "left";
    if (eql(part, "arrow_right") or eql(part, "arrowright") or eql(part, "right")) return "right";
    if (eql(part, "comma")) return ",";
    if (eql(part, "period") or eql(part, "dot")) return ".";
    if (eql(part, "slash")) return "/";
    if (eql(part, "backslash")) return "\\";
    if (eql(part, "semicolon")) return ";";
    if (eql(part, "apostrophe") or eql(part, "quote")) return "'";
    if (eql(part, "grave") or eql(part, "backquote") or eql(part, "backtick")) return "`";
    if (eql(part, "bracket_left") or eql(part, "left_bracket") or eql(part, "bracketleft")) return "[";
    if (eql(part, "bracket_right") or eql(part, "right_bracket") or eql(part, "bracketright")) return "]";

    // W3C / Ghostty physical: KeyA, key_a, Digit1, digit_1
    if (part.len == 4 and eql(part[0..3], "key") and std.ascii.isAlphabetic(part[3])) {
        return part[3..4];
    }
    if (part.len == 5 and eql(part[0..4], "key_") and std.ascii.isAlphabetic(part[4])) {
        return part[4..5];
    }
    if (part.len == 6 and eql(part[0..5], "digit") and part[5] >= '0' and part[5] <= '9') {
        return part[5..6];
    }
    if (part.len == 7 and eql(part[0..6], "digit_") and part[6] >= '0' and part[6] <= '9') {
        return part[6..7];
    }
    return from_bindings;
}

/// Zig-ish string unescape for `text:` payloads (`\x15`, `\n`, `\r`, `\t`, `\e`, `\\`).
pub fn unescapeZigString(allocator: std.mem.Allocator, src: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < src.len) {
        if (src[i] == '\\' and i + 1 < src.len) {
            const n = src[i + 1];
            if (n == 'x' and i + 3 < src.len) {
                const byte = std.fmt.parseInt(u8, src[i + 2 .. i + 4], 16) catch {
                    try out.append(allocator, src[i]);
                    i += 1;
                    continue;
                };
                try out.append(allocator, byte);
                i += 4;
                continue;
            }
            const ch: u8 = switch (n) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                'e' => 0x1b,
                '0' => 0,
                '\\' => '\\',
                '\'' => '\'',
                '"' => '"',
                else => n,
            };
            try out.append(allocator, ch);
            i += 2;
            continue;
        }
        try out.append(allocator, src[i]);
        i += 1;
    }
    return out.toOwnedSlice(allocator);
}

/// Encode a trigger as PTY bytes (ctrl+letter, arrows, enter, …).
pub fn encodeTrigger(trigger: Trigger, out: *[8]u8) []const u8 {
    const key = trigger.keySlice();
    if (trigger.catch_all) return &.{};

    if (trigger.mods.ctrl and !trigger.mods.super and !trigger.mods.alt and key.len == 1) {
        const ch = std.ascii.toLower(key[0]);
        if (ch >= 'a' and ch <= 'z') {
            out[0] = ch - 'a' + 1;
            return out[0..1];
        }
    }

    if (eql(key, "enter")) {
        out[0] = '\r';
        return out[0..1];
    }
    if (eql(key, "tab")) {
        out[0] = '\t';
        return out[0..1];
    }
    if (eql(key, "escape")) {
        out[0] = 0x1b;
        return out[0..1];
    }
    if (eql(key, "backspace")) {
        out[0] = 0x7F;
        return out[0..1];
    }
    if (eql(key, "up")) return copyCsi(out, "A");
    if (eql(key, "down")) return copyCsi(out, "B");
    if (eql(key, "right")) return copyCsi(out, "C");
    if (eql(key, "left")) return copyCsi(out, "D");
    if (eql(key, "home")) return copyCsi(out, "H");
    if (eql(key, "end")) return copyCsi(out, "F");
    if (eql(key, "delete")) {
        const seq = "\x1b[3~";
        @memcpy(out[0..seq.len], seq);
        return out[0..seq.len];
    }
    return &.{};
}

fn copyCsi(out: *[8]u8, final: []const u8) []const u8 {
    out[0] = 0x1b;
    out[1] = '[';
    @memcpy(out[2 .. 2 + final.len], final);
    return out[0 .. 2 + final.len];
}

fn consumePrefix(rest: *[]const u8, prefix: []const u8) bool {
    if (rest.*.len >= prefix.len and std.ascii.eqlIgnoreCase(rest.*[0..prefix.len], prefix)) {
        rest.* = rest.*[prefix.len..];
        return true;
    }
    return false;
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}
