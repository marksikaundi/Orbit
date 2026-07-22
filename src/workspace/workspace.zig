//! Orbit Workspaces — save/restore tabs, splits, cwd, shell, env, layout.

const std = @import("std");
const Session = @import("../terminal/session.zig").Session;
const Tabs = @import("../ui/tabs.zig").Tabs;
const Layout = @import("../ui/layout.zig").Layout;
const Color = @import("../terminal/cell.zig").Color;
const paths = @import("../platform/paths.zig");

pub const Manager = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    dir_path: []u8,
    names: std.ArrayList([]u8) = .empty,
    current_name: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !Manager {
        const dir_path = try paths.joinConfig(allocator, &.{"workspaces"});
        errdefer allocator.free(dir_path);
        paths.ensureDir(dir_path);
        var m: Manager = .{
            .allocator = allocator,
            .io = io,
            .dir_path = dir_path,
        };
        try m.refresh();
        return m;
    }

    pub fn deinit(self: *Manager) void {
        self.clearNames();
        if (self.current_name) |n| self.allocator.free(n);
        self.allocator.free(self.dir_path);
        self.names.deinit(self.allocator);
    }

    fn clearNames(self: *Manager) void {
        for (self.names.items) |n| self.allocator.free(n);
        self.names.clearRetainingCapacity();
    }

    pub fn refresh(self: *Manager) !void {
        self.clearNames();
        paths.ensureDir(self.dir_path);
        const dir = std.Io.Dir.openDirAbsolute(self.io, self.dir_path, .{ .iterate = true }) catch return;
        defer dir.close(self.io);

        var it = dir.iterate();
        while (it.next(self.io) catch null) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".toml")) continue;
            const name = entry.name[0 .. entry.name.len - 5];
            if (name.len == 0) continue;
            const owned = try self.allocator.dupe(u8, name);
            try self.names.append(self.allocator, owned);
        }
        std.mem.sort([]u8, self.names.items, {}, struct {
            fn less(_: void, a: []u8, b: []u8) bool {
                return std.ascii.lessThanIgnoreCase(a, b);
            }
        }.less);
    }

    pub fn setCurrent(self: *Manager, name: []const u8) !void {
        if (self.current_name) |n| self.allocator.free(n);
        self.current_name = try self.allocator.dupe(u8, name);
    }

    pub fn pathFor(self: *Manager, name: []const u8) ![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}{c}{s}.toml", .{ self.dir_path, std.fs.path.sep, name });
    }

    pub fn saveTabs(self: *Manager, name: []const u8, tabs: *Tabs) !void {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.allocator);

        try out.appendSlice(self.allocator, "name = \"");
        try appendEscaped(&out, self.allocator, name);
        try out.appendSlice(self.allocator, "\"\n");
        try out.print(self.allocator, "active_tab = {d}\n\n", .{tabs.active});

        for (tabs.items.items) |*tab| {
            var encoded = try tab.layout.encode(self.allocator);
            defer encoded.deinitMeta(self.allocator);

            try out.appendSlice(self.allocator, "[[tabs]]\n");
            try out.appendSlice(self.allocator, "title = \"");
            try appendEscaped(&out, self.allocator, tab.title);
            try out.appendSlice(self.allocator, "\"\n");
            try out.appendSlice(self.allocator, "layout = \"");
            try appendEscaped(&out, self.allocator, encoded.expr);
            try out.appendSlice(self.allocator, "\"\n");
            try out.print(self.allocator, "focus = {d}\n", .{encoded.focus});

            if (encoded.ratios.len > 0) {
                try out.appendSlice(self.allocator, "ratios = [");
                for (encoded.ratios, 0..) |r, i| {
                    if (i > 0) try out.appendSlice(self.allocator, ", ");
                    try out.print(self.allocator, "{d:.4}", .{r});
                }
                try out.appendSlice(self.allocator, "]\n");
            }

            for (encoded.sessions) |session| {
                try out.appendSlice(self.allocator, "\n[[tabs.panes]]\n");
                try out.appendSlice(self.allocator, "title = \"");
                try appendEscaped(&out, self.allocator, session.title);
                try out.appendSlice(self.allocator, "\"\n");
                try out.appendSlice(self.allocator, "cwd = \"");
                try appendEscaped(&out, self.allocator, session.cwd);
                try out.appendSlice(self.allocator, "\"\n");
                try out.appendSlice(self.allocator, "shell = \"");
                try appendEscaped(&out, self.allocator, session.shell);
                try out.appendSlice(self.allocator, "\"\n");
                if (session.env.len > 0) {
                    try out.appendSlice(self.allocator, "env = [");
                    for (session.env, 0..) |e, i| {
                        if (i > 0) try out.appendSlice(self.allocator, ", ");
                        try out.append(self.allocator, '"');
                        try appendEscaped(&out, self.allocator, e);
                        try out.append(self.allocator, '"');
                    }
                    try out.appendSlice(self.allocator, "]\n");
                }
            }
            try out.append(self.allocator, '\n');
        }

        paths.ensureDir(self.dir_path);
        const path = try self.pathFor(name);
        defer self.allocator.free(path);
        const file = try std.Io.Dir.createFileAbsolute(self.io, path, .{});
        defer file.close(self.io);
        try file.writeStreamingAll(self.io, out.items);
        try self.setCurrent(name);
        try self.refresh();
    }

    pub fn deleteWorkspace(self: *Manager, name: []const u8) !void {
        const path = try self.pathFor(name);
        defer self.allocator.free(path);
        var path_z: [std.fs.max_path_bytes:0]u8 = undefined;
        if (path.len >= path_z.len) return error.PathTooLong;
        @memcpy(path_z[0..path.len], path);
        path_z[path.len] = 0;
        _ = std.c.unlink(path_z[0..path.len :0]);
        if (self.current_name) |cur| {
            if (std.mem.eql(u8, cur, name)) {
                self.allocator.free(cur);
                self.current_name = null;
            }
        }
        try self.refresh();
    }

    pub fn loadSpec(self: *Manager, name: []const u8) !Loaded {
        const path = try self.pathFor(name);
        defer self.allocator.free(path);

        const file = try std.Io.Dir.openFileAbsolute(self.io, path, .{});
        defer file.close(self.io);
        var buf: [4096]u8 = undefined;
        var reader = file.reader(self.io, &buf);
        const data = try reader.interface.allocRemaining(self.allocator, .limited(256 * 1024));
        errdefer self.allocator.free(data);

        var loaded = try parseWorkspace(self.allocator, data);
        loaded.file_data = data;
        return loaded;
    }

    pub const Loaded = struct {
        allocator: std.mem.Allocator,
        file_data: []u8 = &.{},
        name: []u8,
        active_tab: usize,
        tabs: []TabSpecOwned,

        pub fn deinit(self: *Loaded) void {
            for (self.tabs) |*t| t.deinit(self.allocator);
            self.allocator.free(self.tabs);
            self.allocator.free(self.name);
            if (self.file_data.len > 0) self.allocator.free(self.file_data);
        }
    };

    pub const TabSpecOwned = struct {
        title: []u8,
        layout: []u8,
        ratios: []f32,
        focus: usize,
        panes: []PaneSpecOwned,

        pub fn deinit(self: *TabSpecOwned, allocator: std.mem.Allocator) void {
            allocator.free(self.title);
            allocator.free(self.layout);
            if (self.ratios.len > 0) allocator.free(self.ratios);
            for (self.panes) |*p| p.deinit(allocator);
            if (self.panes.len > 0) allocator.free(self.panes);
        }
    };

    pub const PaneSpecOwned = struct {
        title: []u8,
        cwd: []u8,
        shell: []u8,
        env: [][]u8,

        pub fn deinit(self: *PaneSpecOwned, allocator: std.mem.Allocator) void {
            allocator.free(self.title);
            allocator.free(self.cwd);
            allocator.free(self.shell);
            for (self.env) |e| allocator.free(e);
            if (self.env.len > 0) allocator.free(self.env);
        }
    };

    pub fn applyToTabs(
        self: *Manager,
        loaded: *const Loaded,
        tabs: *Tabs,
        cols: u16,
        rows: u16,
        fg: Color,
        bg: Color,
        scrollback: usize,
    ) !void {
        tabs.clear();

        for (loaded.tabs) |tab_spec| {
            if (tab_spec.panes.len == 0) continue;

            var sessions = try self.allocator.alloc(*Session, tab_spec.panes.len);
            var created: usize = 0;
            errdefer {
                var i: usize = 0;
                while (i < created) : (i += 1) sessions[i].destroy();
                self.allocator.free(sessions);
            }

            for (tab_spec.panes, 0..) |pane, i| {
                var env_refs: []const []const u8 = &.{};
                var env_tmp: ?[][]const u8 = null;
                if (pane.env.len > 0) {
                    const refs = try self.allocator.alloc([]const u8, pane.env.len);
                    for (pane.env, 0..) |e, j| refs[j] = e;
                    env_tmp = refs;
                    env_refs = refs;
                }
                defer if (env_tmp) |r| self.allocator.free(r);

                const session = try Session.createWith(self.allocator, .{
                    .cols = cols,
                    .rows = rows,
                    .title = pane.title,
                    .cwd = pane.cwd,
                    .shell = pane.shell,
                    .env = env_refs,
                });
                session.setTheme(fg, bg);
                session.setScrollback(scrollback);
                sessions[i] = session;
                created += 1;
            }

            const layout = try Layout.fromEncoded(
                self.allocator,
                sessions,
                tab_spec.layout,
                tab_spec.ratios,
                tab_spec.focus,
            );
            self.allocator.free(sessions);
            try tabs.addLayout(tab_spec.title, layout);
        }

        if (tabs.items.items.len == 0) return error.EmptyWorkspace;
        tabs.setActive(loaded.active_tab);
        try self.setCurrent(loaded.name);
    }
};

