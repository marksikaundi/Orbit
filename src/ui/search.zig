//! In-terminal text search for the focused session.

const std = @import("std");
const Screen = @import("../terminal/screen.zig").Screen;

pub const Search = struct {
    active: bool = false,
    query: [128]u8 = undefined,
    query_len: usize = 0,
    match_row: ?u16 = null,
    match_col: ?u16 = null,

    pub fn open(self: *Search) void {
        self.active = true;
        self.query_len = 0;
        self.match_row = null;
        self.match_col = null;
    }

    pub fn close(self: *Search) void {
        self.active = false;
        self.query_len = 0;
    }

    pub fn inputChar(self: *Search, codepoint: u32) void {
        if (!self.active) return;
        if (codepoint < 32 or codepoint > 126) return;
        if (self.query_len + 1 >= self.query.len) return;
        self.query[self.query_len] = @intCast(codepoint);
        self.query_len += 1;
    }

    pub fn backspace(self: *Search) void {
        if (self.query_len > 0) self.query_len -= 1;
    }

    pub fn querySlice(self: *const Search) []const u8 {
        return self.query[0..self.query_len];
    }

    pub fn findNext(self: *Search, screen: *const Screen) void {
        const q = self.querySlice();
        if (q.len == 0) return;

        const start_row = if (self.match_row) |r| r else 0;
        const start_col = if (self.match_col) |c| c + 1 else 0;

        var row = start_row;
        while (row < screen.rows) : (row += 1) {
            var line_buf: [512]u8 = undefined;
            const n = screen.lineText(row, line_buf[0..@min(line_buf.len, screen.cols)]);
            const line = line_buf[0..n];
            const from: usize = if (row == start_row) @min(start_col, n) else 0;
            if (from < line.len) {
                if (std.mem.indexOf(u8, line[from..], q)) |rel| {
                    self.match_row = row;
                    self.match_col = @intCast(from + rel);
                    return;
                }
            }
        }
        // Wrap
        row = 0;
        while (row <= start_row) : (row += 1) {
            var line_buf: [512]u8 = undefined;
            const n = screen.lineText(row, line_buf[0..@min(line_buf.len, screen.cols)]);
            const line = line_buf[0..n];
            if (std.mem.indexOf(u8, line, q)) |rel| {
                self.match_row = row;
                self.match_col = @intCast(rel);
                return;
            }
        }
        self.match_row = null;
        self.match_col = null;
    }
};
