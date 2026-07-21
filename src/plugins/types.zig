//! Plugin types — commands, themes, hooks, lifecycle.

const std = @import("std");
const Color = @import("../terminal/cell.zig").Color;
const Theme = @import("../config/theme.zig").Theme;

pub const CommandActionKind = enum {
    /// Type payload into the focused PTY (e.g. "ls\r").
    insert,
    /// Show a status-bar message.
    status,
    /// Apply a theme by name (built-in or plugin).
    theme,
    /// Open workspace picker / save — host builtins via id.
    host,
};

pub const PluginCommand = struct {
    id: []u8,
    label: []u8,
    hint: []u8,
    kind: CommandActionKind,
    payload: []u8,

    pub fn deinit(self: *PluginCommand, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.label);
        allocator.free(self.hint);
        allocator.free(self.payload);
    }
};

pub const PluginTheme = struct {
    name: []u8,
    theme: Theme,

    pub fn deinit(self: *PluginTheme, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

pub const Hooks = struct {
    on_load: ?[]u8 = null,
    on_unload: ?[]u8 = null,
    on_workspace_open: ?[]u8 = null,
    on_workspace_save: ?[]u8 = null,
    /// Optional clear-color override as "#rrggbb" (renderer hook).
    clear_color: ?[]u8 = null,

    pub fn deinit(self: *Hooks, allocator: std.mem.Allocator) void {
        if (self.on_load) |s| allocator.free(s);
        if (self.on_unload) |s| allocator.free(s);
        if (self.on_workspace_open) |s| allocator.free(s);
        if (self.on_workspace_save) |s| allocator.free(s);
        if (self.clear_color) |s| allocator.free(s);
        self.* = .{};
    }
};

pub const Plugin = struct {
    allocator: std.mem.Allocator,
    name: []u8,
    version: []u8,
    description: []u8,
    dir: []u8,
    commands: []PluginCommand,
    themes: []PluginTheme,
    hooks: Hooks,
    enabled: bool = true,

    pub fn deinit(self: *Plugin) void {
        for (self.commands) |*c| c.deinit(self.allocator);
        if (self.commands.len > 0) self.allocator.free(self.commands);
        for (self.themes) |*t| t.deinit(self.allocator);
        if (self.themes.len > 0) self.allocator.free(self.themes);
        self.hooks.deinit(self.allocator);
        self.allocator.free(self.name);
        self.allocator.free(self.version);
        self.allocator.free(self.description);
        self.allocator.free(self.dir);
    }
};

pub fn parseHexColor(s: []const u8) ?Color {
    var hex = std.mem.trim(u8, s, " \t\"'");
    if (hex.len > 0 and hex[0] == '#') hex = hex[1..];
    if (hex.len != 6) return null;
    const r = std.fmt.parseInt(u8, hex[0..2], 16) catch return null;
    const g = std.fmt.parseInt(u8, hex[2..4], 16) catch return null;
    const b = std.fmt.parseInt(u8, hex[4..6], 16) catch return null;
    return Color.rgb(r, g, b);
}

pub fn themeFromColors(name: []const u8, fg: Color, bg: Color, cursor: Color, selection: Color) Theme {
    var t = Theme{
        .name = name,
        .foreground = fg,
        .background = bg,
        .cursor = cursor,
        .selection_bg = selection,
        .ansi = undefined,
    };
    // Derive a simple ANSI ramp from fg/bg for plugin themes.
    const base = [_]Color{
        Color.rgb(0, 0, 0),
        Color.rgb(205, 49, 49),
        Color.rgb(13, 188, 121),
        Color.rgb(229, 229, 16),
        Color.rgb(36, 114, 200),
        Color.rgb(188, 63, 188),
        Color.rgb(17, 168, 205),
        fg,
        Color.rgb(102, 102, 102),
        Color.rgb(241, 76, 76),
        Color.rgb(35, 209, 139),
        Color.rgb(245, 245, 67),
        Color.rgb(59, 142, 234),
        Color.rgb(214, 112, 214),
        Color.rgb(41, 184, 219),
        fg,
    };
    t.ansi = base;
    return t;
}
