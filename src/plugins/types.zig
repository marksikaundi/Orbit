//! Plugin types — commands, themes, keybindings, hooks, user-owned tools.

const std = @import("std");
const Color = @import("../terminal/cell.zig").Color;
const Theme = @import("../config/theme.zig").Theme;

pub const PluginKind = enum {
    commands,
    theme,
    keys,
    format,
    lint,
    ai,

    pub fn parse(s: []const u8) PluginKind {
        if (eql(s, "theme") or eql(s, "themes")) return .theme;
        if (eql(s, "keys") or eql(s, "keybindings") or eql(s, "shortcuts")) return .keys;
        if (eql(s, "format") or eql(s, "formatter") or eql(s, "fmt")) return .format;
        if (eql(s, "lint") or eql(s, "linter") or eql(s, "lints")) return .lint;
        if (eql(s, "ai") or eql(s, "assistant")) return .ai;
        return .commands;
    }

    pub fn label(self: PluginKind) []const u8 {
        return switch (self) {
            .commands => "commands",
            .theme => "theme",
            .keys => "keys",
            .format => "format",
            .lint => "lint",
            .ai => "ai",
        };
    }

    pub fn badge(self: PluginKind) []const u8 {
        return switch (self) {
            .commands => "CMD",
            .theme => "THEME",
            .keys => "KEYS",
            .format => "FMT",
            .lint => "LINT",
            .ai => "AI",
        };
    }
};

pub const StdinSource = enum {
    none,
    buffer,
    selection,

    pub fn parse(s: []const u8) StdinSource {
        if (eql(s, "buffer") or eql(s, "file") or eql(s, "stdin")) return .buffer;
        if (eql(s, "selection") or eql(s, "sel")) return .selection;
        return .none;
    }
};

pub const StdoutMode = enum {
    discard,
    replace,
    insert,
    overlay,
    status,

    pub fn parse(s: []const u8) StdoutMode {
        if (eql(s, "replace") or eql(s, "rewrite")) return .replace;
        if (eql(s, "insert")) return .insert;
        if (eql(s, "status")) return .status;
        if (eql(s, "discard") or eql(s, "none")) return .discard;
        return .overlay;
    }
};

pub const ParseFormat = enum {
    none,
    unix,

    pub fn parse(s: []const u8) ParseFormat {
        if (eql(s, "unix") or eql(s, "gcc")) return .unix;
        return .none;
    }
};

pub const CommandActionKind = enum {
    /// Type payload into the focused PTY (e.g. "ls\r").
    insert,
    /// Show a status-bar message.
    status,
    /// Apply a theme by name (built-in or plugin).
    theme,
    /// Open workspace picker / save — host builtins via id.
    host,
    /// Run this plugin's `[tool]` with the user's own command/script.
    run,
};

fn eql(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

pub const PluginCommand = struct {
    id: []u8,
    label: []u8,
    hint: []u8,
    kind: CommandActionKind,
    payload: []u8,
    /// Optional shortcut string from manifest (e.g. "ctrl+shift+g"); owned until binding is built.
    shortcut: ?[]u8 = null,

    pub fn deinit(self: *PluginCommand, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.label);
        allocator.free(self.hint);
        allocator.free(self.payload);
        if (self.shortcut) |s| allocator.free(s);
    }
};

