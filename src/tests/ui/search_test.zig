//! Unit tests — terminal + workspace search.

const std = @import("std");
const Search = @import("../../ui/search.zig").Search;
const Mode = @import("../../ui/search.zig").Mode;
const Screen = @import("../../terminal/screen.zig").Screen;

test "open close and query editing" {
    var s: Search = .{};
    s.open(std.testing.allocator, "/tmp");
    defer s.close(std.testing.allocator);
    try std.testing.expect(s.active);
    s.inputChar('f');
    s.inputChar('o');
    s.inputChar('o');
    try std.testing.expectEqualStrings("foo", s.querySlice());
    s.backspace();
    try std.testing.expectEqualStrings("fo", s.querySlice());
}

test "ignores control and non-ascii input" {
    var s: Search = .{};
    s.open(std.testing.allocator, null);
    defer s.close(std.testing.allocator);
    s.inputChar(7);
    s.inputChar(0x1F600);
    try std.testing.expectEqual(@as(usize, 0), s.query_len);
}

test "refreshTerminal locates matches case-insensitively" {
    var screen = try Screen.init(std.testing.allocator, 20, 3);
    defer screen.deinit();
    for ("Hello World") |ch| screen.putChar(ch);
    screen.lineFeed();
    screen.cursor_col = 0;
    for ("hello again") |ch| screen.putChar(ch);

    var s: Search = .{};
    s.open(std.testing.allocator, null);
    defer s.close(std.testing.allocator);
    for ("hello") |ch| s.inputChar(ch);
    s.refreshTerminal(&screen);
    try std.testing.expect(s.term_count >= 2);
    try std.testing.expectEqual(@as(usize, 0), s.term_hits[0].abs_row);
    try std.testing.expectEqual(@as(usize, 0), s.term_hits[0].col);
}

test "refreshTerminal empty query has no hits" {
    var screen = try Screen.init(std.testing.allocator, 10, 2);
    defer screen.deinit();
    for ("abc") |ch| screen.putChar(ch);

    var s: Search = .{};
    s.open(std.testing.allocator, null);
    defer s.close(std.testing.allocator);
    s.refreshTerminal(&screen);
    try std.testing.expectEqual(@as(usize, 0), s.term_count);
}

test "toggleMode cycles terminal, files, and code" {
    var s: Search = .{};
    s.open(std.testing.allocator, "/tmp");
    defer s.close(std.testing.allocator);
    try std.testing.expectEqual(Mode.terminal, s.mode);
    s.toggleMode();
    try std.testing.expectEqual(Mode.files, s.mode);
    s.toggleMode();
    try std.testing.expectEqual(Mode.code, s.mode);
    s.toggleMode();
    try std.testing.expectEqual(Mode.terminal, s.mode);
}

test "indexOfIgnoreCase" {
    const search = @import("../../ui/search.zig");
    try std.testing.expectEqual(@as(?usize, 0), search.indexOfIgnoreCase("Hello", "hello"));
    try std.testing.expectEqual(@as(?usize, 6), search.indexOfIgnoreCase("abcde Hello", "hello"));
    try std.testing.expectEqual(@as(?usize, null), search.indexOfIgnoreCase("abc", "zzz"));
}

test "refreshFiles matches names under a folder" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    {
        const file = try tmp.dir.createFile(io, "Hello.java", .{});
        defer file.close(io);
        try file.writeStreamingAll(io, "class Hello {}\n");
    }
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buf);

    var s: Search = .{};
    s.open(std.testing.allocator, buf[0..n]);
    defer s.close(std.testing.allocator);
    s.mode = .files;
    for ("hello") |ch| s.inputChar(ch);
    s.refreshFiles(std.testing.allocator, io);
    try std.testing.expect(s.file_count >= 1);
    try std.testing.expect(std.mem.indexOf(u8, s.file_hits[0], "Hello.java") != null);
}

test "refreshCode finds text inside a file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    {
        const file = try tmp.dir.createFile(io, "App.java", .{});
        defer file.close(io);
        try file.writeStreamingAll(io, "public class App {\n    System.out.println(\"hi\");\n}\n");
    }
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buf);

    var s: Search = .{};
    s.open(std.testing.allocator, buf[0..n]);
    defer s.close(std.testing.allocator);
    s.mode = .code;
    for ("println") |ch| s.inputChar(ch);
    s.refreshCode(std.testing.allocator, io);
    try std.testing.expect(s.code_count >= 1);
    try std.testing.expectEqual(@as(usize, 1), s.code_hits[0].line);
    try std.testing.expect(std.mem.indexOf(u8, s.code_hits[0].rel, "App.java") != null);
    try std.testing.expect(std.mem.indexOf(u8, s.code_hits[0].snippetSlice(), "println") != null);
}
