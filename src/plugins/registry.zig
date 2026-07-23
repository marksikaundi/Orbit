//! Discover and load plugins from the Orbit config plugins directory.

const std = @import("std");
const types = @import("types.zig");
const manifest = @import("manifest.zig");
const plugin_audit = @import("../security/plugin_audit.zig");
const Theme = @import("../config/theme.zig").Theme;
const Color = @import("../terminal/cell.zig").Color;
const paths = @import("../platform/paths.zig");

pub const Registry = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    dir_path: []u8,
    plugins: std.ArrayList(types.Plugin) = .empty,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !Registry {
        const dir_path = try paths.joinConfig(allocator, &.{"plugins"});
        errdefer allocator.free(dir_path);
        paths.ensureDir(dir_path);
        var reg: Registry = .{
            .allocator = allocator,
            .io = io,
            .dir_path = dir_path,
        };
        try reg.reload();
        return reg;
    }

    pub fn deinit(self: *Registry) void {
        self.clear();
        self.plugins.deinit(self.allocator);
        self.allocator.free(self.dir_path);
    }

    fn clear(self: *Registry) void {
        for (self.plugins.items) |*p| p.deinit();
        self.plugins.clearRetainingCapacity();
    }

    pub fn reload(self: *Registry) !void {
        // Fire unload hooks first (caller may also do this for status UI)
        self.clear();
        paths.ensureDir(self.dir_path);
        const dir = std.Io.Dir.openDirAbsolute(self.io, self.dir_path, .{ .iterate = true }) catch return;
        defer dir.close(self.io);

        var it = dir.iterate();
        while (it.next(self.io) catch null) |entry| {
            // Refuse symlinks so a planted link cannot pull plugins from outside the config tree.
            if (entry.kind != .directory) continue;
            if (entry.name.len == 0 or entry.name[0] == '.') continue;
            if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) continue;

            const plugin_dir = try std.fmt.allocPrint(self.allocator, "{s}{c}{s}", .{ self.dir_path, std.fs.path.sep, entry.name });
            defer self.allocator.free(plugin_dir);
            if (!pluginDirIsContained(self.dir_path, plugin_dir)) {
                std.log.warn("security: skipped plugin `{s}` (path escapes plugins directory)", .{entry.name});
                continue;
            }
            const toml_path = try std.fmt.allocPrint(self.allocator, "{s}{c}plugin.toml", .{ plugin_dir, std.fs.path.sep });
            defer self.allocator.free(toml_path);

            const file = std.Io.Dir.openFileAbsolute(self.io, toml_path, .{}) catch continue;
            defer file.close(self.io);
            var buf: [4096]u8 = undefined;
            var reader = file.reader(self.io, &buf);
            const data = reader.interface.allocRemaining(self.allocator, .limited(128 * 1024)) catch continue;
            defer self.allocator.free(data);

            const plugin = manifest.parsePlugin(self.allocator, plugin_dir, data) catch continue;
            warnRiskyPlugin(&plugin);
            try self.plugins.append(self.allocator, plugin);
        }
    }

    pub fn findTheme(self: *const Registry, name: []const u8) ?Theme {
        for (self.plugins.items) |p| {
            if (!p.enabled) continue;
            for (p.themes) |pt| {
                if (std.mem.eql(u8, pt.name, name)) return pt.theme;
            }
        }
        return null;
    }

    pub fn findCommand(self: *Registry, plugin_name: []const u8, command_id: []const u8) ?*types.PluginCommand {
        for (self.plugins.items) |*p| {
            if (!p.enabled) continue;
            if (!std.mem.eql(u8, p.name, plugin_name)) continue;
            for (p.commands) |*c| {
                if (std.mem.eql(u8, c.id, command_id)) return c;
            }
        }
        return null;
    }

    /// Find a command by id across all enabled plugins.
    pub fn findCommandById(self: *Registry, command_id: []const u8) ?*types.PluginCommand {
        for (self.plugins.items) |*p| {
            if (!p.enabled) continue;
            for (p.commands) |*c| {
                if (std.mem.eql(u8, c.id, command_id)) return c;
            }
        }
        return null;
    }

    /// Match a user key chord against enabled plugin bindings. Returns command id if any.
    pub fn matchBinding(self: *const Registry, key_name: []const u8, ctrl: bool, shift: bool, super: bool, alt: bool) ?[]const u8 {
        for (self.plugins.items) |p| {
            if (!p.enabled) continue;
            for (p.bindings) |b| {
                if (b.matches(key_name, ctrl, shift, super, alt)) return b.command_id;
            }
        }
        return null;
    }

    /// First enabled plugin clear_color hook, if any.
    pub fn rendererClearColor(self: *const Registry) ?Color {
        for (self.plugins.items) |p| {
            if (!p.enabled) continue;
            if (p.hooks.clear_color) |hex| {
                if (types.parseHexColor(hex)) |c| return c;
            }
        }
        return null;
    }

    pub fn forEachHook(self: *const Registry, which: enum { on_load, on_unload, on_workspace_open, on_workspace_save }, comptime Ctx: type, ctx: Ctx, comptime cb: *const fn (Ctx, []const u8) void) void {
        for (self.plugins.items) |p| {
            if (!p.enabled) continue;
            const hook: ?[]const u8 = switch (which) {
                .on_load => p.hooks.on_load,
                .on_unload => p.hooks.on_unload,
                .on_workspace_open => p.hooks.on_workspace_open,
                .on_workspace_save => p.hooks.on_workspace_save,
            };
            if (hook) |h| cb(ctx, h);
        }
    }

    pub fn count(self: *const Registry) usize {
        return self.plugins.items.len;
    }
};

