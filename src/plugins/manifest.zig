//! Parse plugin.toml manifests (subset of TOML).

const std = @import("std");
const types = @import("types.zig");
const Color = @import("../terminal/cell.zig").Color;

pub fn parsePlugin(allocator: std.mem.Allocator, dir: []const u8, data: []const u8) !types.Plugin {
    var name = try allocator.dupe(u8, "unnamed");
    errdefer allocator.free(name);
    var version = try allocator.dupe(u8, "0.0.0");
    errdefer allocator.free(version);
    var description = try allocator.dupe(u8, "");
    errdefer allocator.free(description);

    var commands: std.ArrayList(types.PluginCommand) = .empty;
    errdefer {
        for (commands.items) |*c| c.deinit(allocator);
        commands.deinit(allocator);
    }
    var themes: std.ArrayList(types.PluginTheme) = .empty;
    errdefer {
        for (themes.items) |*t| t.deinit(allocator);
        themes.deinit(allocator);
    }
    var bindings: std.ArrayList(types.KeyBinding) = .empty;
    errdefer {
        for (bindings.items) |*b| b.deinit(allocator);
        bindings.deinit(allocator);
    }
    var hooks: types.Hooks = .{};

    var section: enum { root, commands, themes, hooks, bindings } = .root;
    var cur_cmd: ?types.PluginCommand = null;
    var cur_theme_name: ?[]u8 = null;
    var cur_fg: ?Color = null;
    var cur_bg: ?Color = null;
    var cur_cursor: ?Color = null;
    var cur_sel: ?Color = null;
    var cur_bind_keys: ?[]u8 = null;
    var cur_bind_cmd: ?[]u8 = null;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        if (std.mem.eql(u8, line, "[[commands]]")) {
            try flushCommand(allocator, &commands, &bindings, &cur_cmd);
            try flushTheme(allocator, &themes, &cur_theme_name, &cur_fg, &cur_bg, &cur_cursor, &cur_sel);
            try flushBinding(allocator, &bindings, &cur_bind_keys, &cur_bind_cmd);
            section = .commands;
            cur_cmd = .{
                .id = try allocator.dupe(u8, ""),
                .label = try allocator.dupe(u8, "Plugin Command"),
                .hint = try allocator.dupe(u8, ""),
                .kind = .status,
                .payload = try allocator.dupe(u8, ""),
                .shortcut = null,
            };
            continue;
        }
        if (std.mem.eql(u8, line, "[[themes]]")) {
            try flushCommand(allocator, &commands, &bindings, &cur_cmd);
            try flushTheme(allocator, &themes, &cur_theme_name, &cur_fg, &cur_bg, &cur_cursor, &cur_sel);
            try flushBinding(allocator, &bindings, &cur_bind_keys, &cur_bind_cmd);
            section = .themes;
            continue;
        }
        if (std.mem.eql(u8, line, "[[bindings]]")) {
            try flushCommand(allocator, &commands, &bindings, &cur_cmd);
            try flushTheme(allocator, &themes, &cur_theme_name, &cur_fg, &cur_bg, &cur_cursor, &cur_sel);
            try flushBinding(allocator, &bindings, &cur_bind_keys, &cur_bind_cmd);
            section = .bindings;
            continue;
        }
        if (std.mem.eql(u8, line, "[hooks]")) {
            try flushCommand(allocator, &commands, &bindings, &cur_cmd);
            try flushTheme(allocator, &themes, &cur_theme_name, &cur_fg, &cur_bg, &cur_cursor, &cur_sel);
            try flushBinding(allocator, &bindings, &cur_bind_keys, &cur_bind_cmd);
            section = .hooks;
            continue;
        }
        if (line[0] == '[') {
            try flushCommand(allocator, &commands, &bindings, &cur_cmd);
            try flushTheme(allocator, &themes, &cur_theme_name, &cur_fg, &cur_bg, &cur_cursor, &cur_sel);
            try flushBinding(allocator, &bindings, &cur_bind_keys, &cur_bind_cmd);
            section = .root;
            continue;
        }

        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const val = std.mem.trim(u8, line[eq + 1 ..], " \t");

        switch (section) {
            .root => {
                if (std.mem.eql(u8, key, "name")) {
                    allocator.free(name);
                    name = try unquote(allocator, val);
                } else if (std.mem.eql(u8, key, "version")) {
                    allocator.free(version);
                    version = try unquote(allocator, val);
                } else if (std.mem.eql(u8, key, "description")) {
                    allocator.free(description);
                    description = try unquote(allocator, val);
                }
            },
            .commands => {
                const cmd = &(cur_cmd orelse continue);
                if (std.mem.eql(u8, key, "id")) {
                    allocator.free(cmd.id);
                    cmd.id = try unquote(allocator, val);
                } else if (std.mem.eql(u8, key, "label")) {
                    allocator.free(cmd.label);
                    cmd.label = try unquote(allocator, val);
                } else if (std.mem.eql(u8, key, "hint")) {
                    allocator.free(cmd.hint);
                    cmd.hint = try unquote(allocator, val);
                } else if (std.mem.eql(u8, key, "action")) {
                    const a = try unquote(allocator, val);
                    defer allocator.free(a);
                    cmd.kind = parseAction(a);
                } else if (std.mem.eql(u8, key, "payload")) {
                    allocator.free(cmd.payload);
                    cmd.payload = try unquote(allocator, val);
                } else if (std.mem.eql(u8, key, "shortcut") or std.mem.eql(u8, key, "keys")) {
                    if (cmd.shortcut) |s| allocator.free(s);
                    cmd.shortcut = try unquote(allocator, val);
                }
            },
            .themes => {
                if (std.mem.eql(u8, key, "name")) {
                    if (cur_theme_name) |n| allocator.free(n);
                    cur_theme_name = try unquote(allocator, val);
                } else if (std.mem.eql(u8, key, "foreground")) {
                    cur_fg = types.parseHexColor(stripQuotes(val));
                } else if (std.mem.eql(u8, key, "background")) {
                    cur_bg = types.parseHexColor(stripQuotes(val));
                } else if (std.mem.eql(u8, key, "cursor")) {
                    cur_cursor = types.parseHexColor(stripQuotes(val));
                } else if (std.mem.eql(u8, key, "selection")) {
                    cur_sel = types.parseHexColor(stripQuotes(val));
                }
            },
            .bindings => {
                if (std.mem.eql(u8, key, "keys") or std.mem.eql(u8, key, "shortcut")) {
                    if (cur_bind_keys) |s| allocator.free(s);
                    cur_bind_keys = try unquote(allocator, val);
                } else if (std.mem.eql(u8, key, "command") or std.mem.eql(u8, key, "id")) {
                    if (cur_bind_cmd) |s| allocator.free(s);
                    cur_bind_cmd = try unquote(allocator, val);
                }
            },
            .hooks => {
                if (std.mem.eql(u8, key, "on_load")) {
                    if (hooks.on_load) |s| allocator.free(s);
                    hooks.on_load = try unquote(allocator, val);
                } else if (std.mem.eql(u8, key, "on_unload")) {
                    if (hooks.on_unload) |s| allocator.free(s);
                    hooks.on_unload = try unquote(allocator, val);
                } else if (std.mem.eql(u8, key, "on_workspace_open")) {
                    if (hooks.on_workspace_open) |s| allocator.free(s);
                    hooks.on_workspace_open = try unquote(allocator, val);
                } else if (std.mem.eql(u8, key, "on_workspace_save")) {
                    if (hooks.on_workspace_save) |s| allocator.free(s);
                    hooks.on_workspace_save = try unquote(allocator, val);
                } else if (std.mem.eql(u8, key, "clear_color")) {
                    if (hooks.clear_color) |s| allocator.free(s);
                    hooks.clear_color = try unquote(allocator, val);
                }
            },
        }
    }
    try flushCommand(allocator, &commands, &bindings, &cur_cmd);
    try flushTheme(allocator, &themes, &cur_theme_name, &cur_fg, &cur_bg, &cur_cursor, &cur_sel);
    try flushBinding(allocator, &bindings, &cur_bind_keys, &cur_bind_cmd);

    return .{
        .allocator = allocator,
        .name = name,
        .version = version,
        .description = description,
        .dir = try allocator.dupe(u8, dir),
        .commands = try commands.toOwnedSlice(allocator),
        .themes = try themes.toOwnedSlice(allocator),
        .bindings = try bindings.toOwnedSlice(allocator),
        .hooks = hooks,
    };
}

