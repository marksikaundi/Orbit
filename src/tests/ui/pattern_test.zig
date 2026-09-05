const std = @import("std");
const pattern = @import("../../ui/pattern.zig");

test "case-insensitive substring" {
    try std.testing.expectEqual(@as(?usize, 0), pattern.find("Hello", "hello", .{}));
    try std.testing.expectEqual(@as(?usize, null), pattern.find("Hello", "hello", .{ .case_sensitive = true }));
}

test "regex dot and star" {
    try std.testing.expectEqual(@as(?usize, 0), pattern.find("abc", "a.*c", .{ .regex = true }));
    try std.testing.expectEqual(@as(?usize, 1), pattern.find("x123y", "\\d+", .{ .regex = true }));
}

test "regex class" {
    try std.testing.expectEqual(@as(?usize, 2), pattern.find("abZee", "[A-Z]", .{ .regex = true, .case_sensitive = true }));
}
