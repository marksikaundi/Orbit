//! App shortcut table — single source of truth for palette hints and key dispatch.
//!
//! Every chord listed here must be handled by `match` so Command Palette hints
//! cannot drift from what the keyboard actually does.

const std = @import("std");
const palette_mod = @import("palette.zig");
const Action = palette_mod.Action;

pub const Mods = struct {
    ctrl: bool = false,
    shift: bool = false,
    super: bool = false,
    alt: bool = false,
};

pub const Chord = struct {
    key: []const u8,
    mods: Mods,
    action: Action,
};

/// Built-in chords that must work from the terminal (not only via the palette).
pub const app_chords = [_]Chord{
    .{ .key = "q", .mods = .{ .super = true }, .action = .quit },
    .{ .key = "q", .mods = .{ .ctrl = true }, .action = .quit },
    // Close tab: Cmd+W (macOS) / Ctrl+Shift+W. Plain Ctrl+W stays with the shell (kill-word).
    .{ .key = "w", .mods = .{ .super = true }, .action = .close_tab },
    .{ .key = "w", .mods = .{ .ctrl = true, .shift = true }, .action = .close_tab },
    .{ .key = "h", .mods = .{ .ctrl = true, .shift = true }, .action = .go_home },
    .{ .key = "t", .mods = .{ .ctrl = true, .shift = true }, .action = .new_tab },
    .{ .key = "d", .mods = .{ .ctrl = true, .shift = true }, .action = .split_right },
    .{ .key = "e", .mods = .{ .ctrl = true, .shift = true }, .action = .split_down },
    .{ .key = "o", .mods = .{ .ctrl = true, .shift = true }, .action = .open_workspace },
    .{ .key = "s", .mods = .{ .ctrl = true, .shift = true }, .action = .save_workspace },
    .{ .key = "f", .mods = .{ .ctrl = true, .shift = true }, .action = .search },
    .{ .key = "f", .mods = .{ .super = true, .shift = true }, .action = .search },
    .{ .key = "tab", .mods = .{ .ctrl = true }, .action = .next_tab },
    .{ .key = "tab", .mods = .{ .ctrl = true, .shift = true }, .action = .prev_tab },
    .{ .key = "]", .mods = .{ .ctrl = true, .shift = true }, .action = .next_tab },
    .{ .key = "[", .mods = .{ .ctrl = true, .shift = true }, .action = .prev_tab },
    .{ .key = "pagedown", .mods = .{ .ctrl = true }, .action = .focus_next_pane },
    .{ .key = "equal", .mods = .{ .ctrl = true }, .action = .font_larger },
    .{ .key = "equal", .mods = .{ .super = true }, .action = .font_larger },
    .{ .key = "minus", .mods = .{ .ctrl = true }, .action = .font_smaller },
    .{ .key = "minus", .mods = .{ .super = true }, .action = .font_smaller },
    .{ .key = "0", .mods = .{ .ctrl = true }, .action = .font_reset },
    .{ .key = "0", .mods = .{ .super = true }, .action = .font_reset },
};

/// Match a key name + modifiers to a built-in action.
pub fn match(key: []const u8, mods: Mods) ?Action {
    for (app_chords) |chord| {
        if (!std.ascii.eqlIgnoreCase(chord.key, key)) continue;
        if (chord.mods.ctrl != mods.ctrl) continue;
        if (chord.mods.shift != mods.shift) continue;
        if (chord.mods.super != mods.super) continue;
        if (chord.mods.alt != mods.alt) continue;
        return chord.action;
    }
    return null;
}

/// Encode Ctrl+A…Ctrl+Z as the ASCII control byte (1…26).
/// Returns null for letters that Orbit consumes as app shortcuts.
pub fn ctrlLetterToPty(key_name: []const u8, mods: Mods) ?u8 {
    if (!mods.ctrl or mods.super or mods.alt) return null;
    if (key_name.len != 1) return null;
    const ch = std.ascii.toLower(key_name[0]);
    if (ch < 'a' or ch > 'z') return null;

    // App-reserved Ctrl(+Shift) chords — do not forward to the shell.
    if (match(key_name, mods) != null) return null;

    return ch - 'a' + 1;
}

/// Parse a human hint like "Ctrl+Shift+T" or "Cmd+W" into mods + key.
/// Key tokens are lowercased into `key_buf` (must outlive the return).
pub fn parseHint(hint: []const u8, key_buf: *[32]u8) ?struct { Mods, []const u8 } {
    var mods: Mods = .{};
    var key_raw: ?[]const u8 = null;
    var it = std.mem.splitScalar(u8, hint, '+');
    while (it.next()) |raw| {
        const part = trim(raw);
        if (part.len == 0) continue;
        if (eql(part, "ctrl") or eql(part, "control")) {
            mods.ctrl = true;
        } else if (eql(part, "shift")) {
            mods.shift = true;
        } else if (eql(part, "cmd") or eql(part, "super") or eql(part, "meta")) {
            mods.super = true;
        } else if (eql(part, "alt") or eql(part, "option")) {
            mods.alt = true;
        } else if (eql(part, "cmd/ctrl") or eql(part, "ctrl/cmd")) {
            mods.ctrl = true;
        } else {
            key_raw = normalizeKeyToken(part);
        }
    }
    const raw = key_raw orelse return null;
    const n = @min(raw.len, key_buf.len);
    for (raw[0..n], 0..) |ch, i| {
        key_buf[i] = std.ascii.toLower(ch);
    }
    return .{ mods, key_buf[0..n] };
}

fn normalizeKeyToken(part: []const u8) []const u8 {
    if (eql(part, "=") or eql(part, "+") or eql(part, "plus")) return "equal";
    if (eql(part, "-") or eql(part, "−")) return "minus";
    if (eql(part, "pgdn") or eql(part, "page down") or eql(part, "page_down") or eql(part, "pagedown")) return "pagedown";
    if (eql(part, "pgup") or eql(part, "page up") or eql(part, "page_up") or eql(part, "pageup")) return "pageup";
    return part;
}

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t");
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}