fn flushCommand(
    allocator: std.mem.Allocator,
    list: *std.ArrayList(types.PluginCommand),
    bindings: *std.ArrayList(types.KeyBinding),
    cur: *?types.PluginCommand,
) !void {
    if (cur.*) |*cmd| {
        if (cmd.shortcut) |sc| {
            if (cmd.id.len > 0) {
                const binding = types.parseShortcut(allocator, sc, cmd.id) catch null;
                if (binding) |b| try bindings.append(allocator, b);
            }
            allocator.free(sc);
            cmd.shortcut = null;
        }
        try list.append(allocator, cmd.*);
        cur.* = null;
    }
}

fn flushBinding(
    allocator: std.mem.Allocator,
    list: *std.ArrayList(types.KeyBinding),
    keys: *?[]u8,
    command: *?[]u8,
) !void {
    if (keys.*) |k| {
        defer {
            allocator.free(k);
            keys.* = null;
        }
        if (command.*) |cid| {
            defer {
                allocator.free(cid);
                command.* = null;
            }
            const binding = types.parseShortcut(allocator, k, cid) catch return;
            try list.append(allocator, binding);
        }
    } else if (command.*) |cid| {
        allocator.free(cid);
        command.* = null;
    }
}

fn flushTheme(
    allocator: std.mem.Allocator,
    list: *std.ArrayList(types.PluginTheme),
    name: *?[]u8,
    fg: *?Color,
    bg: *?Color,
    cursor: *?Color,
    sel: *?Color,
) !void {
    if (name.*) |n| {
        const foreground = fg.* orelse Color.rgb(230, 235, 240);
        const background = bg.* orelse Color.rgb(18, 20, 26);
        const cur = cursor.* orelse Color.rgb(120, 180, 255);
        const selection = sel.* orelse Color.rgb(50, 80, 120);
        try list.append(allocator, .{
            .name = n,
            .theme = types.themeFromColors(n, foreground, background, cur, selection),
        });
        name.* = null;
    }
    fg.* = null;
    bg.* = null;
    cursor.* = null;
    sel.* = null;
}

fn parseAction(s: []const u8) types.CommandActionKind {
    if (std.mem.eql(u8, s, "insert")) return .insert;
    if (std.mem.eql(u8, s, "theme")) return .theme;
    if (std.mem.eql(u8, s, "host")) return .host;
    return .status;
}

fn stripQuotes(val: []const u8) []const u8 {
    if (val.len >= 2 and val[0] == '"' and val[val.len - 1] == '"') return val[1 .. val.len - 1];
    return val;
}

fn unquote(allocator: std.mem.Allocator, val: []const u8) ![]u8 {
    const s = stripQuotes(val);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '\\' and i + 1 < s.len) {
            i += 1;
            switch (s[i]) {
                'n' => try out.append(allocator, '\n'),
                'r' => try out.append(allocator, '\r'),
                't' => try out.append(allocator, '\t'),
                else => try out.append(allocator, s[i]),
            }
        } else {
            try out.append(allocator, s[i]);
        }
    }
    return out.toOwnedSlice(allocator);
}
