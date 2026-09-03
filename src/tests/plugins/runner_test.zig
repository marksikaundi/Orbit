//! Unit tests — plugin tool runner helpers.

const std = @import("std");
const runner = @import("../../plugins/runner.zig");
const types = @import("../../plugins/types.zig");

test "expand placeholders" {
    const ctx = runner.Context{
        .plugin = "format",
        .action = "format",
        .file = "/tmp/app.js",
        .language = "javascript",
        .cwd = "/tmp",
        .plugin_dir = "/tmp/plugins/format",
        .prompt = "hi",
        .selection = "sel",
    };
    const out = try runner.expand(std.testing.allocator, "fmt {file} in {cwd} ({language})", ctx);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("fmt /tmp/app.js in /tmp (javascript)", out);
}

test "stdinFor prefers buffer then selection" {
    var tool: types.ToolSpec = .{ .stdin = .buffer };
    const ctx = runner.Context{ .buffer = "buf", .selection = "sel" };
    try std.testing.expectEqualStrings("buf", runner.stdinFor(&tool, ctx));
    tool.stdin = .selection;
    try std.testing.expectEqualStrings("sel", runner.stdinFor(&tool, ctx));
    tool.stdin = .none;
    try std.testing.expectEqualStrings("", runner.stdinFor(&tool, ctx));
}

test "run echo when available" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    var plugin: types.Plugin = .{
        .allocator = std.testing.allocator,
        .name = try std.testing.allocator.dupe(u8, "echo"),
        .version = try std.testing.allocator.dupe(u8, "1"),
        .description = try std.testing.allocator.dupe(u8, ""),
        .dir = try std.testing.allocator.dupe(u8, "/tmp"),
        .kind = .commands,
        .commands = &.{},
        .themes = &.{},
        .bindings = &.{},
        .hooks = .{},
        .tool = .{
            .command = try std.testing.allocator.dupe(u8, "echo"),
            .args = blk: {
                var args = try std.testing.allocator.alloc([]u8, 1);
                args[0] = try std.testing.allocator.dupe(u8, "orbit-plugin");
                break :blk args;
            },
            .stdout = .status,
            .timeout_ms = 5000,
        },
        .enabled = true,
    };
    defer plugin.deinit();

    var result = try runner.run(std.testing.allocator, std.testing.io, &plugin, .{});
    defer result.deinit();
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "orbit-plugin") != null);
    try std.testing.expectEqual(@as(u8, 0), result.code);
}