fn appendEscaped(out: *std.ArrayList(u8), allocator: std.mem.Allocator, s: []const u8) !void {
    for (s) |ch| {
        if (ch == '"' or ch == '\\') try out.append(allocator, '\\');
        try out.append(allocator, ch);
    }
}

fn parseWorkspace(allocator: std.mem.Allocator, data: []const u8) !Manager.Loaded {
    var ws_name = try allocator.dupe(u8, "workspace");
    errdefer allocator.free(ws_name);
    var active_tab: usize = 0;
    var tabs_list: std.ArrayList(Manager.TabSpecOwned) = .empty;
    errdefer {
        for (tabs_list.items) |*t| t.deinit(allocator);
        tabs_list.deinit(allocator);
    }

    var current_tab: ?*Manager.TabSpecOwned = null;
    var in_pane = false;
    var saw_tabs = false;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        if (std.mem.eql(u8, line, "[[tabs]]")) {
            saw_tabs = true;
            try tabs_list.append(allocator, .{
                .title = try allocator.dupe(u8, "Shell"),
                .layout = try allocator.dupe(u8, "0"),
                .ratios = &.{},
                .focus = 0,
                .panes = &.{},
            });
            current_tab = &tabs_list.items[tabs_list.items.len - 1];
            in_pane = false;
            continue;
        }
        if (std.mem.eql(u8, line, "[[tabs.panes]]")) {
            const tab = current_tab orelse continue;
            const new_len = tab.panes.len + 1;
            if (tab.panes.len == 0) {
                tab.panes = try allocator.alloc(Manager.PaneSpecOwned, 1);
            } else {
                tab.panes = try allocator.realloc(tab.panes, new_len);
            }
            tab.panes[new_len - 1] = .{
                .title = try allocator.dupe(u8, "Shell"),
                .cwd = try allocator.dupe(u8, defaultCwd()),
                .shell = try allocator.dupe(u8, defaultShell()),
                .env = &.{},
            };
            in_pane = true;
            continue;
        }

        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const val = std.mem.trim(u8, line[eq + 1 ..], " \t");

        if (!saw_tabs) {
            if (std.mem.eql(u8, key, "name")) {
                allocator.free(ws_name);
                ws_name = try unquoteAlloc(allocator, val);
            } else if (std.mem.eql(u8, key, "active_tab")) {
                active_tab = std.fmt.parseInt(usize, stripQuotes(val), 10) catch 0;
            }
            continue;
        }

        const tab = current_tab orelse continue;
        if (in_pane and tab.panes.len > 0) {
            const pane = &tab.panes[tab.panes.len - 1];
            if (std.mem.eql(u8, key, "title")) {
                allocator.free(pane.title);
                pane.title = try unquoteAlloc(allocator, val);
            } else if (std.mem.eql(u8, key, "cwd")) {
                allocator.free(pane.cwd);
                pane.cwd = try unquoteAlloc(allocator, val);
            } else if (std.mem.eql(u8, key, "shell")) {
                allocator.free(pane.shell);
                pane.shell = try unquoteAlloc(allocator, val);
            } else if (std.mem.eql(u8, key, "env")) {
                for (pane.env) |e| allocator.free(e);
                if (pane.env.len > 0) allocator.free(pane.env);
                pane.env = try parseStringArray(allocator, val);
            }
        } else if (std.mem.eql(u8, key, "title")) {
            allocator.free(tab.title);
            tab.title = try unquoteAlloc(allocator, val);
        } else if (std.mem.eql(u8, key, "layout")) {
            allocator.free(tab.layout);
            tab.layout = try unquoteAlloc(allocator, val);
        } else if (std.mem.eql(u8, key, "focus")) {
            tab.focus = std.fmt.parseInt(usize, stripQuotes(val), 10) catch 0;
        } else if (std.mem.eql(u8, key, "ratios")) {
            if (tab.ratios.len > 0) allocator.free(tab.ratios);
            tab.ratios = try parseFloatArray(allocator, val);
        }
    }

    return .{
        .allocator = allocator,
        .name = ws_name,
        .active_tab = active_tab,
        .tabs = try tabs_list.toOwnedSlice(allocator),
    };
}

