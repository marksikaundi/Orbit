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

test "alternate screen restores the shell after vim-style 1049" {
    var screen = try Screen.init(std.testing.allocator, 12, 4);
    defer screen.deinit();
    var parser = Parser.init();
    parser.feed(&screen, "prompt>");
    try std.testing.expectEqual(@as(u21, 'p'), screen.cellAtConst(0, 0).codepoint);
    try std.testing.expect(!screen.alt_active);

    parser.feed(&screen, "\x1b[?1049h");
    try std.testing.expect(screen.alt_active);
    try std.testing.expectEqual(@as(u21, ' '), screen.cellAtConst(0, 0).codepoint);

    parser.feed(&screen, "console.log");
    try std.testing.expectEqual(@as(u21, 'c'), screen.cellAtConst(0, 0).codepoint);

    parser.feed(&screen, "\x1b[?1049l");
    try std.testing.expect(!screen.alt_active);
    try std.testing.expectEqual(@as(u21, 'p'), screen.cellAtConst(0, 0).codepoint);
    try std.testing.expectEqual(@as(u21, 't'), screen.cellAtConst(5, 0).codepoint);
}

test "alt screen scroll does not pollute scrollback" {
    var screen = try Screen.init(std.testing.allocator, 4, 2);
    defer screen.deinit();
    var parser = Parser.init();
    parser.feed(&screen, "\x1b[?1049h");
    parser.feed(&screen, "aaaa\nbbbb\ncccc");
    try std.testing.expectEqual(@as(usize, 0), screen.scrollback.items.len);
    parser.feed(&screen, "\x1b[?1049l");
    try std.testing.expectEqual(@as(usize, 0), screen.scrollback.items.len);
}

test "CSI 6n reports 1-based cursor position" {
    var screen = try Screen.init(std.testing.allocator, 20, 10);
    defer screen.deinit();
    screen.cursor_col = 4;
    screen.cursor_row = 2;
    var parser = Parser.init();
    parser.feed(&screen, "\x1b[6n");
    try std.testing.expectEqualStrings("\x1b[3;5R", parser.reply_buf[0..parser.reply_len]);
}

test "CSI ? 25 l hides the cursor" {
    var screen = try Screen.init(std.testing.allocator, 8, 2);
    defer screen.deinit();
    var parser = Parser.init();
    parser.feed(&screen, "\x1b[?25l");
    try std.testing.expect(!screen.cursor_visible);
    parser.feed(&screen, "\x1b[?25h");
    try std.testing.expect(screen.cursor_visible);
}

test "primary DA replies" {
    var screen = try Screen.init(std.testing.allocator, 8, 2);
    defer screen.deinit();
    var parser = Parser.init();
    parser.feed(&screen, "\x1b[c");
    try std.testing.expect(parser.reply_len > 0);
    try std.testing.expectEqual(@as(u8, 0x1B), parser.reply_buf[0]);
}

test "OSC 0 sets the title" {
    var screen = try Screen.init(std.testing.allocator, 8, 2);
    defer screen.deinit();
    var parser = Parser.init();
    parser.feed(&screen, "\x1b]0;api-server\x07");
    try std.testing.expect(screen.title_dirty);
    try std.testing.expectEqualStrings("api-server", screen.title[0..screen.title_len]);
}

test "OSC 7 sets live cwd" {
    var screen = try Screen.init(std.testing.allocator, 8, 2);
    defer screen.deinit();
    var parser = Parser.init();
    parser.feed(&screen, "\x1b]7;file://localhost/tmp/proj\x07");
    try std.testing.expect(screen.cwd_dirty);
    try std.testing.expectEqualStrings("/tmp/proj", screen.osc_cwd[0..screen.osc_cwd_len]);
}

test "OSC 8 hyperlink is stored on the next cell" {
    var screen = try Screen.init(std.testing.allocator, 20, 2);
    defer screen.deinit();
    var parser = Parser.init();
    parser.feed(&screen, "\x1b]8;;https://example.com\x07hi\x1b]8;;\x07");
    try std.testing.expect(screen.cellAtConst(0, 0).link_id != 0);
    try std.testing.expectEqualStrings("https://example.com", screen.linkUrl(screen.cellAtConst(0, 0).link_id).?);
    try std.testing.expectEqual(@as(u16, 0), screen.active_link);
}

test "DECSET 1000 and 1006 enable mouse tracking" {
    var screen = try Screen.init(std.testing.allocator, 8, 2);
    defer screen.deinit();
    var parser = Parser.init();
    parser.feed(&screen, "\x1b[?1000h\x1b[?1006h");
    try std.testing.expect(screen.mouse_tracking == .x10);
    try std.testing.expect(screen.mouse_sgr);
    parser.feed(&screen, "\x1b[?1000l");
    try std.testing.expect(screen.mouse_tracking == .off);
}

test "CSI scroll repeat is clamped to the region height" {
    var screen = try Screen.init(std.testing.allocator, 8, 4);
    defer screen.deinit();
    screen.scrollback_max = 8;
    var parser = Parser.init();
    parser.feed(&screen, "hello\x1b[9999S");
    try std.testing.expect(screen.scrollback.items.len <= 8);
}
