//! Tab bar: multiple layouts (each tab = one layout tree).

const std = @import("std");
const Layout = @import("layout.zig").Layout;
const Session = @import("../terminal/session.zig").Session;

pub const Tab = struct {
    title: []u8,
    layout: Layout,
};

pub const Tabs = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(Tab) = .empty,
    active: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Tabs {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Tabs) void {
        for (self.items.items) |*tab| {
            self.allocator.free(tab.title);
            tab.layout.deinit();
        }
        self.items.deinit(self.allocator);
    }

    pub fn add(self: *Tabs, title: []const u8, session: *Session) !void {
        const layout = try Layout.init(self.allocator, session);
        const title_owned = try self.allocator.dupe(u8, title);
        try self.items.append(self.allocator, .{
            .title = title_owned,
            .layout = layout,
        });
        self.active = self.items.items.len - 1;
    }

    pub fn current(self: *Tabs) ?*Tab {
        if (self.items.items.len == 0) return null;
        return &self.items.items[self.active];
    }

    pub fn focusedSession(self: *Tabs) ?*Session {
        const tab = self.current() orelse return null;
        return tab.layout.focused;
    }

    pub fn next(self: *Tabs) void {
        if (self.items.items.len == 0) return;
        self.active = (self.active + 1) % self.items.items.len;
    }

    pub fn prev(self: *Tabs) void {
        if (self.items.items.len == 0) return;
        self.active = if (self.active == 0) self.items.items.len - 1 else self.active - 1;
    }

    pub fn closeActive(self: *Tabs) void {
        if (self.items.items.len <= 1) return; // keep at least one
        var tab = self.items.orderedRemove(self.active);
        self.allocator.free(tab.title);
        tab.layout.deinit();
        if (self.active >= self.items.items.len) self.active = self.items.items.len - 1;
    }

    pub fn clear(self: *Tabs) void {
        for (self.items.items) |*tab| {
            self.allocator.free(tab.title);
            tab.layout.deinit();
        }
        self.items.clearRetainingCapacity();
        self.active = 0;
    }

    pub fn addLayout(self: *Tabs, title: []const u8, layout: Layout) !void {
        const title_owned = try self.allocator.dupe(u8, title);
        errdefer self.allocator.free(title_owned);
        try self.items.append(self.allocator, .{
            .title = title_owned,
            .layout = layout,
        });
        self.active = self.items.items.len - 1;
    }

    pub fn setActive(self: *Tabs, index: usize) void {
        if (self.items.items.len == 0) return;
        self.active = @min(index, self.items.items.len - 1);
    }

