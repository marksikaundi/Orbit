//! Unit tests — syntax-highlighted file preview.

const std = @import("std");
const Viewer = @import("../../ui/viewer.zig").Viewer;
const viewer_mod = @import("../../ui/viewer.zig");

test "open javascript file detects language and splits lines" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    {
        const file = try tmp.dir.createFile(io, "hello.js", .{});
        defer file.close(io);
        try file.writeStreamingAll(io, "const x = 1;\nfunction hi() {}\n");
    }
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPathFile(io, "hello.js", &buf);

    var v: Viewer = .{};
    v.open(std.testing.allocator, io, buf[0..n], "hello.js");
    defer v.close(std.testing.allocator);

    try std.testing.expect(v.active);
    try std.testing.expectEqual(viewer_mod.Language.javascript, v.language);
    try std.testing.expect(v.lineCount() >= 2);
    try std.testing.expectEqualStrings("const x = 1;", v.line(0));
}

test "python preview is a different language than javascript" {
    try std.testing.expectEqual(viewer_mod.Language.python, viewer_mod.detectLanguage("app.py"));
    try std.testing.expect(viewer_mod.detectLanguage("app.py") != viewer_mod.detectLanguage("app.js"));
}

test "binary files are rejected" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    {
        const file = try tmp.dir.createFile(io, "blob.bin", .{});
        defer file.close(io);
        try file.writeStreamingAll(io, "\x00\x01\x02\x03");
    }
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPathFile(io, "blob.bin", &buf);

    var v: Viewer = .{};
    v.open(std.testing.allocator, io, buf[0..n], "blob.bin");
    defer v.close(std.testing.allocator);

    try std.testing.expect(v.binary);
    try std.testing.expect(v.error_msg != null);
}

test "scroll stays in bounds" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    {
        const file = try tmp.dir.createFile(io, "lines.py", .{});
        defer file.close(io);
        try file.writeStreamingAll(io, "a\nb\nc\nd\ne\n");
    }
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPathFile(io, "lines.py", &buf);

    var v: Viewer = .{};
    v.open(std.testing.allocator, io, buf[0..n], "lines.py");
    defer v.close(std.testing.allocator);

    v.scrollBy(100, 2);
    try std.testing.expect(v.scroll + 2 <= v.lineCount() or v.lineCount() <= 2);
    v.scrollBy(-1000, 2);
    try std.testing.expectEqual(@as(usize, 0), v.scroll);
}

test "insert typing rebuilds lines and marks dirty" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    {
        const file = try tmp.dir.createFile(io, "Main.java", .{});
        defer file.close(io);
        try file.writeStreamingAll(io, "class Main {\n}\n");
    }
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPathFile(io, "Main.java", &buf);

    var v: Viewer = .{};
    v.open(std.testing.allocator, io, buf[0..n], "Main.java");
    defer v.close(std.testing.allocator);

    try std.testing.expectEqual(viewer_mod.Language.java, v.language);
    v.cursor_row = 0;
    v.cursor_col = v.line(0).len;
    v.insertChar(std.testing.allocator, ' ');
    v.insertChar(std.testing.allocator, 'x');
    try std.testing.expect(v.dirty);
    try std.testing.expect(std.mem.endsWith(u8, v.line(0), " x"));
    try std.testing.expect(v.complete_open or v.line(0).len > 0);
}

test "java completion accept inserts println" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    {
        const file = try tmp.dir.createFile(io, "A.java", .{});
        defer file.close(io);
        try file.writeStreamingAll(io, "pri");
    }
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPathFile(io, "A.java", &buf);

    var v: Viewer = .{};
    v.open(std.testing.allocator, io, buf[0..n], "A.java");
    defer v.close(std.testing.allocator);

    v.cursor_col = 3;
    v.refreshCompletion(false);
    try std.testing.expect(v.complete_open);
    try std.testing.expect(v.complete_n > 0);

    var i: usize = 0;
    while (i < v.complete_n) : (i += 1) {
        if (std.mem.indexOf(u8, v.complete_hits[i].label(), "println") != null) {
            v.complete_sel = i;
            break;
        }
    }
    try std.testing.expect(v.acceptCompletion(std.testing.allocator));
    try std.testing.expect(std.mem.indexOf(u8, v.line(0), "println") != null);
}

test "save writes edits back to disk" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    {
        const file = try tmp.dir.createFile(io, "note.py", .{});
        defer file.close(io);
        try file.writeStreamingAll(io, "x = 1");
    }
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPathFile(io, "note.py", &buf);

    var v: Viewer = .{};
    v.open(std.testing.allocator, io, buf[0..n], "note.py");
    defer v.close(std.testing.allocator);

    v.cursor_col = 5;
    v.newline(std.testing.allocator);
    v.insertChar(std.testing.allocator, 'y');
    try std.testing.expect(v.save(io));
    try std.testing.expect(!v.dirty);

    const file = try tmp.dir.openFile(io, "note.py", .{});
    defer file.close(io);
    var read_buf: [64]u8 = undefined;
    var reader = file.reader(io, &read_buf);
    const body = try reader.interface.allocRemaining(std.testing.allocator, .limited(64));
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\ny") != null);
}

test "missing file sets an error" {
    var v: Viewer = .{};
    v.open(std.testing.allocator, std.testing.io, "/this/orbit-missing-preview-file.py", "missing.py");
    defer v.close(std.testing.allocator);
    try std.testing.expect(v.error_msg != null);
    try std.testing.expectEqual(@as(usize, 0), v.lineCount());
}
