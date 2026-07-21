//! Split-pane layout tree for a tab.

const std = @import("std");
const Session = @import("../terminal/session.zig").Session;

pub const Dir = enum { horizontal, vertical };

pub const Node = union(enum) {
    leaf: *Session,
    split: SplitNode,
};

pub const SplitNode = struct {
    dir: Dir,
    ratio: f32 = 0.5, // first child share
    first: *Node,
    second: *Node,
};

pub const Rect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
};

pub const Layout = struct {
    allocator: std.mem.Allocator,
    root: *Node,
    focused: *Session,

    pub fn init(allocator: std.mem.Allocator, session: *Session) !Layout {
        const node = try allocator.create(Node);
        node.* = .{ .leaf = session };
        return .{
            .allocator = allocator,
            .root = node,
            .focused = session,
        };
    }

    pub fn deinit(self: *Layout) void {
        self.freeNode(self.root);
    }

    fn freeNode(self: *Layout, node: *Node) void {
        switch (node.*) {
            .leaf => |s| s.destroy(),
            .split => |sp| {
                self.freeNode(sp.first);
                self.freeNode(sp.second);
            },
        }
        self.allocator.destroy(node);
    }

    pub fn splitFocused(self: *Layout, dir: Dir, new_session: *Session) !void {
        const leaf_node = self.findLeafNode(self.root, self.focused) orelse return error.FocusNotFound;
        const old_session = leaf_node.leaf;

        const first = try self.allocator.create(Node);
        first.* = .{ .leaf = old_session };
        const second = try self.allocator.create(Node);
        second.* = .{ .leaf = new_session };

        leaf_node.* = .{ .split = .{
            .dir = dir,
            .ratio = 0.5,
            .first = first,
            .second = second,
        } };
        self.focused = new_session;
    }

    fn findLeafNode(self: *Layout, node: *Node, target: *Session) ?*Node {
        switch (node.*) {
            .leaf => |s| return if (s == target) node else null,
            .split => |sp| {
                if (self.findLeafNode(sp.first, target)) |n| return n;
                return self.findLeafNode(sp.second, target);
            },
        }
    }

    pub fn focusNext(self: *Layout) void {
        var list: std.ArrayList(*Session) = .empty;
        defer list.deinit(self.allocator);
        self.collect(self.root, &list) catch return;
        if (list.items.len == 0) return;
        var idx: usize = 0;
        for (list.items, 0..) |s, i| {
            if (s == self.focused) {
                idx = i;
                break;
            }
        }
        self.focused = list.items[(idx + 1) % list.items.len];
    }

    fn collect(self: *Layout, node: *Node, list: *std.ArrayList(*Session)) !void {
        switch (node.*) {
            .leaf => |s| try list.append(self.allocator, s),
            .split => |sp| {
                try self.collect(sp.first, list);
                try self.collect(sp.second, list);
            },
        }
    }

    pub fn tickAll(self: *Layout) void {
        self.tickNode(self.root);
    }

    fn tickNode(self: *Layout, node: *Node) void {
        switch (node.*) {
            .leaf => |s| s.tick(),
            .split => |sp| {
                self.tickNode(sp.first);
                self.tickNode(sp.second);
            },
        }
    }

    /// Visit each leaf with its pixel rect (for rendering / hit-test).
    pub fn forEachLeaf(self: *Layout, bounds: Rect, comptime Ctx: type, ctx: Ctx, comptime cb: *const fn (Ctx, *Session, Rect) void) void {
        self.walk(self.root, bounds, Ctx, ctx, cb);
    }

    fn walk(self: *Layout, node: *Node, bounds: Rect, comptime Ctx: type, ctx: Ctx, comptime cb: *const fn (Ctx, *Session, Rect) void) void {
        switch (node.*) {
            .leaf => |s| cb(ctx, s, bounds),
            .split => |sp| {
                if (sp.dir == .horizontal) {
                    const left_w: i32 = @intFromFloat(@as(f32, @floatFromInt(bounds.w)) * sp.ratio);
                    self.walk(sp.first, .{ .x = bounds.x, .y = bounds.y, .w = left_w, .h = bounds.h }, Ctx, ctx, cb);
                    self.walk(sp.second, .{ .x = bounds.x + left_w, .y = bounds.y, .w = bounds.w - left_w, .h = bounds.h }, Ctx, ctx, cb);
                } else {
                    const top_h: i32 = @intFromFloat(@as(f32, @floatFromInt(bounds.h)) * sp.ratio);
                    self.walk(sp.first, .{ .x = bounds.x, .y = bounds.y, .w = bounds.w, .h = top_h }, Ctx, ctx, cb);
                    self.walk(sp.second, .{ .x = bounds.x, .y = bounds.y + top_h, .w = bounds.w, .h = bounds.h - top_h }, Ctx, ctx, cb);
                }
            },
        }
    }

    pub fn sessionAt(self: *Layout, bounds: Rect, px: i32, py: i32) ?*Session {
        const Hit = struct {
            px: i32,
            py: i32,
            found: ?*Session = null,
            fn cb(ctx: *@This(), s: *Session, r: Rect) void {
                if (ctx.px >= r.x and ctx.px < r.x + r.w and ctx.py >= r.y and ctx.py < r.y + r.h) {
                    ctx.found = s;
                }
            }
        };
        var hit: Hit = .{ .px = px, .py = py };
        self.forEachLeaf(bounds, *Hit, &hit, Hit.cb);
        return hit.found;
    }
};
