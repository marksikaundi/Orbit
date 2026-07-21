//! Unit tests — home screen navigation (logic only; no GPU draw).

const std = @import("std");
const home = @import("../../ui/home.zig");

test "version constant present" {
    try std.testing.expect(home.version.len > 0);
}

test "entries cover core actions" {
    try std.testing.expectEqual(@as(usize, 6), home.entries.len);
    try std.testing.expectEqual(home.Action.new_terminal, home.entries[0].action);
    try std.testing.expectEqual(home.Action.quit, home.entries[home.entries.len - 1].action);
}

test "moveDown and moveUp stay in bounds" {
    var h: home.Home = .{};
    h.moveDown();
    try std.testing.expectEqual(@as(usize, 1), h.selected);
    h.moveUp();
    try std.testing.expectEqual(@as(usize, 0), h.selected);
    h.moveUp();
    try std.testing.expectEqual(@as(usize, 0), h.selected);

    var i: usize = 0;
    while (i < 20) : (i += 1) h.moveDown();
    try std.testing.expectEqual(home.entries.len - 1, h.selected);
}

test "help mode blocks navigation" {
    var h: home.Home = .{};
    h.show_help = true;
    h.moveDown();
    try std.testing.expectEqual(@as(usize, 0), h.selected);
}

test "selectedAction follows selection" {
    var h: home.Home = .{};
    try std.testing.expectEqual(home.Action.new_terminal, h.selectedAction());
    h.selected = 3;
    try std.testing.expectEqual(home.Action.settings, h.selectedAction());
}
