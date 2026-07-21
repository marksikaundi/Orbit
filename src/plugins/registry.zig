//! Discover and load plugins from ~/.config/orbit/plugins/<name>/plugin.toml

const std = @import("std");
const types = @import("types.zig");
const manifest = @import("manifest.zig");
const Theme = @import("../config/theme.zig").Theme;
const Color = @import("../terminal/cell.zig").Color;

pub const Registry = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    dir_path: []u8,
    plugins: std.ArrayList(types.Plugin) = .empty,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !Registry {
        const home = std.c.getenv("HOME") orelse return error.NoHome;
        const dir_path = try std.fmt.allocPrint(allocator, "{s}/.config/orbit/plugins", .{std.mem.span(home)});
        errdefer allocator.free(dir_path);
        ensureDir(dir_path);
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
        ensureDir(self.dir_path);
        const dir = std.Io.Dir.openDirAbsolute(self.io, self.dir_path, .{ .iterate = true }) catch return;
        defer dir.close(self.io);

        var it = dir.iterate();
        while (it.next(self.io) catch null) |entry| {
            if (entry.kind != .directory and entry.kind != .sym_link) continue;
            if (entry.name.len == 0 or entry.name[0] == '.') continue;

            const plugin_dir = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.dir_path, entry.name });
            defer self.allocator.free(plugin_dir);
            const toml_path = try std.fmt.allocPrint(self.allocator, "{s}/plugin.toml", .{plugin_dir});
            defer self.allocator.free(toml_path);

            const file = std.Io.Dir.openFileAbsolute(self.io, toml_path, .{}) catch continue;
            defer file.close(self.io);
            var buf: [4096]u8 = undefined;
            var reader = file.reader(self.io, &buf);
            const data = reader.interface.allocRemaining(self.allocator, .limited(128 * 1024)) catch continue;
            defer self.allocator.free(data);

            const plugin = manifest.parsePlugin(self.allocator, plugin_dir, data) catch continue;
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

fn ensureDir(path: []const u8) void {
    var buf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= buf.len) return;
    var i: usize = 1;
    while (i <= path.len) : (i += 1) {
        if (i < path.len and path[i] != '/') continue;
        @memcpy(buf[0..i], path[0..i]);
        buf[i] = 0;
        _ = std.c.mkdir(buf[0..i :0], 0o755);
    }
}
