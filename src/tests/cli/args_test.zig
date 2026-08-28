//! Unit tests — IDE / launch CLI parsing.

const std = @import("std");
const args = @import("../../cli/args.zig");

test "no args stays on home" {
    var launch = try args.parse(std.testing.allocator, &.{"orbit"});
    defer launch.deinit(std.testing.allocator);
    try std.testing.expectEqual(args.Action.run, launch.action);
    try std.testing.expect(!launch.skip_home);
    try std.testing.expect(launch.cwd == null);
}

test "working-directory equals form skips home" {
    var launch = try args.parse(std.testing.allocator, &.{ "orbit", "--working-directory=/tmp/proj" });
    defer launch.deinit(std.testing.allocator);
    try std.testing.expect(launch.skip_home);
    try std.testing.expectEqualStrings("/tmp/proj", launch.cwd.?);
}

test "ghostty kitty konsole flag aliases" {
    const cases = [_][]const []const u8{
        &.{ "orbit", "--cwd", "/a" },
        &.{ "orbit", "--workdir", "/a" },
        &.{ "orbit", "--directory", "/a" },
        &.{ "orbit", "-d", "/a" },
    };
    for (cases) |argv| {
        var launch = try args.parse(std.testing.allocator, argv);
        defer launch.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings("/a", launch.cwd.?);
        try std.testing.expect(launch.skip_home);
    }
}

test "positional folder" {
    var launch = try args.parse(std.testing.allocator, &.{ "orbit", "/Users/me/code" });
    defer launch.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("/Users/me/code", launch.cwd.?);
}

test "command after -e" {
    var launch = try args.parse(std.testing.allocator, &.{ "orbit", "-e", "git", "status" });
    defer launch.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), launch.execute.len);
    try std.testing.expectEqualStrings("git", launch.execute[0]);
    try std.testing.expectEqualStrings("status", launch.execute[1]);
    try std.testing.expect(launch.skip_home);
}

test "command after --" {
    var launch = try args.parse(std.testing.allocator, &.{ "orbit", "--working-directory=/tmp", "--", "bash", "-c", "ls" });
    defer launch.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("/tmp", launch.cwd.?);
    try std.testing.expectEqual(@as(usize, 3), launch.execute.len);
    try std.testing.expectEqualStrings("bash", launch.execute[0]);
}

test "help and version" {
    var h = try args.parse(std.testing.allocator, &.{ "orbit", "--help" });
    defer h.deinit(std.testing.allocator);
    try std.testing.expectEqual(args.Action.help, h.action);

    var v = try args.parse(std.testing.allocator, &.{ "orbit", "-V" });
    defer v.deinit(std.testing.allocator);
    try std.testing.expectEqual(args.Action.version, v.action);
}

test "ide-setup with editor" {
    var launch = try args.parse(std.testing.allocator, &.{ "orbit", "ide-setup", "--editor", "cursor" });
    defer launch.deinit(std.testing.allocator);
    try std.testing.expectEqual(args.Action.ide_setup, launch.action);
    try std.testing.expectEqualStrings("cursor", launch.editor.?);
}

test "unknown flag errors" {
    try std.testing.expectError(error.UnknownArgument, args.parse(std.testing.allocator, &.{ "orbit", "--nope" }));
}

test "missing directory value errors" {
    try std.testing.expectError(error.MissingValue, args.parse(std.testing.allocator, &.{ "orbit", "--working-directory" }));
}

test "wait-after-command" {
    var launch = try args.parse(std.testing.allocator, &.{ "orbit", "--wait-after-command=true", "-e", "make" });
    defer launch.deinit(std.testing.allocator);
    try std.testing.expect(launch.wait_after_command);
    try std.testing.expectEqualStrings("make", launch.execute[0]);
}
