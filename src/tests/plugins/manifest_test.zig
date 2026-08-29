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

test "parse command shortcut and [[bindings]]" {
    const data =
        \\name = "keys"
        \\version = "0.1.0"
        \\description = "demo"
        \\
        \\[[commands]]
        \\id = "keys.git"
        \\label = "Git"
        \\action = "insert"
        \\payload = "git status\r"
        \\shortcut = "ctrl+shift+g"
        \\
        \\[[bindings]]
        \\keys = "ctrl+alt+t"
        \\command = "keys.git"
    ;
    var plugin = try manifest.parsePlugin(std.testing.allocator, "/tmp/keys", data);
    defer plugin.deinit();
    try std.testing.expectEqual(@as(usize, 2), plugin.bindings.len);
    try std.testing.expect(plugin.bindings[0].ctrl);
    try std.testing.expect(plugin.bindings[0].shift);
    try std.testing.expectEqualStrings("g", plugin.bindings[0].key_name);
    try std.testing.expectEqualStrings("keys.git", plugin.bindings[0].command_id);
    try std.testing.expect(plugin.bindings[1].alt);
    try std.testing.expectEqualStrings("t", plugin.bindings[1].key_name);
}

test "parse kind tool and run action" {
    const data =
        \\name = "format"
        \\version = "1"
        \\kind = "format"
        \\description = "fmt"
        \\
        \\[tool]
        \\command = "sh"
        \\script = "run.sh"
        \\args = "{file}"
        \\stdin = "buffer"
        \\stdout = "replace"
        \\languages = "javascript, zig"
        \\timeout_ms = 12000
        \\
        \\[[commands]]
        \\id = "format.document"
        \\label = "Format"
        \\action = "run"
        \\payload = "format"
    ;
    var plugin = try manifest.parsePlugin(std.testing.allocator, "/tmp/format", data);
    defer plugin.deinit();
    try std.testing.expect(plugin.kind == .format);
    try std.testing.expect(plugin.tool.hasRunner());
    try std.testing.expectEqualStrings("sh", plugin.tool.command.?);
    try std.testing.expectEqualStrings("run.sh", plugin.tool.script.?);
    try std.testing.expectEqual(@as(usize, 1), plugin.tool.args.len);
    try std.testing.expectEqualStrings("{file}", plugin.tool.args[0]);
    try std.testing.expect(plugin.tool.stdin == .buffer);
    try std.testing.expect(plugin.tool.stdout == .replace);
    try std.testing.expectEqual(@as(u32, 12000), plugin.tool.timeout_ms);
    try std.testing.expect(plugin.tool.matchesLanguage("javascript"));
    try std.testing.expect(plugin.tool.matchesLanguage("zig"));
    try std.testing.expect(!plugin.tool.matchesLanguage("ruby"));
    try std.testing.expectEqual(@as(usize, 1), plugin.commands.len);
    try std.testing.expect(plugin.commands[0].kind == .run);
}

test "tool without commands synthesizes a run command" {
    const data =
        \\name = "lint"
        \\kind = "lint"
        \\[tool]
        \\command = "sh"
        \\script = "run.sh"
    ;
    var plugin = try manifest.parsePlugin(std.testing.allocator, "/tmp/lint", data);
    defer plugin.deinit();
    try std.testing.expect(plugin.kind == .lint);
    try std.testing.expect(plugin.tool.parse == .unix);
    try std.testing.expectEqual(@as(usize, 1), plugin.commands.len);
    try std.testing.expect(plugin.commands[0].kind == .run);
    try std.testing.expectEqualStrings("lint.run", plugin.commands[0].id);
}
