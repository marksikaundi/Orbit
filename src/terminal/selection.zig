//! Mouse-driven text selection over the terminal grid.

const std = @import("std");
const Screen = @import("screen.zig").Screen;

pub const Point = struct {
    col: u16,
    row: u16,

    pub fn before(self: Point, other: Point) bool {
        if (self.row != other.row) return self.row < other.row;
        return self.col < other.col;
    }
};

pub const Kind = enum { stream, word, line, rect };

pub const Selection = struct {
    active: bool = false,
    selecting: bool = false,
    kind: Kind = .stream,
    start: Point = .{ .col = 0, .row = 0 },
    end: Point = .{ .col = 0, .row = 0 },

    pub fn clear(self: *Selection) void {
        self.active = false;
        self.selecting = false;
    }

    pub fn begin(self: *Selection, col: u16, row: u16) void {
        self.beginKind(col, row, .stream);
    }

    pub fn beginKind(self: *Selection, col: u16, row: u16, kind: Kind) void {
        self.active = true;
        self.selecting = true;
        self.kind = kind;
        self.start = .{ .col = col, .row = row };
        self.end = self.start;
    }

    pub fn update(self: *Selection, col: u16, row: u16) void {
        if (!self.selecting) return;
        self.end = .{ .col = col, .row = row };
    }

    pub fn finish(self: *Selection) void {
        self.selecting = false;
        if (self.start.col == self.end.col and self.start.row == self.end.row) {
            self.active = false;
        }
    }

    pub fn normalized(self: *const Selection) struct { a: Point, b: Point } {
        if (self.start.before(self.end) or (self.start.col == self.end.col and self.start.row == self.end.row)) {
            return .{ .a = self.start, .b = self.end };
        }
        return .{ .a = self.end, .b = self.start };
    }

    pub fn contains(self: *const Selection, col: u16, row: u16) bool {
        if (!self.active) return false;
        const n = self.normalized();
        if (self.kind == .rect) {
            const c0 = @min(n.a.col, n.b.col);
            const c1 = @max(n.a.col, n.b.col);
            return row >= n.a.row and row <= n.b.row and col >= c0 and col <= c1;
        }
        if (self.kind == .line) {
            return row >= n.a.row and row <= n.b.row;
        }
        const p = Point{ .col = col, .row = row };
        if (p.row < n.a.row or p.row > n.b.row) return false;
        if (n.a.row == n.b.row) {
            return col >= n.a.col and col <= n.b.col;
        }
        if (p.row == n.a.row) return col >= n.a.col;
        if (p.row == n.b.row) return col <= n.b.col;
        return true;
    }

    pub fn selectWord(self: *Selection, screen: *const Screen, col: u16, row: u16) void {
        const bounds = wordBounds(screen, col, row);
        self.active = true;
        self.selecting = false;
        self.kind = .word;
        self.start = .{ .col = bounds.lo, .row = row };
        self.end = .{ .col = bounds.hi, .row = row };
    }

    pub fn selectLine(self: *Selection, screen: *const Screen, row: u16) void {
        self.active = true;
        self.selecting = false;
        self.kind = .line;
        self.start = .{ .col = 0, .row = row };
        self.end = .{ .col = screen.cols -| 1, .row = row };
    }

    /// Write selected text into `buf`, returns bytes written (truncated if needed).
    pub fn copyText(self: *const Selection, screen: *const Screen, buf: []u8) usize {
        if (!self.active or buf.len == 0) return 0;
        const n = self.normalized();
        var out: usize = 0;
        var row = n.a.row;
        while (row <= n.b.row) : (row += 1) {
            const start_col: u16, const end_col: u16 = switch (self.kind) {
                .rect => .{ @min(n.a.col, n.b.col), @max(n.a.col, n.b.col) },
                .line => .{ 0, screen.cols -| 1 },
                else => .{
                    if (row == n.a.row) n.a.col else 0,
                    if (row == n.b.row) n.b.col else screen.cols -| 1,
                },
            };
            var col = start_col;
            while (col <= end_col) : (col += 1) {
                const cell = screen.visibleCell(col, row);
                if (cell.wide == 2) continue;
                out += utf8Put(buf, out, cell.codepoint);
                if (out >= buf.len) return out;
            }
            if (row < n.b.row) {
                if (out >= buf.len) return out;
                buf[out] = '\n';
                out += 1;
            }
        }
        return out;
    }
};

fn utf8Put(buf: []u8, at: usize, cp: u21) usize {
    if (cp == 0 or cp == ' ') {
        if (at >= buf.len) return 0;
        buf[at] = ' ';
        return 1;
    }
    if (cp < 0x80) {
        if (at >= buf.len) return 0;
        buf[at] = @intCast(cp);
        return 1;
    }
    var tmp: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(cp, &tmp) catch return 0;
    if (at + n > buf.len) return 0;
    @memcpy(buf[at .. at + n], tmp[0..n]);
    return n;
}

fn isWordChar(cp: u21) bool {
    if (cp >= '0' and cp <= '9') return true;
    if (cp >= 'A' and cp <= 'Z') return true;
    if (cp >= 'a' and cp <= 'z') return true;
    if (cp == '_' or cp == '-' or cp == '.') return true;
    return cp > 127;
}

fn wordBounds(screen: *const Screen, col: u16, row: u16) struct { lo: u16, hi: u16 } {
    var lo = col;
    var hi = col;
    while (lo > 0) {
        const cp = screen.visibleCell(lo - 1, row).codepoint;
        if (!isWordChar(cp)) break;
        lo -= 1;
    }
    while (hi + 1 < screen.cols) {
        const cp = screen.visibleCell(hi + 1, row).codepoint;
        if (!isWordChar(cp)) break;
        hi += 1;
    }
    return .{ .lo = lo, .hi = hi };
}
