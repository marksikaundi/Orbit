//! Unit tests — in-terminal search.

const std = @import("std");
const Search = @import("../../ui/search.zig").Search;
const Screen = @import("../../terminal/screen.zig").Screen;

test "open close and query editing" {
    var s: Search = .{};
    s.open();
    try std.testing.expect(s.active);
    s.inputChar('f');
    s.inputChar('o');
    s.inputChar('o');
    try std.testing.expectEqualStrings("foo", s.querySlice());
    s.backspace();
    try std.testing.expectEqualStrings("fo", s.querySlice());
    s.close();
    try std.testing.expect(!s.active);
    try std.testing.expectEqual(@as(usize, 0), s.query_len);
}

test "ignores control and non-ascii input" {
    var s: Search = .{};
    s.open();
    s.inputChar(7);
    s.inputChar(0x1F600);
    try std.testing.expectEqual(@as(usize, 0), s.query_len);
}

test "findNext locates and advances" {
    var screen = try Screen.init(std.testing.allocator, 20, 3);
    defer screen.deinit();
    for ("hello world") |ch| screen.putChar(ch);
    screen.lineFeed();
    screen.cursor_col = 0;
    for ("hello again") |ch| screen.putChar(ch);

    var s: Search = .{};
    s.open();
    for ("hello") |ch| s.inputChar(ch);
    s.findNext(&screen);
    try std.testing.expectEqual(@as(?u16, 0), s.match_row);
    try std.testing.expectEqual(@as(?u16, 0), s.match_col);

    s.findNext(&screen);
    try std.testing.expectEqual(@as(?u16, 1), s.match_row);
    try std.testing.expectEqual(@as(?u16, 0), s.match_col);
}

test "findNext clears when no match" {
    var screen = try Screen.init(std.testing.allocator, 10, 2);
    defer screen.deinit();
    for ("abc") |ch| screen.putChar(ch);

    var s: Search = .{};
    s.open();
    for ("zzz") |ch| s.inputChar(ch);
    s.findNext(&screen);
    try std.testing.expectEqual(@as(?u16, null), s.match_row);
}
