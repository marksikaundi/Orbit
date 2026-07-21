const std = @import("std");
const Cell = @import("cell.zig").Cell;

pub const Screen = struct {
    allocator: std.mem.Allocator,
    cols: u16,
    rows: u16,
    cells: []Cell,
    cursor_col: u16 = 0,
    cursor_row: u16 = 0,
    dirty: bool = true,

    pub fn init(allocator: std.mem.Allocator, cols: u16, rows: u16) !Screen {
        const cells = try allocator.alloc(Cell, @as(usize, cols) * @as(usize, rows));
        @memset(cells, Cell.blank());
        return .{
            .allocator = allocator,
            .cols = cols,
            .rows = rows,
            .cells = cells,
        };
    }

    pub fn deinit(self: *Screen) void {
        self.allocator.free(self.cells);
        self.* = undefined;
    }

    pub fn resize(self: *Screen, cols: u16, rows: u16) !void {
        const new_cells = try self.allocator.alloc(Cell, @as(usize, cols) * @as(usize, rows));
        @memset(new_cells, Cell.blank());

        const copy_rows = @min(self.rows, rows);
        const copy_cols = @min(self.cols, cols);
        var r: u16 = 0;
        while (r < copy_rows) : (r += 1) {
            var col: u16 = 0;
            while (col < copy_cols) : (col += 1) {
                new_cells[@as(usize, r) * cols + col] = self.cells[@as(usize, r) * self.cols + col];
                new_cells[@as(usize, r) * cols + col].dirty = true;
            }
        }

        self.allocator.free(self.cells);
        self.cells = new_cells;
        self.cols = cols;
        self.rows = rows;
        self.cursor_col = @min(self.cursor_col, cols -| 1);
        self.cursor_row = @min(self.cursor_row, rows -| 1);
        self.dirty = true;
    }

    pub fn cellAt(self: *Screen, col: u16, row: u16) *Cell {
        return &self.cells[@as(usize, row) * self.cols + col];
    }

    pub fn cellAtConst(self: *const Screen, col: u16, row: u16) Cell {
        return self.cells[@as(usize, row) * self.cols + col];
    }

    pub fn putChar(self: *Screen, codepoint: u21) void {
        if (codepoint == 0) return;

        switch (codepoint) {
            '\n' => {
                self.cursor_col = 0;
                self.lineFeed();
                return;
            },
            '\r' => {
                self.cursor_col = 0;
                self.dirty = true;
                return;
            },
            '\t' => {
                const next = ((self.cursor_col / 8) + 1) * 8;
                while (self.cursor_col < next and self.cursor_col < self.cols) {
                    self.cellAt(self.cursor_col, self.cursor_row).set(' ');
                    self.cursor_col += 1;
                }
                self.dirty = true;
                return;
            },
            0x08, 0x7F => { // backspace / delete
                if (self.cursor_col > 0) {
                    self.cursor_col -= 1;
                    self.cellAt(self.cursor_col, self.cursor_row).set(' ');
                    self.dirty = true;
                }
                return;
            },
            else => {},
        }

        if (codepoint < 0x20) return; // ignore other controls

        if (self.cursor_col >= self.cols) {
            self.cursor_col = 0;
            self.lineFeed();
        }

        self.cellAt(self.cursor_col, self.cursor_row).set(codepoint);
        self.cursor_col += 1;
        self.dirty = true;
    }

    fn lineFeed(self: *Screen) void {
        if (self.cursor_row + 1 < self.rows) {
            self.cursor_row += 1;
        } else {
            self.scrollUp();
        }
        self.dirty = true;
    }

    fn scrollUp(self: *Screen) void {
        const row_bytes = self.cols;
        // Move rows 1..end to 0..end-1
        var r: u16 = 0;
        while (r + 1 < self.rows) : (r += 1) {
            const dst = self.cells[@as(usize, r) * row_bytes ..][0..row_bytes];
            const src = self.cells[@as(usize, r + 1) * row_bytes ..][0..row_bytes];
            @memcpy(dst, src);
            for (dst) |*cell| cell.dirty = true;
        }
        // Clear last row
        const last = self.cells[@as(usize, self.rows - 1) * row_bytes ..][0..row_bytes];
        @memset(last, Cell.blank());
        for (last) |*cell| cell.dirty = true;
    }

    pub fn clearDirty(self: *Screen) void {
        for (self.cells) |*cell| cell.dirty = false;
        self.dirty = false;
    }
};

test "screen putChar and newline" {
    var screen = try Screen.init(std.testing.allocator, 10, 3);
    defer screen.deinit();
    screen.putChar('H');
    screen.putChar('i');
    screen.putChar('\n');
    screen.putChar('!');
    try std.testing.expectEqual(@as(u21, 'H'), screen.cellAtConst(0, 0).codepoint);
    try std.testing.expectEqual(@as(u21, 'i'), screen.cellAtConst(1, 0).codepoint);
    try std.testing.expectEqual(@as(u21, '!'), screen.cellAtConst(0, 1).codepoint);
}
