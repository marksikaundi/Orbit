//! Recent workspaces + last-session pointer.

const std = @import("std");
const paths = @import("../platform/paths.zig");

pub const last_name = "__last__";
pub const max_recents = 8;

pub const Entry = struct {
    name: []u8,
    path: []u8,
};

pub const Store = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    last: ?[]u8 = null,
    last_ssh: ?[]u8 = null,
    restore_on_launch: bool = true,
    names: std.ArrayList([]u8) = .empty,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) Store {
        var s: Store = .{ .allocator = allocator, .io = io };
        s.load() catch {};
        return s;
    }

    pub fn deinit(self: *Store) void {
        self.clearNames();
        if (self.last) |n| self.allocator.free(n);
        if (self.last_ssh) |n| self.allocator.free(n);
        self.names.deinit(self.allocator);
    }

    fn clearNames(self: *Store) void {
        for (self.names.items) |n| self.allocator.free(n);
        self.names.clearRetainingCapacity();
    }

    pub fn filePath(self: *Store) ![]u8 {
        return paths.joinConfig(self.allocator, &.{"session.toml"});
    }

    pub fn remember(self: *Store, name: []const u8) void {
        if (name.len == 0 or std.mem.eql(u8, name, last_name)) return;
        // Move to front
        var i: usize = 0;
        while (i < self.names.items.len) {
            if (std.mem.eql(u8, self.names.items[i], name)) {
                const old = self.names.orderedRemove(i);
                self.allocator.free(old);
                break;
            }
            i += 1;
        }
        const owned = self.allocator.dupe(u8, name) catch return;
        self.names.insert(self.allocator, 0, owned) catch {
            self.allocator.free(owned);
            return;
        };
        while (self.names.items.len > max_recents) {
            const drop = self.names.pop().?;
            self.allocator.free(drop);
        }
        if (self.last) |n| self.allocator.free(n);
        self.last = self.allocator.dupe(u8, name) catch null;
        self.save() catch {};
    }

    pub fn setLast(self: *Store, name: []const u8) void {
        if (self.last) |n| self.allocator.free(n);
        self.last = self.allocator.dupe(u8, name) catch null;
        self.save() catch {};
    }

    pub fn setLastSsh(self: *Store, cmd: []const u8) void {
        if (self.last_ssh) |n| self.allocator.free(n);
        self.last_ssh = self.allocator.dupe(u8, cmd) catch null;
        self.save() catch {};
    }

    pub fn lastSsh(self: *const Store) ?[]const u8 {
        return self.last_ssh;
    }

    fn load(self: *Store) !void {
        const path = self.filePath() catch return;
        defer self.allocator.free(path);
        const file = std.Io.Dir.openFileAbsolute(self.io, path, .{}) catch return;
        defer file.close(self.io);
        var buf: [1024]u8 = undefined;
        var reader = file.reader(self.io, &buf);
        const data = reader.interface.allocRemaining(self.allocator, .limited(16 * 1024)) catch return;
        defer self.allocator.free(data);

        var lines = std.mem.splitScalar(u8, data, '\n');
        while (lines.next()) |raw| {
            var line = std.mem.trim(u8, raw, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const key = std.mem.trim(u8, line[0..eq], " \t");
            var val = std.mem.trim(u8, line[eq + 1 ..], " \t");
            if (val.len >= 2 and val[0] == '"' and val[val.len - 1] == '"') {
                val = val[1 .. val.len - 1];
            }
            if (std.mem.eql(u8, key, "last_workspace") or std.mem.eql(u8, key, "last")) {
                if (self.last) |n| self.allocator.free(n);
                self.last = self.allocator.dupe(u8, val) catch null;
            } else if (std.mem.eql(u8, key, "last_ssh")) {
                if (self.last_ssh) |n| self.allocator.free(n);
                self.last_ssh = self.allocator.dupe(u8, val) catch null;
            } else if (std.mem.eql(u8, key, "restore_on_launch")) {
                self.restore_on_launch = std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "1");
            } else if (std.mem.eql(u8, key, "recent")) {
                if (val.len == 0 or std.mem.eql(u8, val, last_name)) continue;
                const owned = self.allocator.dupe(u8, val) catch continue;
                self.names.append(self.allocator, owned) catch self.allocator.free(owned);
            }
        }
    }

    fn save(self: *Store) !void {
        const path = try self.filePath();
        defer self.allocator.free(path);
        if (std.fs.path.dirname(path)) |dir| paths.ensureDir(dir);

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.allocator);
        try out.appendSlice(self.allocator, "# Orbit session — last workspace and recents\n");
        if (self.last) |n| {
            try out.appendSlice(self.allocator, "last_workspace = \"");
            try out.appendSlice(self.allocator, n);
            try out.appendSlice(self.allocator, "\"\n");
        }
        if (self.last_ssh) |n| {
            try out.appendSlice(self.allocator, "last_ssh = \"");
            try out.appendSlice(self.allocator, n);
            try out.appendSlice(self.allocator, "\"\n");
        }
        try out.appendSlice(self.allocator, if (self.restore_on_launch)
            "restore_on_launch = true\n"
        else
            "restore_on_launch = false\n");
        for (self.names.items) |n| {
            try out.appendSlice(self.allocator, "recent = \"");
            try out.appendSlice(self.allocator, n);
            try out.appendSlice(self.allocator, "\"\n");
        }
        const file = try std.Io.Dir.createFileAbsolute(self.io, path, .{});
        defer file.close(self.io);
        try file.writeStreamingAll(self.io, out.items);
    }
};
