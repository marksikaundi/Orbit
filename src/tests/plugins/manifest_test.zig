//! Unit tests — plugin manifest parsing.

const std = @import("std");
const manifest = @import("../../plugins/manifest.zig");

test "parse full plugin manifest" {
    const data =
        \\name = "hello"
        \\version = "0.1.0"
        \\description = "Demo"
        \\
        \\[[commands]]
        \\id = "greet"
        \\label = "Say Hello"
        \\hint = "status"
        \\action = "status"
        \\payload = "hi"
        \\
        \\[[themes]]
        \\name = "amber"
        \\foreground = "#ffe0a0"
        \\background = "#1a1408"
        \\cursor = "#ffcc66"
        \\selection = "#3a3020"
        \\
        \\[hooks]
        \\on_load = "status:loaded"
    ;
    var plugin = try manifest.parsePlugin(std.testing.allocator, "/tmp/hello", data);
    defer plugin.deinit();

    try std.testing.expectEqualStrings("hello", plugin.name);
    try std.testing.expectEqual(@as(usize, 1), plugin.commands.len);
    try std.testing.expectEqualStrings("greet", plugin.commands[0].id);
    try std.testing.expectEqual(@as(usize, 1), plugin.themes.len);
    try std.testing.expectEqualStrings("amber", plugin.themes[0].name);
    try std.testing.expectEqual(@as(u8, 0xff), plugin.themes[0].theme.foreground.r);
    try std.testing.expect(plugin.hooks.on_load != null);
}

test "parse insert and host action kinds" {
    const data =
        \\name = "x"
        \\version = "1"
        \\description = ""
        \\[[commands]]
        \\id = "ls"
        \\label = "LS"
        \\action = "insert"
        \\payload = "ls\r"
        \\[[commands]]
        \\id = "ws"
        \\label = "Open WS"
        \\action = "host"
        \\payload = "open_workspace"
    ;
    var plugin = try manifest.parsePlugin(std.testing.allocator, "/tmp/x", data);
    defer plugin.deinit();
    try std.testing.expectEqual(@as(usize, 2), plugin.commands.len);
}
