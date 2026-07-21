//! Unit tests — ANSI / CSI parser.

const std = @import("std");
const Screen = @import("../../terminal/screen.zig").Screen;
const Parser = @import("../../terminal/parser.zig").Parser;

test "SGR red foreground then reset" {
    var screen = try Screen.init(std.testing.allocator, 20, 2);
    defer screen.deinit();
    var parser = Parser.init();
    parser.feed(&screen, "\x1b[31mHi\x1b[0m!");
    try std.testing.expectEqual(@as(u21, 'H'), screen.cellAtConst(0, 0).codepoint);
    try std.testing.expectEqual(@as(u8, 205), screen.cellAtConst(0, 0).fg.r);
    try std.testing.expectEqual(@as(u21, '!'), screen.cellAtConst(2, 0).codepoint);
}

test "CSI CUP cursor position" {
    var screen = try Screen.init(std.testing.allocator, 20, 5);
    defer screen.deinit();
    var parser = Parser.init();
    parser.feed(&screen, "\x1b[3;5H");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
}

test "CSI cursor up down left right" {
    var screen = try Screen.init(std.testing.allocator, 20, 10);
    defer screen.deinit();
    screen.cursor_col = 5;
    screen.cursor_row = 5;
    var parser = Parser.init();
    parser.feed(&screen, "\x1b[2A"); // up 2
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    parser.feed(&screen, "\x1b[1B"); // down 1
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    parser.feed(&screen, "\x1b[3C"); // right 3
    try std.testing.expectEqual(@as(u16, 8), screen.cursor_col);
    parser.feed(&screen, "\x1b[2D"); // left 2
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_col);
}

test "SGR bold attribute" {
    var screen = try Screen.init(std.testing.allocator, 10, 2);
    defer screen.deinit();
    var parser = Parser.init();
    parser.feed(&screen, "\x1b[1mB\x1b[0m");
    try std.testing.expect(screen.cellAtConst(0, 0).attrs.bold);
}

test "plain text feed" {
    var screen = try Screen.init(std.testing.allocator, 20, 2);
    defer screen.deinit();
    var parser = Parser.init();
    parser.feed(&screen, "abc");
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAtConst(0, 0).codepoint);
    try std.testing.expectEqual(@as(u21, 'c'), screen.cellAtConst(2, 0).codepoint);
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
}

test "erase display CSI 2J" {
    var screen = try Screen.init(std.testing.allocator, 8, 2);
    defer screen.deinit();
    var parser = Parser.init();
    parser.feed(&screen, "xxxx\x1b[2J");
    try std.testing.expectEqual(@as(u21, ' '), screen.cellAtConst(0, 0).codepoint);
}
