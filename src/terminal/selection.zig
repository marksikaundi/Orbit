//! Mouse-driven text selection over the terminal grid.

const Screen = @import("screen.zig").Screen;

pub const Point = struct {
    col: u16,
    row: u16,

    pub fn before(self: Point, other: Point) bool {
        if (self.row != other.row) return self.row < other.row;
        return self.col < other.col;
    }
};

pub const Selection = struct {
    active: bool = false,
    selecting: bool = false,
    start: Point = .{ .col = 0, .row = 0 },
    end: Point = .{ .col = 0, .row = 0 },

    pub fn clear(self: *Selection) void {
        self.active = false;
        self.selecting = false;
    }

    pub fn begin(self: *Selection, col: u16, row: u16) void {
        self.active = true;
        self.selecting = true;
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
        const p = Point{ .col = col, .row = row };
        if (p.row < n.a.row or p.row > n.b.row) return false;
        if (n.a.row == n.b.row) {
            return col >= n.a.col and col <= n.b.col;
        }
        if (p.row == n.a.row) return col >= n.a.col;
        if (p.row == n.b.row) return col <= n.b.col;
        return true;
    }

    /// Write selected text into `buf`, returns bytes written (truncated if needed).
    pub fn copyText(self: *const Selection, screen: *const Screen, buf: []u8) usize {
        if (!self.active or buf.len == 0) return 0;
        const n = self.normalized();
        var out: usize = 0;
        var row = n.a.row;
        while (row <= n.b.row) : (row += 1) {
            const start_col: u16 = if (row == n.a.row) n.a.col else 0;
            const end_col: u16 = if (row == n.b.row) n.b.col else screen.cols -| 1;
            var col = start_col;
            while (col <= end_col) : (col += 1) {
                if (out >= buf.len) return out;
                const cp = screen.visibleCell(col, row).codepoint;
                buf[out] = if (cp < 128) @intCast(cp) else '?';
                out += 1;
            }
            if (row < n.b.row) {
                if (out >= buf.len) return out;
                buf[out] = '\n';
                out += 1;
            }
        }
        // Trim trailing spaces on each line for nicer clipboard
        return out;
    }
};
