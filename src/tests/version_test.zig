//! Unit tests — version module / VERSION file.

const std = @import("std");
const version = @import("../version.zig");

test "VERSION is semver X.Y.Z" {
    try std.testing.expect(version.string.len >= 5);
    var parts = std.mem.splitScalar(u8, version.string, '.');
    var n: usize = 0;
    while (parts.next()) |p| {
        _ = try std.fmt.parseInt(u32, p, 10);
        n += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), n);
}

test "tagged has v prefix" {
    try std.testing.expect(std.mem.startsWith(u8, version.tagged, "v"));
    try std.testing.expectEqualStrings(version.string, version.tagged[1..]);
}
