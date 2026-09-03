//! Unit tests — Ghostty-compatible keybind parsing and keymap.

const std = @import("std");
const keybind = @import("../../config/keybind.zig");
const Config = @import("../../config/config.zig").Config;
const palette_mod = @import("../../ui/palette.zig");

test "parse ctrl+shift+t = new_tab" {
    const b = try keybind.parseSpec(std.testing.allocator, "ctrl+shift+t=new_tab");
    defer {
        var tmp = b;
        tmp.deinit(std.testing.allocator);
    }
    try std.testing.expect(b.sequence_len == 1);
    try std.testing.expect(b.sequence[0].mods.ctrl);
    try std.testing.expect(b.sequence[0].mods.shift);
    try std.testing.expectEqualStrings("t", b.sequence[0].keySlice());
    try std.testing.expectEqual(palette_mod.Action.new_tab, b.actions[0].app);
}

test "parse Ghostty aliases cmd, option, control" {
    const b = try keybind.parseSpec(std.testing.allocator, "cmd+option+control+k=quit");
    defer {
        var tmp = b;
        tmp.deinit(std.testing.allocator);
    }
    try std.testing.expect(b.sequence[0].mods.super);
    try std.testing.expect(b.sequence[0].mods.alt);
    try std.testing.expect(b.sequence[0].mods.ctrl);
}

test "parse prefixes performable unconsumed all global" {
    const b = try keybind.parseSpec(std.testing.allocator, "performable:unconsumed:ctrl+c=copy_to_clipboard");
    defer {
        var tmp = b;
        tmp.deinit(std.testing.allocator);
    }
    try std.testing.expect(b.prefixes.performable);
    try std.testing.expect(b.prefixes.unconsumed);
    try std.testing.expectEqual(palette_mod.Action.copy_selection, b.actions[0].app);
}

