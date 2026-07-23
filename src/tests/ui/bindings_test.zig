//! Unit tests — shortcut bindings stay aligned with the Command Palette.

const std = @import("std");
const bindings = @import("../../ui/bindings.zig");
const palette_mod = @import("../../ui/palette.zig");

test "plain Ctrl+W does not close tab (shell kill-word)" {
    try std.testing.expect(bindings.match("w", .{ .ctrl = true }) == null);
}

test "Cmd+W closes tab" {
    const act = bindings.match("w", .{ .super = true }) orelse return error.TestUnexpectedResult;
    try std.testing.expect(act == .close_tab);
}

test "Ctrl+Shift+W closes tab" {
    const act = bindings.match("w", .{ .ctrl = true, .shift = true }) orelse return error.TestUnexpectedResult;
    try std.testing.expect(act == .close_tab);
}

test "Ctrl alone with wrong key does not match close" {
    // Regression: matching hardcoded "w" while Ctrl held closed on every Ctrl chord.
    try std.testing.expect(bindings.match("t", .{ .ctrl = true }) == null);
    try std.testing.expect(bindings.match("c", .{ .ctrl = true }) == null);
}

test "Ctrl+Q quits" {
    const act = bindings.match("q", .{ .ctrl = true }) orelse return error.TestUnexpectedResult;
    try std.testing.expect(act == .quit);
}

test "plain W is not an app shortcut" {
    try std.testing.expect(bindings.match("w", .{}) == null);
}

test "Ctrl+C reaches the PTY as ETX" {
    const byte = bindings.ctrlLetterToPty("c", .{ .ctrl = true }) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u8, 0x03), byte);
}

test "Ctrl+D reaches the PTY as EOT" {
    const byte = bindings.ctrlLetterToPty("d", .{ .ctrl = true }) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u8, 0x04), byte);
}

test "Ctrl+W is forwarded to the PTY as kill-word" {
    const byte = bindings.ctrlLetterToPty("w", .{ .ctrl = true }) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u8, 0x17), byte);
}

test "Ctrl+Shift+T opens new tab" {
    const act = bindings.match("t", .{ .ctrl = true, .shift = true }) orelse return error.TestUnexpectedResult;
    try std.testing.expect(act == .new_tab);
}

test "every shortcut-style palette hint resolves to its action" {
    for (palette_mod.catalog) |entry| {
        if (!isChordHint(entry.hint)) continue;
        var key_buf: [32]u8 = undefined;
        const parsed = bindings.parseHint(entry.hint, &key_buf) orelse {
            std.debug.print("unparseable hint for {s}: {s}\n", .{ entry.label, entry.hint });
            return error.TestUnexpectedResult;
        };
        const mods, const key = parsed;
        const act = bindings.match(key, mods) orelse {
            std.debug.print("unbound hint for {s}: {s}\n", .{ entry.label, entry.hint });
            return error.TestUnexpectedResult;
        };
        try std.testing.expectEqual(entry.action, act);
    }
}

test "parseHint understands Cmd+W and Ctrl+Shift+T" {
    var key_buf: [32]u8 = undefined;
    {
        const parsed = bindings.parseHint("Cmd+W", &key_buf) orelse return error.TestUnexpectedResult;
        const mods, const key = parsed;
        try std.testing.expect(mods.super and !mods.ctrl);
        try std.testing.expectEqualStrings("w", key);
    }
    {
        const parsed = bindings.parseHint("Ctrl+Shift+T", &key_buf) orelse return error.TestUnexpectedResult;
        const mods, const key = parsed;
        try std.testing.expect(mods.ctrl and mods.shift);
        try std.testing.expectEqualStrings("t", key);
    }
}

test "palette catalog covers every Action exactly once" {
    var seen = [_]bool{false} ** std.meta.fields(palette_mod.Action).len;
    for (palette_mod.catalog) |entry| {
        const idx = @intFromEnum(entry.action);
        try std.testing.expect(!seen[idx]);
        seen[idx] = true;
    }
    for (seen) |s| try std.testing.expect(s);
}

fn isChordHint(hint: []const u8) bool {
    if (hint.len == 0) return false;
    if (std.mem.indexOfScalar(u8, hint, '+') != null) return true;
    // e.g. future single-token chords
    return std.mem.startsWith(u8, hint, "Ctrl") or std.mem.startsWith(u8, hint, "Cmd");
}