pub const PluginTheme = struct {
    name: []u8,
    theme: Theme,

    pub fn deinit(self: *PluginTheme, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

/// User-defined shortcut that runs a plugin command.
pub const KeyBinding = struct {
    ctrl: bool = false,
    shift: bool = false,
    super: bool = false,
    alt: bool = false,
    /// Key token: letter, digit, or name like "enter".
    key_name: []u8,
    command_id: []u8,

    pub fn deinit(self: *KeyBinding, allocator: std.mem.Allocator) void {
        allocator.free(self.key_name);
        allocator.free(self.command_id);
    }

    pub fn matches(self: *const KeyBinding, key_name: []const u8, ctrl: bool, shift: bool, super: bool, alt: bool) bool {
        return self.ctrl == ctrl and self.shift == shift and self.super == super and self.alt == alt and std.ascii.eqlIgnoreCase(self.key_name, key_name);
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

/// User-owned executable. Orbit never ships an AI/lint/format engine — it runs yours.
pub const ToolSpec = struct {
    command: ?[]u8 = null,
    script: ?[]u8 = null,
    args: [][]u8 = &.{},
    languages: [][]u8 = &.{},
    stdin: StdinSource = .none,
    stdout: StdoutMode = .overlay,
    parse: ParseFormat = .none,
    timeout_ms: u32 = 20_000,
    prompt: ?[]u8 = null,

    pub fn hasRunner(self: *const ToolSpec) bool {
        if (self.command) |c| {
            if (c.len > 0) return true;
        }
        if (self.script) |s| {
            if (s.len > 0) return true;
        }
        return false;
    }

    pub fn matchesLanguage(self: *const ToolSpec, lang: []const u8) bool {
        if (self.languages.len == 0) return true;
        if (lang.len == 0) return true;
        for (self.languages) |item| {
            if (eql(item, "*") or eql(item, "any") or eql(item, "all")) return true;
            if (eql(item, lang)) return true;
        }
        return false;
    }

    pub fn deinit(self: *ToolSpec, allocator: std.mem.Allocator) void {
        if (self.command) |s| allocator.free(s);
        if (self.script) |s| allocator.free(s);
        if (self.prompt) |s| allocator.free(s);
        for (self.args) |a| allocator.free(a);
        if (self.args.len > 0) allocator.free(self.args);
        for (self.languages) |l| allocator.free(l);
        if (self.languages.len > 0) allocator.free(self.languages);
        self.* = .{};
    }
};

pub const Plugin = struct {
    allocator: std.mem.Allocator,
    name: []u8,
    version: []u8,
    description: []u8,
    dir: []u8,
    kind: PluginKind = .commands,
    commands: []PluginCommand,
    themes: []PluginTheme,
    bindings: []KeyBinding,
    hooks: Hooks,
    tool: ToolSpec = .{},
    enabled: bool = true,

    pub fn deinit(self: *Plugin) void {
        for (self.commands) |*c| c.deinit(self.allocator);
        if (self.commands.len > 0) self.allocator.free(self.commands);
        for (self.themes) |*t| t.deinit(self.allocator);
        if (self.themes.len > 0) self.allocator.free(self.themes);
        for (self.bindings) |*b| b.deinit(self.allocator);
        if (self.bindings.len > 0) self.allocator.free(self.bindings);
        self.hooks.deinit(self.allocator);
        self.tool.deinit(self.allocator);
        self.allocator.free(self.name);
        self.allocator.free(self.version);
        self.allocator.free(self.description);
        self.allocator.free(self.dir);
    }
};

/// Parse "ctrl+shift+g" / "cmd+k" into a KeyBinding (command_id provided).
pub fn parseShortcut(allocator: std.mem.Allocator, raw: []const u8, command_id: []const u8) !KeyBinding {
    var ctrl = false;
    var shift = false;
    var super = false;
    var alt = false;
    var key_name: ?[]const u8 = null;

    var it = std.mem.splitScalar(u8, raw, '+');
    while (it.next()) |part_raw| {
        const part = std.mem.trim(u8, part_raw, " \t");
        if (part.len == 0) continue;
        if (std.ascii.eqlIgnoreCase(part, "ctrl") or std.ascii.eqlIgnoreCase(part, "control")) {
            ctrl = true;
        } else if (std.ascii.eqlIgnoreCase(part, "shift")) {
            shift = true;
        } else if (std.ascii.eqlIgnoreCase(part, "cmd") or std.ascii.eqlIgnoreCase(part, "super") or std.ascii.eqlIgnoreCase(part, "meta")) {
            super = true;
        } else if (std.ascii.eqlIgnoreCase(part, "alt") or std.ascii.eqlIgnoreCase(part, "option")) {
            alt = true;
        } else {
            key_name = part;
        }
    }

    const kn = key_name orelse return error.InvalidShortcut;
    return .{
        .ctrl = ctrl,
        .shift = shift,
        .super = super,
        .alt = alt,
        .key_name = try allocator.dupe(u8, kn),
        .command_id = try allocator.dupe(u8, command_id),
    };
}

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