fn warnRiskyPlugin(plugin: *const types.Plugin) void {
    for (plugin.commands) |cmd| {
        if (cmd.kind != .insert) continue;
        const hit = plugin_audit.auditInsertPayload(cmd.payload) orelse continue;
        const action = if (plugin_audit.shouldBlock(hit)) "blocked" else "warning";
        std.log.warn(
            "security: plugin `{s}` command `{s}` [{s}/{s}] {s}",
            .{ plugin.name, cmd.id, hit.severity.label(), action, hit.message },
        );
    }
    warnRiskyHook(plugin, "on_load", plugin.hooks.on_load);
    warnRiskyHook(plugin, "on_unload", plugin.hooks.on_unload);
    warnRiskyHook(plugin, "on_workspace_open", plugin.hooks.on_workspace_open);
    warnRiskyHook(plugin, "on_workspace_save", plugin.hooks.on_workspace_save);
}

fn warnRiskyHook(plugin: *const types.Plugin, which: []const u8, hook: ?[]const u8) void {
    const raw = hook orelse return;
    if (!std.mem.startsWith(u8, raw, "insert:")) return;
    const payload = raw["insert:".len..];
    const hit = plugin_audit.auditInsertPayload(payload) orelse return;
    const action = if (plugin_audit.shouldBlock(hit)) "blocked" else "warning";
    std.log.warn(
        "security: plugin `{s}` hook `{s}` [{s}/{s}] {s}",
        .{ plugin.name, which, hit.severity.label(), action, hit.message },
    );
}

/// True when `plugin_dir` is exactly under `plugins_root` (no `..` escape).
fn pluginDirIsContained(plugins_root: []const u8, plugin_dir: []const u8) bool {
    if (std.mem.indexOf(u8, plugin_dir, "..") != null) return false;
    if (!std.mem.startsWith(u8, plugin_dir, plugins_root)) return false;
    if (plugin_dir.len <= plugins_root.len) return false;
    const sep = plugin_dir[plugins_root.len];
    return sep == std.fs.path.sep or sep == '/' or sep == '\\';
}