test "parse sequence ctrl+a>n" {
    const b = try keybind.parseSpec(std.testing.allocator, "ctrl+a>n=new_tab");
    defer {
        var tmp = b;
        tmp.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(@as(u8, 2), b.sequence_len);
    try std.testing.expect(b.sequence[0].mods.ctrl);
    try std.testing.expectEqualStrings("a", b.sequence[0].keySlice());
    try std.testing.expectEqualStrings("n", b.sequence[1].keySlice());
}

test "text unescape zig string" {
    const bytes = try keybind.unescapeZigString(std.testing.allocator, "\\x15hello\\n");
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqual(@as(u8, 0x15), bytes[0]);
    try std.testing.expectEqualStrings("hello\n", bytes[1..]);
}

test "csi and esc actions" {
    const csi = try keybind.parseSpec(std.testing.allocator, "up=csi:A");
    defer {
        var tmp = csi;
        tmp.deinit(std.testing.allocator);
    }
    try std.testing.expectEqualStrings("A", csi.actions[0].csi);

    const esc = try keybind.parseSpec(std.testing.allocator, "ctrl+d=esc:d");
    defer {
        var tmp = esc;
        tmp.deinit(std.testing.allocator);
    }
    try std.testing.expectEqualStrings("d", esc.actions[0].esc);
}

test "Ghostty action aliases map to Orbit" {
    const cases = [_]struct { []const u8, palette_mod.Action }{
        .{ "copy_to_clipboard", .copy_selection },
        .{ "paste_from_clipboard", .paste_clipboard },
        .{ "toggle_command_palette", .toggle_palette },
        .{ "new_split:right", .split_right },
        .{ "new_split:down", .split_down },
        .{ "goto_tab:next", .next_tab },
        .{ "goto_tab:previous", .prev_tab },
        .{ "increase_font_size:1", .font_larger },
        .{ "reset_font_size", .font_reset },
        .{ "close_surface", .close_tab },
        .{ "open_config", .settings },
        .{ "scroll_page_up", .scroll_page_up },
        .{ "theme:nord", .theme_nord },
    };
    for (cases) |c| {
        var spec_buf: [64]u8 = undefined;
        const spec = std.fmt.bufPrint(&spec_buf, "f1={s}", .{c[0]}) catch unreachable;
        var b = try keybind.parseSpec(std.testing.allocator, spec);
        defer b.deinit(std.testing.allocator);
        try std.testing.expectEqual(c[1], b.actions[0].app);
    }
}

test "unbind removes a trigger" {
    var km: keybind.Keymap = .{};
    defer km.deinit(std.testing.allocator);
    try km.loadDefaults(std.testing.allocator);
    try km.applyLine(std.testing.allocator, "ctrl+shift+t=unbind");

    const trig = keybind.Trigger.from(.{ .ctrl = true, .shift = true }, "t");
    try std.testing.expect(km.advance(&.{}, trig) == .miss);
}

test "clear wipes defaults then custom bind works" {
    var km: keybind.Keymap = .{};
    defer km.deinit(std.testing.allocator);
    try km.loadDefaults(std.testing.allocator);
    try km.applyLine(std.testing.allocator, "clear");
    try std.testing.expectEqual(@as(usize, 0), km.bindings.items.len);
    try km.applyLine(std.testing.allocator, "ctrl+k=new_tab");
    const trig = keybind.Trigger.from(.{ .ctrl = true }, "k");
    switch (km.advance(&.{}, trig)) {
        .fire => |b| try std.testing.expectEqual(palette_mod.Action.new_tab, b.actions[0].app),
        else => return error.TestUnexpectedResult,
    }
}

test "later bind overwrites earlier trigger" {
    var km: keybind.Keymap = .{};
    defer km.deinit(std.testing.allocator);
    try km.applyLine(std.testing.allocator, "ctrl+k=new_tab");
    try km.applyLine(std.testing.allocator, "ctrl+k=quit");
    const trig = keybind.Trigger.from(.{ .ctrl = true }, "k");
    switch (km.advance(&.{}, trig)) {
        .fire => |b| try std.testing.expectEqual(palette_mod.Action.quit, b.actions[0].app),
        else => return error.TestUnexpectedResult,
    }
}

test "sequence waits then fires" {
    var km: keybind.Keymap = .{};
    defer km.deinit(std.testing.allocator);
    try km.applyLine(std.testing.allocator, "ctrl+a>n=new_tab");

    const a = keybind.Trigger.from(.{ .ctrl = true }, "a");
    try std.testing.expect(km.advance(&.{}, a) == .wait);

    const n = keybind.Trigger.from(.{}, "n");
    var pending = [_]keybind.Trigger{a};
    switch (km.advance(&pending, n)) {
        .fire => |b| try std.testing.expectEqual(palette_mod.Action.new_tab, b.actions[0].app),
        else => return error.TestUnexpectedResult,
    }
}

test "plain bind after sequence unbinds the sequence" {
    var km: keybind.Keymap = .{};
    defer km.deinit(std.testing.allocator);
    try km.applyLine(std.testing.allocator, "ctrl+a>n=new_tab");
    try km.applyLine(std.testing.allocator, "ctrl+a=quit");
    const a = keybind.Trigger.from(.{ .ctrl = true }, "a");
    switch (km.advance(&.{}, a)) {
        .fire => |b| try std.testing.expectEqual(palette_mod.Action.quit, b.actions[0].app),
        else => return error.TestUnexpectedResult,
    }
}

test "chain appends to the last keybind" {
    var km: keybind.Keymap = .{};
    defer km.deinit(std.testing.allocator);
    try km.applyLine(std.testing.allocator, "ctrl+k=new_tab");
    try km.applyLine(std.testing.allocator, "chain=reload_config");
    const trig = keybind.Trigger.from(.{ .ctrl = true }, "k");
    switch (km.advance(&.{}, trig)) {
        .fire => |b| {
            try std.testing.expectEqual(@as(u8, 2), b.action_len);
            try std.testing.expectEqual(palette_mod.Action.new_tab, b.actions[0].app);
            try std.testing.expectEqual(palette_mod.Action.reload_config, b.actions[1].app);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "ignore consumes without an app action" {
    var km: keybind.Keymap = .{};
    defer km.deinit(std.testing.allocator);
    try km.applyLine(std.testing.allocator, "ctrl+q=ignore");
    const trig = keybind.Trigger.from(.{ .ctrl = true }, "q");
    switch (km.advance(&.{}, trig)) {
        .fire => |b| try std.testing.expect(b.actions[0] == .ignore),
        else => return error.TestUnexpectedResult,
    }
}

test "page_up alias and catch_all" {
    var km: keybind.Keymap = .{};
    defer km.deinit(std.testing.allocator);
    try km.applyLine(std.testing.allocator, "page_up=scroll_page_up");
    try km.applyLine(std.testing.allocator, "ctrl+catch_all=ignore");

    const pg = keybind.Trigger.from(.{}, "pageup");
    switch (km.advance(&.{}, pg)) {
        .fire => |b| try std.testing.expectEqual(palette_mod.Action.scroll_page_up, b.actions[0].app),
        else => return error.TestUnexpectedResult,
    }

    const x = keybind.Trigger.from(.{ .ctrl = true }, "x");
    switch (km.advance(&.{}, x)) {
        .fire => |b| try std.testing.expect(b.actions[0] == .ignore),
        else => return error.TestUnexpectedResult,
    }
}

test "physical KeyA and equal aliases" {
    const a = try keybind.parseSpec(std.testing.allocator, "physical:ctrl+key_a=new_tab");
    defer {
        var tmp = a;
        tmp.deinit(std.testing.allocator);
    }
    try std.testing.expectEqualStrings("a", a.sequence[0].keySlice());

    const eq = try keybind.parseSpec(std.testing.allocator, "ctrl+equal=increase_font_size");
    defer {
        var tmp = eq;
        tmp.deinit(std.testing.allocator);
    }
    try std.testing.expectEqualStrings("equal", eq.sequence[0].keySlice());
}

test "duplicate modifiers are rejected" {
    try std.testing.expectError(error.DuplicateModifier, keybind.parseTrigger("ctrl+ctrl+a"));
}

test "config.toml keybind lines overlay defaults" {
    var cfg: Config = .{};
    defer cfg.deinit(std.testing.allocator);
    Config.parseInto(&cfg, std.testing.allocator,
        \\keybind = ctrl+k=reload_config
        \\keybind = "ctrl+shift+t=unbind"
        \\[keybind]
        \\"ctrl+j" = "new_tab"
    );
    try std.testing.expectEqual(@as(usize, 3), cfg.keybind_lines.len);

    const k = keybind.Trigger.from(.{ .ctrl = true }, "k");
    switch (cfg.keymap.advance(&.{}, k)) {
        .fire => |b| try std.testing.expectEqual(palette_mod.Action.reload_config, b.actions[0].app),
        else => return error.TestUnexpectedResult,
    }

    const t = keybind.Trigger.from(.{ .ctrl = true, .shift = true }, "t");
    try std.testing.expect(cfg.keymap.advance(&.{}, t) == .miss);

    const j = keybind.Trigger.from(.{ .ctrl = true }, "j");
    switch (cfg.keymap.advance(&.{}, j)) {
        .fire => |b| try std.testing.expectEqual(palette_mod.Action.new_tab, b.actions[0].app),
        else => return error.TestUnexpectedResult,
    }

    // Defaults still present
    const h = keybind.Trigger.from(.{ .ctrl = true, .shift = true }, "h");
    switch (cfg.keymap.advance(&.{}, h)) {
        .fire => |b| try std.testing.expectEqual(palette_mod.Action.go_home, b.actions[0].app),
        else => return error.TestUnexpectedResult,
    }
}

test "keybind=clear in config drops built-ins" {
    var cfg: Config = .{};
    defer cfg.deinit(std.testing.allocator);
    Config.parseInto(&cfg, std.testing.allocator,
        \\keybind = clear
        \\keybind = ctrl+k=quit
    );
    const t = keybind.Trigger.from(.{ .ctrl = true, .shift = true }, "t");
    try std.testing.expect(cfg.keymap.advance(&.{}, t) == .miss);
    const k = keybind.Trigger.from(.{ .ctrl = true }, "k");
    switch (cfg.keymap.advance(&.{}, k)) {
        .fire => |b| try std.testing.expectEqual(palette_mod.Action.quit, b.actions[0].app),
        else => return error.TestUnexpectedResult,
    }
}

test "unknown action is skipped not crash" {
    var km: keybind.Keymap = .{};
    defer km.deinit(std.testing.allocator);
    km.applyLine(std.testing.allocator, "ctrl+k=not_a_real_action") catch {};
    try std.testing.expectEqual(@as(usize, 0), km.bindings.items.len);
}
