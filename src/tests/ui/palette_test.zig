//! Unit tests — command palette.

const std = @import("std");
const palette_mod = @import("../../ui/palette.zig");
const Palette = palette_mod.Palette;

test "builtins populate and empty query matches all" {
    var p: Palette = .{};
    p.addAllBuiltins();
    try std.testing.expect(p.item_count > 10);
    p.open();
    try std.testing.expectEqual(p.item_count, p.match_count);
}

test "fuzzy filter finds New Tab" {
    var p: Palette = .{};
    p.addAllBuiltins();
    p.open();
    p.inputChar('n');
    p.inputChar('e');
    p.inputChar('w');
    try std.testing.expect(p.match_count >= 1);
    const item = p.selectedItem() orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, item.label, "New") != null or std.mem.indexOf(u8, item.label, "Tab") != null);
}

test "backspace restores broader matches" {
    var p: Palette = .{};
    p.addAllBuiltins();
    p.open();
    const all = p.match_count;
    p.inputChar('z');
    p.inputChar('z');
    p.inputChar('z');
    const narrow = p.match_count;
    try std.testing.expect(narrow <= all);
    p.backspace();
    p.backspace();
    p.backspace();
    try std.testing.expectEqual(all, p.match_count);
}

test "selection moves with wrap clamp" {
    var p: Palette = .{};
    p.addAllBuiltins();
    p.open();
    p.moveDown();
    try std.testing.expectEqual(@as(usize, 1), p.selected);
    p.moveUp();
    try std.testing.expectEqual(@as(usize, 0), p.selected);
    p.moveUp();
    try std.testing.expectEqual(@as(usize, 0), p.selected);
}

test "plugin commands appear in filter" {
    var p: Palette = .{};
    p.addAllBuiltins();
    p.addPluginCommand("Hello Plugin", "demo", "hello", "greet");
    p.open();
    for ("hello") |ch| p.inputChar(ch);
    try std.testing.expect(p.match_count >= 1);
}

test "close clears active state" {
    var p: Palette = .{};
    p.addAllBuiltins();
    p.open();
    try std.testing.expect(p.active);
    p.close();
    try std.testing.expect(!p.active);
}
