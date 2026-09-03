//! Unit tests — unix diagnostic parsing.

const std = @import("std");
const diagnostics = @import("../../plugins/diagnostics.zig");

test "parse unix file:line:col: message" {
    const d = diagnostics.parseUnixLine("src/app.zig:12:4: unused variable") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("src/app.zig", d.path);
    try std.testing.expectEqual(@as(u32, 12), d.line);
    try std.testing.expectEqual(@as(u32, 4), d.col);
    try std.testing.expectEqualStrings("unused variable", d.message);
}

test "parse unix file:line: message without column" {
    const d = diagnostics.parseUnixLine("/tmp/a.py:3: missing comma") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 3), d.line);
    try std.testing.expectEqual(@as(u32, 1), d.col);
    try std.testing.expectEqualStrings("missing comma", d.message);
}

test "parseUnix collects multiple lines" {
    const text =
        \\app.js:1:1: missing semicolon
        \\not a diagnostic
        \\app.js:4:2: unused
        \\
    ;
    var buf: [8]diagnostics.Diagnostic = undefined;
    const n = diagnostics.parseUnix(text, &buf);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqual(@as(u32, 1), buf[0].line);
    try std.testing.expectEqual(@as(u32, 4), buf[1].line);
}

test "viewerPos is zero-based" {
    const pos = diagnostics.viewerPos(.{ .path = "a", .line = 10, .col = 3, .message = "x" });
    try std.testing.expectEqual(@as(usize, 9), pos.row);
    try std.testing.expectEqual(@as(usize, 2), pos.col);
}
