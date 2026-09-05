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
        self.focusBy(1);
    }

    pub fn focusPrev(self: *Layout) void {
        self.focusBy(-1);
    }

    fn focusBy(self: *Layout, delta: i32) void {
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
        const n: i32 = @intCast(list.items.len);
        var next = @as(i32, @intCast(idx)) + delta;
        next = @mod(next, n);
        if (next < 0) next += n;
        self.focused = list.items[@intCast(next)];
    }

    /// Close the focused pane. Returns true if the tab still has panes.
    pub fn closeFocused(self: *Layout) bool {
        if (self.root.* == .leaf) {
            // Single pane — caller should close the tab.
            return false;
        }
        const removed = self.removeSession(self.root, self.focused) orelse return true;
        self.root = removed;
        var list: std.ArrayList(*Session) = .empty;
        defer list.deinit(self.allocator);
        self.collect(self.root, &list) catch return true;
        if (list.items.len == 0) return false;
        self.focused = list.items[0];
        return true;
    }

    fn removeSession(self: *Layout, node: *Node, target: *Session) ?*Node {
        switch (node.*) {
            .leaf => |s| {
                if (s != target) return node;
                s.destroy();
                self.allocator.destroy(node);
                return null;
            },
            .split => |sp| {
                const first = self.removeSession(sp.first, target);
                const second = self.removeSession(sp.second, target);
                if (first == null and second == null) {
                    self.allocator.destroy(node);
                    return null;
                }
                if (first == null) {
                    self.allocator.destroy(node);
                    return second;
                }
                if (second == null) {
                    self.allocator.destroy(node);
                    return first;
                }
                node.* = .{ .split = .{
                    .dir = sp.dir,
                    .ratio = sp.ratio,
                    .first = first.?,
                    .second = second.?,
                } };
                return node;
            },
        }
    }

    pub fn setRatioAt(self: *Layout, px: i32, py: i32, bounds: Rect, new_ratio: f32) bool {
        return self.adjustSplit(self.root, bounds, px, py, new_ratio, false);
    }

    /// Update the nearest split seam while the pointer is dragging (no 6px lock).
    pub fn dragRatio(self: *Layout, px: i32, py: i32, bounds: Rect) bool {
        return self.adjustSplit(self.root, bounds, px, py, 0.5, true);
    }

    fn adjustSplit(self: *Layout, node: *Node, bounds: Rect, px: i32, py: i32, ratio: f32, dragging: bool) bool {
        switch (node.*) {
            .leaf => return false,
            .split => |*sp| {
                const clamped = @min(0.85, @max(0.15, ratio));
                if (sp.dir == .horizontal) {
                    const left_w: i32 = @intFromFloat(@as(f32, @floatFromInt(bounds.w)) * sp.ratio);
                    const seam = bounds.x + left_w;
                    if (dragging or @abs(px - seam) <= 6) {
                        const rel = @as(f32, @floatFromInt(px - bounds.x)) / @as(f32, @floatFromInt(@max(1, bounds.w)));
                        sp.ratio = @min(0.85, @max(0.15, rel));
                        return true;
                    }
                    if (px < seam) {
                        return self.adjustSplit(sp.first, .{ .x = bounds.x, .y = bounds.y, .w = left_w, .h = bounds.h }, px, py, clamped, dragging);
                    }
                    return self.adjustSplit(sp.second, .{
                        .x = bounds.x + left_w,
                        .y = bounds.y,
                        .w = bounds.w - left_w,
                        .h = bounds.h,
                    }, px, py, clamped, dragging);
                } else {
                    const top_h: i32 = @intFromFloat(@as(f32, @floatFromInt(bounds.h)) * sp.ratio);
                    const seam = bounds.y + top_h;
                    if (dragging or @abs(py - seam) <= 6) {
                        const rel = @as(f32, @floatFromInt(py - bounds.y)) / @as(f32, @floatFromInt(@max(1, bounds.h)));
                        sp.ratio = @min(0.85, @max(0.15, rel));
                        return true;
                    }
                    if (py < seam) {
                        return self.adjustSplit(sp.first, .{ .x = bounds.x, .y = bounds.y, .w = bounds.w, .h = top_h }, px, py, clamped, dragging);
                    }
                    return self.adjustSplit(sp.second, .{
                        .x = bounds.x,
                        .y = bounds.y + top_h,
                        .w = bounds.w,
                        .h = bounds.h - top_h,
                    }, px, py, clamped, dragging);
                }
            },
        }
    }

    pub fn hitDivider(self: *Layout, bounds: Rect, px: i32, py: i32) bool {
        return self.dividerAt(self.root, bounds, px, py);
    }

    fn dividerAt(self: *Layout, node: *Node, bounds: Rect, px: i32, py: i32) bool {
        switch (node.*) {
            .leaf => return false,
            .split => |sp| {
                if (sp.dir == .horizontal) {
                    const left_w: i32 = @intFromFloat(@as(f32, @floatFromInt(bounds.w)) * sp.ratio);
                    if (@abs(px - (bounds.x + left_w)) <= 6 and py >= bounds.y and py < bounds.y + bounds.h) return true;
                    if (self.dividerAt(sp.first, .{ .x = bounds.x, .y = bounds.y, .w = left_w, .h = bounds.h }, px, py)) return true;
                    return self.dividerAt(sp.second, .{
                        .x = bounds.x + left_w,
                        .y = bounds.y,
                        .w = bounds.w - left_w,
                        .h = bounds.h,
                    }, px, py);
                } else {
                    const top_h: i32 = @intFromFloat(@as(f32, @floatFromInt(bounds.h)) * sp.ratio);
                    if (@abs(py - (bounds.y + top_h)) <= 6 and px >= bounds.x and px < bounds.x + bounds.w) return true;
                    if (self.dividerAt(sp.first, .{ .x = bounds.x, .y = bounds.y, .w = bounds.w, .h = top_h }, px, py)) return true;
                    return self.dividerAt(sp.second, .{
                        .x = bounds.x,
                        .y = bounds.y + top_h,
                        .w = bounds.w,
                        .h = bounds.h - top_h,
                    }, px, py);
                }
            },
        }
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

    pub const PruneResult = enum {
        /// No dead shells.
        none,
        /// At least one pane removed; tab still has sessions.
        changed,
        /// All panes gone — root already freed; do not call `deinit`.
        empty,
    };

    /// Drop panes whose shell has exited.
    pub fn pruneDead(self: *Layout) PruneResult {
        if (!self.anyDead(self.root)) return .none;
        const new_root = self.pruneNode(self.root) orelse return .empty;
        self.root = new_root;
        var list: std.ArrayList(*Session) = .empty;
        defer list.deinit(self.allocator);
        self.collect(self.root, &list) catch return .empty;
        if (list.items.len == 0) return .empty;
        var ok = false;
        for (list.items) |s| {
            if (s == self.focused) {
                ok = true;
                break;
            }
        }
        if (!ok) self.focused = list.items[0];
        return .changed;
    }

    fn anyDead(self: *Layout, node: *Node) bool {
        switch (node.*) {
            .leaf => |s| return !s.alive,
            .split => |sp| return self.anyDead(sp.first) or self.anyDead(sp.second),
        }
    }

    fn pruneNode(self: *Layout, node: *Node) ?*Node {
        switch (node.*) {
            .leaf => |s| {
                if (s.alive) return node;
                s.destroy();
                self.allocator.destroy(node);
                return null;
            },
            .split => |sp| {
                const first = self.pruneNode(sp.first);
                const second = self.pruneNode(sp.second);
                if (first == null and second == null) {
                    self.allocator.destroy(node);
                    return null;
                }
                if (first == null) {
                    self.allocator.destroy(node);
                    return second;
                }
                if (second == null) {
                    self.allocator.destroy(node);
                    return first;
                }
                node.* = .{ .split = .{
                    .dir = sp.dir,
                    .ratio = sp.ratio,
                    .first = first.?,
                    .second = second.?,
                } };
                return node;
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

    pub fn collectSessions(self: *Layout, list: *std.ArrayList(*Session)) !void {
        try self.collect(self.root, list);
    }

    /// Encode layout as expr like `h(0,v(1,2))` plus ratios in DFS split order.
    pub fn encode(self: *Layout, allocator: std.mem.Allocator) !Encoded {
        var sessions: std.ArrayList(*Session) = .empty;
        errdefer sessions.deinit(allocator);
        try self.collect(self.root, &sessions);

        var ratios: std.ArrayList(f32) = .empty;
        errdefer ratios.deinit(allocator);

        var expr: std.ArrayList(u8) = .empty;
        errdefer expr.deinit(allocator);

        var next_idx: usize = 0;
        try encodeNode(self.root, &expr, &ratios, &next_idx, allocator);

        // Focus index
        var focus: usize = 0;
        for (sessions.items, 0..) |s, i| {
            if (s == self.focused) {
                focus = i;
                break;
            }
        }

        return .{
            .expr = try expr.toOwnedSlice(allocator),
            .ratios = try ratios.toOwnedSlice(allocator),
            .sessions = try sessions.toOwnedSlice(allocator),
            .focus = focus,
        };
    }

    pub const Encoded = struct {
        expr: []u8,
        ratios: []f32,
        sessions: []*Session,
        focus: usize,

        pub fn deinitMeta(self: *Encoded, allocator: std.mem.Allocator) void {
            allocator.free(self.expr);
            allocator.free(self.ratios);
            allocator.free(self.sessions);
        }
    };

    fn encodeNode(node: *Node, expr: *std.ArrayList(u8), ratios: *std.ArrayList(f32), next_idx: *usize, allocator: std.mem.Allocator) !void {
        switch (node.*) {
            .leaf => {
                var buf: [16]u8 = undefined;
                const s = try std.fmt.bufPrint(&buf, "{d}", .{next_idx.*});
                try expr.appendSlice(allocator, s);
                next_idx.* += 1;
            },
            .split => |sp| {
                try expr.append(allocator, if (sp.dir == .horizontal) 'h' else 'v');
                try expr.append(allocator, '(');
                try encodeNode(sp.first, expr, ratios, next_idx, allocator);
                try expr.append(allocator, ',');
                try encodeNode(sp.second, expr, ratios, next_idx, allocator);
                try expr.append(allocator, ')');
                try ratios.append(allocator, sp.ratio);
            },
        }
    }

    /// Build layout from sessions + expr (`0`, `h(0,1)`, `v(h(0,1),2)`, …).
    pub fn fromEncoded(
        allocator: std.mem.Allocator,
        sessions: []const *Session,
        expr: []const u8,
        ratios: []const f32,
        focus: usize,
    ) !Layout {
        if (sessions.len == 0) return error.NoSessions;
        var pos: usize = 0;
        var ratio_idx: usize = 0;
        const root = try parseNode(allocator, sessions, expr, &pos, ratios, &ratio_idx);
        const focused = sessions[@min(focus, sessions.len - 1)];
        return .{
            .allocator = allocator,
            .root = root,
            .focused = focused,
        };
    }

    fn parseNode(
        allocator: std.mem.Allocator,
        sessions: []const *Session,
        expr: []const u8,
        pos: *usize,
        ratios: []const f32,
        ratio_idx: *usize,
    ) !*Node {
        if (pos.* >= expr.len) return error.BadLayoutExpr;

        if (expr[pos.*] == 'h' or expr[pos.*] == 'v') {
            const dir: Dir = if (expr[pos.*] == 'h') .horizontal else .vertical;
            pos.* += 1;
            if (pos.* >= expr.len or expr[pos.*] != '(') return error.BadLayoutExpr;
            pos.* += 1;
            const first = try parseNode(allocator, sessions, expr, pos, ratios, ratio_idx);
            errdefer freeNodeStatic(allocator, first);
            if (pos.* >= expr.len or expr[pos.*] != ',') return error.BadLayoutExpr;
            pos.* += 1;
            const second = try parseNode(allocator, sessions, expr, pos, ratios, ratio_idx);
            errdefer freeNodeStatic(allocator, second);
            if (pos.* >= expr.len or expr[pos.*] != ')') return error.BadLayoutExpr;
            pos.* += 1;
            const ratio: f32 = if (ratio_idx.* < ratios.len) ratios[ratio_idx.*] else 0.5;
            if (ratio_idx.* < ratios.len) ratio_idx.* += 1;

            const node = try allocator.create(Node);
            node.* = .{ .split = .{
                .dir = dir,
                .ratio = ratio,
                .first = first,
                .second = second,
            } };
            return node;
        }

        // leaf index
        var num: usize = 0;
        var any = false;
        while (pos.* < expr.len and expr[pos.*] >= '0' and expr[pos.*] <= '9') : (pos.* += 1) {
            any = true;
            num = num * 10 + (expr[pos.*] - '0');
        }
        if (!any or num >= sessions.len) return error.BadLayoutExpr;
        const node = try allocator.create(Node);
        node.* = .{ .leaf = sessions[num] };
        return node;
    }

    fn freeNodeStatic(allocator: std.mem.Allocator, node: *Node) void {
        switch (node.*) {
            .leaf => {}, // sessions owned by caller during build failure
            .split => |sp| {
                freeNodeStatic(allocator, sp.first);
                freeNodeStatic(allocator, sp.second);
            },
        }
        allocator.destroy(node);
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