fn stripQuotes(val: []const u8) []const u8 {
    if (val.len >= 2 and val[0] == '"' and val[val.len - 1] == '"') {
        return val[1 .. val.len - 1];
    }
    return val;
}

fn unquoteAlloc(allocator: std.mem.Allocator, val: []const u8) ![]u8 {
    const s = stripQuotes(val);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '\\' and i + 1 < s.len) {
            i += 1;
            try out.append(allocator, s[i]);
        } else {
            try out.append(allocator, s[i]);
        }
    }
    return out.toOwnedSlice(allocator);
}

fn parseFloatArray(allocator: std.mem.Allocator, val: []const u8) ![]f32 {
    var s = std.mem.trim(u8, val, " \t");
    if (s.len >= 2 and s[0] == '[' and s[s.len - 1] == ']') s = s[1 .. s.len - 1];
    var list: std.ArrayList(f32) = .empty;
    errdefer list.deinit(allocator);
    var parts = std.mem.splitScalar(u8, s, ',');
    while (parts.next()) |p| {
        const t = std.mem.trim(u8, p, " \t");
        if (t.len == 0) continue;
        try list.append(allocator, std.fmt.parseFloat(f32, t) catch 0.5);
    }
    return list.toOwnedSlice(allocator);
}

fn parseStringArray(allocator: std.mem.Allocator, val: []const u8) ![][]u8 {
    var s = std.mem.trim(u8, val, " \t");
    if (s.len >= 2 and s[0] == '[' and s[s.len - 1] == ']') s = s[1 .. s.len - 1];
    var list: std.ArrayList([]u8) = .empty;
    errdefer {
        for (list.items) |e| allocator.free(e);
        list.deinit(allocator);
    }
    var i: usize = 0;
    while (i < s.len) {
        while (i < s.len and (s[i] == ' ' or s[i] == '\t' or s[i] == ',')) : (i += 1) {}
        if (i >= s.len) break;
        if (s[i] == '"') {
            i += 1;
            const start = i;
            while (i < s.len and s[i] != '"') : (i += 1) {}
            try list.append(allocator, try allocator.dupe(u8, s[start..i]));
            if (i < s.len) i += 1;
        } else {
            const start = i;
            while (i < s.len and s[i] != ',') : (i += 1) {}
            try list.append(allocator, try allocator.dupe(u8, std.mem.trim(u8, s[start..i], " \t")));
        }
    }
    return list.toOwnedSlice(allocator);
}

