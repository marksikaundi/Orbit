//! Unit tests — home screen navigation (logic only; no GPU draw).

const std = @import("std");
const home = @import("../../ui/home.zig");

test "version constant present" {
    try std.testing.expect(home.version.len > 0);
}

test "entries cover core actions" {
    try std.testing.expectEqual(@as(usize, 7), home.entries.len);
    try std.testing.expectEqual(home.Action.new_terminal, home.entries[0].action);
    try std.testing.expectEqual(home.Action.settings, home.entries[3].action);
    try std.testing.expectEqual(home.Action.plugins, home.entries[4].action);
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

test "help catalog covers major sections" {
    try std.testing.expect(home.help_rows.len > 40);
    var headings: usize = 0;
    var items: usize = 0;
    for (home.help_rows) |row| {
        switch (row) {
            .heading => headings += 1,
            .item => items += 1,
            else => {},
        }
    }
    try std.testing.expect(headings >= 8);
    try std.testing.expect(items >= 30);
}

test "help scroll does not move menu selection" {
    var h: home.Home = .{};
    h.openHelp();
    try std.testing.expect(h.show_help);
    try std.testing.expectEqual(@as(usize, 0), h.help_scroll);
    h.moveDown();
    try std.testing.expectEqual(@as(usize, 0), h.selected);
    try std.testing.expectEqual(@as(usize, 1), h.help_scroll);
    h.closeHelp();
    try std.testing.expect(!h.show_help);
}

test "selectedAction follows selection" {
    var h: home.Home = .{};
    try std.testing.expectEqual(home.Action.new_terminal, h.selectedAction());
    h.selected = 3;
    try std.testing.expectEqual(home.Action.settings, h.selectedAction());
}

test "recents extend the home list" {
    var h: home.Home = .{ .recents_count = 2 };
    var i: usize = 0;
    while (i < 20) : (i += 1) h.moveDown();
    try std.testing.expectEqual(@as(usize, home.entries.len + 1), h.selected);
    try std.testing.expectEqual(@as(?usize, 1), h.recentIndex());
}
