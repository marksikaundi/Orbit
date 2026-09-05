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

    var dash_h = try args.parse(std.testing.allocator, &.{ "orbit", "-h" });
    defer dash_h.deinit(std.testing.allocator);
    try std.testing.expectEqual(args.Action.help, dash_h.action);

    var sub = try args.parse(std.testing.allocator, &.{ "orbit", "help" });
    defer sub.deinit(std.testing.allocator);
    try std.testing.expectEqual(args.Action.help, sub.action);
    try std.testing.expect(sub.cwd == null);

    var v = try args.parse(std.testing.allocator, &.{ "orbit", "-V" });
    defer v.deinit(std.testing.allocator);
    try std.testing.expectEqual(args.Action.version, v.action);
}

test "help catalog covers launch, developer, and plugin commands" {
    try std.testing.expect(std.mem.indexOf(u8, args.help_text, "orbit help") != null);
    try std.testing.expect(std.mem.indexOf(u8, args.help_text, "zig build run") != null);
    try std.testing.expect(std.mem.indexOf(u8, args.help_text, "zig build test") != null);
    try std.testing.expect(std.mem.indexOf(u8, args.help_text, "zig build security-scan") != null);
    try std.testing.expect(std.mem.indexOf(u8, args.help_text, "ide-setup") != null);
    try std.testing.expect(std.mem.indexOf(u8, args.help_text, "orbit update") != null);
    try std.testing.expect(std.mem.indexOf(u8, args.help_text, "ORBIT_FOREGROUND") != null);
    try std.testing.expect(std.mem.indexOf(u8, args.help_text, "git status") != null);
    try std.testing.expect(std.mem.indexOf(u8, args.help_text, "Ctrl+Shift+P") != null);
    try std.testing.expect(std.mem.indexOf(u8, args.help_text, "Format: Document") != null);
}

test "update subcommand and flags" {
    var u = try args.parse(std.testing.allocator, &.{ "orbit", "update" });
    defer u.deinit(std.testing.allocator);
    try std.testing.expectEqual(args.Action.update, u.action);
    try std.testing.expect(!u.update_check);
    try std.testing.expect(!u.update_force);

    var c = try args.parse(std.testing.allocator, &.{ "orbit", "update", "--check" });
    defer c.deinit(std.testing.allocator);
    try std.testing.expectEqual(args.Action.update, c.action);
    try std.testing.expect(c.update_check);

    var f = try args.parse(std.testing.allocator, &.{ "orbit", "--update", "--force", "-c" });
    defer f.deinit(std.testing.allocator);
    try std.testing.expectEqual(args.Action.update, f.action);
    try std.testing.expect(f.update_check);
    try std.testing.expect(f.update_force);

    var r = try args.parse(std.testing.allocator, &.{ "orbit", "--orbit-rebuild", "C:\\src\\Orbit" });
    defer r.deinit(std.testing.allocator);
    try std.testing.expectEqual(args.Action.update, r.action);
    try std.testing.expect(r.update_rebuild);
    try std.testing.expectEqualStrings("C:\\src\\Orbit", r.cwd.?);
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
