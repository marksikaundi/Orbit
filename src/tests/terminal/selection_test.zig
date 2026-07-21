//! Unit tests — mouse text selection.

const std = @import("std");
const Selection = @import("../../terminal/selection.zig").Selection;
const Point = @import("../../terminal/selection.zig").Point;
const Screen = @import("../../terminal/screen.zig").Screen;

test "Point.before ordering" {
    const a = Point{ .col = 1, .row = 0 };
    const b = Point{ .col = 0, .row = 1 };
    try std.testing.expect(a.before(b));
    try std.testing.expect(!b.before(a));
}

test "single-line selection contains" {
    var sel: Selection = .{};
    sel.begin(2, 1);
    sel.update(5, 1);
    sel.finish();
    try std.testing.expect(sel.active);
    try std.testing.expect(sel.contains(3, 1));
    try std.testing.expect(sel.contains(2, 1));
    try std.testing.expect(sel.contains(5, 1));
    try std.testing.expect(!sel.contains(1, 1));
    try std.testing.expect(!sel.contains(6, 1));
}

test "reverse drag normalizes" {
    var sel: Selection = .{};
    sel.begin(5, 0);
    sel.update(2, 0);
    sel.finish();
    const n = sel.normalized();
    try std.testing.expectEqual(@as(u16, 2), n.a.col);
    try std.testing.expectEqual(@as(u16, 5), n.b.col);
    try std.testing.expect(sel.contains(3, 0));
}

test "multi-line selection contains" {
    var sel: Selection = .{};
    sel.begin(3, 0);
    sel.update(2, 2);
    sel.finish();
    try std.testing.expect(sel.contains(5, 0)); // from start col to EOL
    try std.testing.expect(sel.contains(0, 1)); // full middle row
    try std.testing.expect(sel.contains(1, 2)); // up to end col
    try std.testing.expect(!sel.contains(3, 2)); // past end
    try std.testing.expect(!sel.contains(2, 0)); // before start on first row
}

test "click without drag clears active" {
    var sel: Selection = .{};
    sel.begin(1, 1);
    sel.finish();
    try std.testing.expect(!sel.active);
}

test "copyText extracts ASCII with newlines" {
    var screen = try Screen.init(std.testing.allocator, 8, 3);
    defer screen.deinit();
    for ("ab") |ch| screen.putChar(ch);
    screen.putChar('\n');
    for ("cd") |ch| screen.putChar(ch);

    var sel: Selection = .{};
    sel.begin(0, 0);
    sel.update(1, 1);
    sel.finish();

    var buf: [32]u8 = undefined;
    const n = sel.copyText(&screen, &buf);
    // Multi-line copy includes the rest of the first row (spaces) by design.
    try std.testing.expect(std.mem.indexOf(u8, buf[0..n], "ab") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf[0..n], "\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf[0..n], "cd") != null);
}

test "clear resets selection" {
    var sel: Selection = .{};
    sel.begin(0, 0);
    sel.update(3, 0);
    sel.finish();
    sel.clear();
    try std.testing.expect(!sel.active);
    try std.testing.expect(!sel.contains(1, 0));
}
