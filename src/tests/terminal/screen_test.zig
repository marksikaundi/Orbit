//! Unit tests — terminal screen buffer.

const std = @import("std");
const Screen = @import("../../terminal/screen.zig").Screen;
const Color = @import("../../terminal/cell.zig").Color;

test "putChar advances cursor and wraps" {
    var screen = try Screen.init(std.testing.allocator, 4, 2);
    defer screen.deinit();

    screen.putChar('a');
    screen.putChar('b');
    screen.putChar('c');
    screen.putChar('d');
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAtConst(0, 0).codepoint);
    try std.testing.expectEqual(@as(u21, 'd'), screen.cellAtConst(3, 0).codepoint);
}

test "newline moves to next row" {
    var screen = try Screen.init(std.testing.allocator, 10, 3);
    defer screen.deinit();
    screen.putChar('x');
    screen.putChar('\n');
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
}

test "sgr colors persist on cell" {
    var screen = try Screen.init(std.testing.allocator, 8, 2);
    defer screen.deinit();
    screen.fg = Color.rgb(200, 50, 50);
    screen.putChar('R');
    try std.testing.expectEqual(@as(u8, 200), screen.cellAtConst(0, 0).fg.r);
}

test "cursor save and restore" {
    var screen = try Screen.init(std.testing.allocator, 20, 10);
    defer screen.deinit();
    screen.cursor_col = 5;
    screen.cursor_row = 3;
    screen.saveCursor();
    screen.cursor_col = 0;
    screen.cursor_row = 0;
    screen.restoreCursor();
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
}

test "lineText extracts printable row" {
    var screen = try Screen.init(std.testing.allocator, 8, 2);
    defer screen.deinit();
    for ("hello") |ch| screen.putChar(ch);
    var buf: [16]u8 = undefined;
    const n = screen.lineText(0, &buf);
    try std.testing.expect(std.mem.startsWith(u8, buf[0..n], "hello"));
}

test "resize preserves content when growing" {
    var screen = try Screen.init(std.testing.allocator, 4, 2);
    defer screen.deinit();
    screen.putChar('Z');
    try screen.resize(8, 4);
    try std.testing.expectEqual(@as(u16, 8), screen.cols);
    try std.testing.expectEqual(@as(u16, 4), screen.rows);
    try std.testing.expectEqual(@as(u21, 'Z'), screen.cellAtConst(0, 0).codepoint);
}

test "eraseInLine clears from cursor" {
    var screen = try Screen.init(std.testing.allocator, 6, 1);
    defer screen.deinit();
    for ("abcdef") |ch| screen.putChar(ch);
    screen.cursor_col = 2;
    screen.cursor_row = 0;
    screen.eraseInLine(0); // erase to end
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAtConst(0, 0).codepoint);
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAtConst(1, 0).codepoint);
    try std.testing.expectEqual(@as(u21, ' '), screen.cellAtConst(2, 0).codepoint);
}

test "enterAltScreen swaps buffers and leave restores" {
    var screen = try Screen.init(std.testing.allocator, 6, 2);
    defer screen.deinit();
    screen.putChar('A');
    screen.enterAltScreen(true, true);
    try std.testing.expect(screen.alt_active);
    try std.testing.expectEqual(@as(u21, ' '), screen.cellAtConst(0, 0).codepoint);
    screen.putChar('Z');
    screen.leaveAltScreen(true);
    try std.testing.expect(!screen.alt_active);
    try std.testing.expectEqual(@as(u21, 'A'), screen.cellAtConst(0, 0).codepoint);
}

test "scrollback ring caps length and keeps newest rows" {
    var screen = try Screen.init(std.testing.allocator, 2, 1);
    defer screen.deinit();
    screen.scrollback_max = 3;

    for ("ABCDE") |ch| {
        screen.putChar(ch);
        screen.putChar('\n');
    }

    try std.testing.expectEqual(@as(usize, 3), screen.scrollback.items.len);
    try std.testing.expectEqual(@as(u21, 'C'), screen.scrollbackRowAt(0)[0].codepoint);
    try std.testing.expectEqual(@as(u21, 'D'), screen.scrollbackRowAt(1)[0].codepoint);
    try std.testing.expectEqual(@as(u21, 'E'), screen.scrollbackRowAt(2)[0].codepoint);

    screen.view_offset = 3;
    try std.testing.expectEqual(@as(u21, 'C'), screen.visibleCell(0, 0).codepoint);
}

test "setThemeColors recolors default cells so unused rows match" {
    var screen = try Screen.init(std.testing.allocator, 4, 2);
    defer screen.deinit();
    screen.putChar('A');
    const old_bg = screen.cellAtConst(1, 0).bg;
    const themed = Color.rgb(0, 43, 54);
    screen.setThemeColors(Color.rgb(200, 200, 200), themed);
    try std.testing.expect(screen.cellAtConst(1, 0).bg.eql(themed));
    try std.testing.expect(screen.cellAtConst(0, 1).bg.eql(themed));
    try std.testing.expect(screen.cellAtConst(0, 0).bg.eql(themed));
    try std.testing.expect(old_bg.eql(Color.rgb(18, 20, 26)));
}