fn defaultCwd() []const u8 {
    return paths.defaultCwd();
}

fn defaultShell() []const u8 {
    return paths.defaultShell();
}

test "parse float array" {
    const ratios = try parseFloatArray(std.testing.allocator, "[0.5, 0.3]");
    defer std.testing.allocator.free(ratios);
    try std.testing.expectEqual(@as(usize, 2), ratios.len);
}

test "parse workspace toml" {
    const data =
        \\name = "Backend"
        \\active_tab = 0
        \\
        \\[[tabs]]
        \\title = "API"
        \\layout = "0"
        \\focus = 0
        \\
        \\[[tabs.panes]]
        \\title = "shell"
        \\cwd = "/tmp"
        \\shell = "/bin/zsh"
    ;
    const loaded = try parseWorkspace(std.testing.allocator, data);
    defer {
        // file_data empty — only free name/tabs
        for (loaded.tabs) |*t| t.deinit(std.testing.allocator);
        std.testing.allocator.free(loaded.tabs);
        std.testing.allocator.free(loaded.name);
    }
    try std.testing.expectEqualStrings("Backend", loaded.name);
    try std.testing.expectEqual(@as(usize, 1), loaded.tabs.len);
    try std.testing.expectEqualStrings("/tmp", loaded.tabs[0].panes[0].cwd);
}
