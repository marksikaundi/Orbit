//! Overlay payload for plugin tool output (AI replies, lint text).

const std = @import("std");
const diagnostics = @import("diagnostics.zig");

pub const max_body: usize = 96 * 1024;

pub const ResultView = struct {
    allocator: std.mem.Allocator,
    title: [72]u8 = undefined,
    title_len: usize = 0,
    body: []u8 = &.{},
    scroll: usize = 0,
    insertable: bool = false,
    return_to_viewer: bool = false,
    jump_line: ?u32 = null,
    jump_col: ?u32 = null,

    pub fn init(allocator: std.mem.Allocator) ResultView {
        return .{ .allocator = allocator };
    }

    pub fn close(self: *ResultView) void {
        if (self.body.len > 0) self.allocator.free(self.body);
        self.body = &.{};
        self.title_len = 0;
        self.scroll = 0;
        self.insertable = false;
        self.return_to_viewer = false;
        self.jump_line = null;
        self.jump_col = null;
    }

    pub fn deinit(self: *ResultView) void {
        self.close();
    }

    pub fn open(self: *ResultView, title: []const u8, body: []const u8, insertable: bool) void {
        self.close();
        const n = @min(title.len, self.title.len);
        @memcpy(self.title[0..n], title[0..n]);
        self.title_len = n;
        const cap = @min(body.len, max_body);
        self.body = self.allocator.dupe(u8, body[0..cap]) catch &.{};
        self.insertable = insertable;
        self.scroll = 0;
    }

    pub fn titleSlice(self: *const ResultView) []const u8 {
        return self.title[0..self.title_len];
    }

    pub fn lineCount(self: *const ResultView) usize {
        if (self.body.len == 0) return 1;
        var n: usize = 1;
        for (self.body) |ch| {
            if (ch == '\n') n += 1;
        }
        if (self.body[self.body.len - 1] == '\n' and n > 1) n -= 1;
        return n;
    }

    pub fn line(self: *const ResultView, index: usize) []const u8 {
        if (self.body.len == 0) return "";
        var i: usize = 0;
        var start: usize = 0;
        var row: usize = 0;
        while (i <= self.body.len) : (i += 1) {
            if (i == self.body.len or self.body[i] == '\n') {
                if (row == index) {
                    var slice = self.body[start..i];
                    if (slice.len > 0 and slice[slice.len - 1] == '\r') slice = slice[0 .. slice.len - 1];
                    return slice;
                }
                row += 1;
                start = i + 1;
            }
        }
        return "";
    }

    pub fn scrollBy(self: *ResultView, delta: i32, visible: usize) void {
        const total = self.lineCount();
        const max_scroll = if (total > visible) total - visible else 0;
        const next: i64 = @as(i64, @intCast(self.scroll)) + delta;
        if (next < 0) {
            self.scroll = 0;
        } else if (next > max_scroll) {
            self.scroll = max_scroll;
        } else {
            self.scroll = @intCast(next);
        }
    }

    pub fn applyUnixDiagnostics(self: *ResultView) void {
        var buf: [diagnostics.max_diagnostics]diagnostics.Diagnostic = undefined;
        const n = diagnostics.parseUnix(self.body, buf[0..]);
        if (n == 0) return;
        self.jump_line = buf[0].line;
        self.jump_col = buf[0].col;
    }
};
