const std = @import("std");
const cell_mod = @import("cell.zig");
const Cell = cell_mod.Cell;
const Color = cell_mod.Color;
const Attrs = cell_mod.Attrs;
const width = @import("../font/width.zig");
const mouse_mod = @import("mouse.zig");

pub const Screen = struct {
    allocator: std.mem.Allocator,
    cols: u16,
    rows: u16,
    cells: []Cell,
    cursor_col: u16 = 0,
    cursor_row: u16 = 0,
    cursor_visible: bool = true,
    saved_col: u16 = 0,
    saved_row: u16 = 0,
    dirty: bool = true,

    // Current pen (SGR) state
    fg: Color = Color.rgb(230, 235, 240),
    bg: Color = Color.rgb(18, 20, 26),
    attrs: Attrs = .{},
    default_fg: Color = Color.rgb(230, 235, 240),
    default_bg: Color = Color.rgb(18, 20, 26),

    // Scrollback: circular buffer of rows (each row = cols cells).
    // Logical index 0 is oldest; physical slot is `(start + i) % len`.
    scrollback: std.ArrayList([]Cell) = .empty,
    scrollback_max: usize = 2000,
    /// Physical index of the oldest row once the ring is wrapping.
    scrollback_start: usize = 0,
    /// View offset from bottom (0 = live screen, >0 = scrolled up).
    view_offset: u16 = 0,

    // Origin / wrap
    auto_wrap: bool = true,
    origin_mode: bool = false,
    scroll_top: u16 = 0,
    scroll_bottom: u16 = 0, // inclusive; set to rows-1 on init

    /// Inactive buffer for DEC 47 / 1047 / 1049 (vim, less, htop).
    /// While `alt_active`, `cells` is the alternate screen and this holds primary.
    alt_cells: []Cell = &.{},
    alt_active: bool = false,

    /// OSC 8 hyperlink table. Index 0 is unused (no link).
    links: std.ArrayList([]u8) = .empty,
    active_link: u16 = 0,
    /// OSC 0/2 title (owned bytes in title[0..title_len]).
    title: [96]u8 = undefined,
    title_len: u16 = 0,
    title_dirty: bool = false,
    /// OSC 7 working directory.
    osc_cwd: [std.fs.max_path_bytes]u8 = undefined,
    osc_cwd_len: u16 = 0,
    cwd_dirty: bool = false,
    mouse_tracking: mouse_mod.Tracking = .off,
    mouse_sgr: bool = false,
    bell: bool = false,

    pub fn init(allocator: std.mem.Allocator, cols: u16, rows: u16) !Screen {
        const n = @as(usize, cols) * @as(usize, rows);
        const cells = try allocator.alloc(Cell, n);
        errdefer allocator.free(cells);
        const alt_cells = try allocator.alloc(Cell, n);
        const blank = Cell.blankWith(Color.rgb(230, 235, 240), Color.rgb(18, 20, 26));
        @memset(cells, blank);
        @memset(alt_cells, blank);
        return .{
            .allocator = allocator,
            .cols = cols,
            .rows = rows,
            .cells = cells,
            .alt_cells = alt_cells,
            .scroll_bottom = rows -| 1,
        };
    }

    pub fn deinit(self: *Screen) void {
        self.clearScrollback();
        self.scrollback.deinit(self.allocator);
        for (self.links.items) |s| self.allocator.free(s);
        self.links.deinit(self.allocator);
        self.allocator.free(self.alt_cells);
        self.allocator.free(self.cells);
        self.* = undefined;
    }

    pub fn internLink(self: *Screen, url: []const u8) u16 {
        if (url.len == 0) return 0;
        for (self.links.items, 0..) |existing, i| {
            if (std.mem.eql(u8, existing, url)) return @intCast(i + 1);
        }
        const owned = self.allocator.dupe(u8, url) catch return 0;
        self.links.append(self.allocator, owned) catch {
            self.allocator.free(owned);
            return 0;
        };
        return @intCast(self.links.items.len);
    }

    pub fn linkUrl(self: *const Screen, id: u16) ?[]const u8 {
        if (id == 0 or id > self.links.items.len) return null;
        return self.links.items[id - 1];
    }

    pub fn setTitle(self: *Screen, text: []const u8) void {
        const n = @min(text.len, self.title.len);
        if (n == 0) return;
        @memcpy(self.title[0..n], text[0..n]);
        self.title_len = @intCast(n);
        self.title_dirty = true;
    }

    pub fn setOscCwd(self: *Screen, path: []const u8) void {
        const n = @min(path.len, self.osc_cwd.len);
        if (n == 0) return;
        @memcpy(self.osc_cwd[0..n], path[0..n]);
        self.osc_cwd_len = @intCast(n);
        self.cwd_dirty = true;
    }

    pub fn setThemeColors(self: *Screen, fg: Color, bg: Color) void {
        const old_fg = self.default_fg;
        const old_bg = self.default_bg;
        self.default_fg = fg;
        self.default_bg = bg;
        self.fg = fg;
        self.bg = bg;
        recolorDefaults(self.cells, old_fg, old_bg, fg, bg);
        recolorDefaults(self.alt_cells, old_fg, old_bg, fg, bg);
        for (self.scrollback.items) |row| {
            recolorDefaults(row, old_fg, old_bg, fg, bg);
        }
        self.dirty = true;
    }

    pub fn resize(self: *Screen, cols: u16, rows: u16) !void {
        const n = @as(usize, cols) * @as(usize, rows);
        const new_cells = try self.allocator.alloc(Cell, n);
        errdefer self.allocator.free(new_cells);
        const new_alt = try self.allocator.alloc(Cell, n);
        const blank = Cell.blankWith(self.default_fg, self.default_bg);
        @memset(new_cells, blank);
        @memset(new_alt, blank);

        const copy_rows = @min(self.rows, rows);
        const copy_cols = @min(self.cols, cols);
        var r: u16 = 0;
        while (r < copy_rows) : (r += 1) {
            var col: u16 = 0;
            while (col < copy_cols) : (col += 1) {
                new_cells[@as(usize, r) * cols + col] = self.cells[@as(usize, r) * self.cols + col];
                new_cells[@as(usize, r) * cols + col].dirty = true;
                new_alt[@as(usize, r) * cols + col] = self.alt_cells[@as(usize, r) * self.cols + col];
            }
        }

        // Free / rebuild scrollback rows to new width (truncate or pad).
        for (self.scrollback.items) |*row_ptr| {
            const old = row_ptr.*;
            const fresh = try self.allocator.alloc(Cell, cols);
            @memset(fresh, blank);
            const copy_n = @min(old.len, cols);
            @memcpy(fresh[0..copy_n], old[0..copy_n]);
            self.allocator.free(old);
            row_ptr.* = fresh;
        }

        self.allocator.free(self.cells);
        self.allocator.free(self.alt_cells);
        self.cells = new_cells;
        self.alt_cells = new_alt;
        self.cols = cols;
        self.rows = rows;
        self.cursor_col = @min(self.cursor_col, cols -| 1);
        self.cursor_row = @min(self.cursor_row, rows -| 1);
        self.scroll_top = 0;
        self.scroll_bottom = rows -| 1;
        self.view_offset = 0;
        self.dirty = true;
    }

    pub fn cellAt(self: *Screen, col: u16, row: u16) *Cell {
        return &self.cells[@as(usize, row) * self.cols + col];
    }

    pub fn cellAtConst(self: *const Screen, col: u16, row: u16) Cell {
        return self.cells[@as(usize, row) * self.cols + col];
    }

    /// Visible cell accounting for scrollback view offset.
    pub fn visibleCell(self: *const Screen, col: u16, row: u16) Cell {
        if (self.view_offset == 0) {
            return self.cellAtConst(col, row);
        }
        const total_back: usize = self.scrollback.items.len;
        const offset: usize = self.view_offset;
        // row 0 of view is (total_back - offset) into scrollback + screen
        const abs_row: isize = @as(isize, @intCast(total_back)) - @as(isize, @intCast(offset)) + @as(isize, @intCast(row));
        if (abs_row < 0) {
            return Cell.blankWith(self.default_fg, self.default_bg);
        }
        const a: usize = @intCast(abs_row);
        if (a < total_back) {
            const sb_row = self.scrollbackRowAt(a);
            if (col < sb_row.len) return sb_row[col];
            return Cell.blankWith(self.default_fg, self.default_bg);
        }
        const screen_row: usize = a - total_back;
        if (screen_row < self.rows) {
            return self.cellAtConst(col, @intCast(screen_row));
        }
        return Cell.blankWith(self.default_fg, self.default_bg);
    }

    pub fn putChar(self: *Screen, codepoint: u21) void {
        if (codepoint == 0) return;
        self.view_offset = 0;

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
                    self.writeAtCursor(' ');
                    self.cursor_col += 1;
                }
                self.dirty = true;
                return;
            },
            0x08 => { // BS
                if (self.cursor_col > 0) {
                    self.cursor_col -= 1;
                    self.dirty = true;
                }
                return;
            },
            0x07 => {
                self.bell = true;
                return;
            },
            else => {},
        }

        if (codepoint < 0x20) return;

        const cols = width.columns(codepoint);
        const need: u16 = if (cols >= 2) 2 else 1;

        if (self.cursor_col + need > self.cols) {
            if (self.auto_wrap) {
                self.cursor_col = 0;
                self.lineFeed();
            } else {
                self.cursor_col = self.cols -| 1;
            }
        }

        self.writeAtCursorWide(codepoint, need);
        self.cursor_col += need;
        if (self.cursor_col > self.cols) self.cursor_col = self.cols;
        self.dirty = true;
    }

    /// Oldest-first scrollback row. `i` must be `< scrollback.items.len`.
    pub fn scrollbackRowAt(self: *const Screen, i: usize) []const Cell {
        const n = self.scrollback.items.len;
        return self.scrollback.items[(self.scrollback_start + i) % n];
    }

    fn writeAtCursor(self: *Screen, codepoint: u21) void {
        self.writeAtCursorWide(codepoint, 1);
    }

    fn writeAtCursorWide(self: *Screen, codepoint: u21, cols: u16) void {
        var fg = self.fg;
        var bg = self.bg;
        if (self.attrs.reverse) {
            const t = fg;
            fg = bg;
            bg = t;
        }
        const wide: u8 = if (cols >= 2) 1 else 0;
        self.cellAt(self.cursor_col, self.cursor_row).setFull(codepoint, fg, bg, self.attrs, wide, self.active_link);
        if (cols >= 2 and self.cursor_col + 1 < self.cols) {
            self.cellAt(self.cursor_col + 1, self.cursor_row).setFull(0, fg, bg, self.attrs, 2, self.active_link);
        }
    }

    pub fn lineFeed(self: *Screen) void {
        if (self.cursor_row < self.scroll_bottom) {
            self.cursor_row += 1;
        } else {
            self.scrollUpRegion();
        }
        self.dirty = true;
    }

    pub fn index(self: *Screen) void {
        self.lineFeed();
    }

    pub fn reverseIndex(self: *Screen) void {
        if (self.cursor_row > self.scroll_top) {
            self.cursor_row -= 1;
        } else {
            self.scrollDownRegion();
        }
        self.dirty = true;
    }

    fn pushScrollbackRow(self: *Screen, row_cells: []const Cell) void {
        if (self.scrollback_max == 0) return;
        const blank = Cell.blankWith(self.default_fg, self.default_bg);
        const n = @min(row_cells.len, self.cols);

        // Once at capacity, reuse the oldest slot (O(1)) instead of orderedRemove(0).
        if (self.scrollback.items.len >= self.scrollback_max and self.scrollback_max > 0) {
            const slot = self.scrollback.items[self.scrollback_start];
            @memcpy(slot[0..n], row_cells[0..n]);
            if (n < self.cols) {
                @memset(slot[n..], blank);
            }
            self.scrollback_start = (self.scrollback_start + 1) % self.scrollback.items.len;
            return;
        }

        const copy = self.allocator.alloc(Cell, self.cols) catch return;
        @memcpy(copy[0..n], row_cells[0..n]);
        if (n < self.cols) {
            @memset(copy[n..], blank);
        }
        self.scrollback.append(self.allocator, copy) catch {
            self.allocator.free(copy);
            return;
        };
    }

    fn clearScrollback(self: *Screen) void {
        for (self.scrollback.items) |row| self.allocator.free(row);
        self.scrollback.clearRetainingCapacity();
        self.scrollback_start = 0;
    }

    pub fn scrollUpRegion(self: *Screen) void {
        const top = self.scroll_top;
        const bottom = self.scroll_bottom;
        if (!self.alt_active and top == 0 and bottom + 1 == self.rows) {
            // Full primary screen: save top row to scrollback (never while vim/less is up).
            const top_row = self.cells[0..self.cols];
            self.pushScrollbackRow(top_row);
        }
        var r: u16 = top;
        while (r < bottom) : (r += 1) {
            const dst = self.cells[@as(usize, r) * self.cols ..][0..self.cols];
            const src = self.cells[@as(usize, r + 1) * self.cols ..][0..self.cols];
            @memcpy(dst, src);
            for (dst) |*cell| cell.dirty = true;
        }
        const last = self.cells[@as(usize, bottom) * self.cols ..][0..self.cols];
        @memset(last, Cell.blankWith(self.default_fg, self.default_bg));
        for (last) |*cell| cell.dirty = true;
    }

    pub fn scrollDownRegion(self: *Screen) void {
        const top = self.scroll_top;
        const bottom = self.scroll_bottom;
        var r: u16 = bottom;
        while (r > top) : (r -= 1) {
            const dst = self.cells[@as(usize, r) * self.cols ..][0..self.cols];
            const src = self.cells[@as(usize, r - 1) * self.cols ..][0..self.cols];
            @memcpy(dst, src);
            for (dst) |*cell| cell.dirty = true;
        }
        const first = self.cells[@as(usize, top) * self.cols ..][0..self.cols];
        @memset(first, Cell.blankWith(self.default_fg, self.default_bg));
        for (first) |*cell| cell.dirty = true;
    }

    pub fn scrollView(self: *Screen, delta: i32) void {
        const max_off: u16 = @intCast(@min(self.scrollback.items.len, 65535));
        if (delta < 0) {
            const d: u16 = @intCast(@min(@as(u16, @intCast(-delta)), self.view_offset));
            self.view_offset -= d;
        } else {
            const d: u16 = @intCast(@min(@as(u16, @intCast(delta)), max_off -| self.view_offset));
            self.view_offset += d;
        }
        self.dirty = true;
    }

    // --- Cursor ---

    pub fn moveCursor(self: *Screen, col: u16, row: u16) void {
        self.cursor_col = @min(col, self.cols -| 1);
        var r = row;
        if (self.origin_mode) {
            r = self.scroll_top +| row;
            r = @min(r, self.scroll_bottom);
        } else {
            r = @min(r, self.rows -| 1);
        }
        self.cursor_row = r;
        self.dirty = true;
    }

    pub fn moveCursorRel(self: *Screen, dcol: i32, drow: i32) void {
        const nc: i32 = @as(i32, @intCast(self.cursor_col)) + dcol;
        const nr: i32 = @as(i32, @intCast(self.cursor_row)) + drow;
        self.cursor_col = @intCast(@max(0, @min(nc, @as(i32, @intCast(self.cols -| 1)))));
        self.cursor_row = @intCast(@max(0, @min(nr, @as(i32, @intCast(self.rows -| 1)))));
        self.dirty = true;
    }

    pub fn saveCursor(self: *Screen) void {
        self.saved_col = self.cursor_col;
        self.saved_row = self.cursor_row;
    }

    pub fn restoreCursor(self: *Screen) void {
        self.cursor_col = self.saved_col;
        self.cursor_row = self.saved_row;
        self.dirty = true;
    }

    // --- Erase ---

    pub fn eraseInDisplay(self: *Screen, mode: u16) void {
        const blank = Cell.blankWith(self.default_fg, self.default_bg);
        switch (mode) {
            0 => { // cursor to end
                self.eraseInLine(0);
                var r = self.cursor_row +| 1;
                while (r < self.rows) : (r += 1) {
                    @memset(self.cells[@as(usize, r) * self.cols ..][0..self.cols], blank);
                }
            },
            1 => { // start to cursor
                var r: u16 = 0;
                while (r < self.cursor_row) : (r += 1) {
                    @memset(self.cells[@as(usize, r) * self.cols ..][0..self.cols], blank);
                }
                self.eraseInLine(1);
            },
            2, 3 => { // entire screen (+scrollback for 3)
                @memset(self.cells, blank);
                if (mode == 3) {
                    self.clearScrollback();
                }
            },
            else => {},
        }
        for (self.cells) |*c| c.dirty = true;
        self.dirty = true;
    }

    pub fn eraseInLine(self: *Screen, mode: u16) void {
        const blank = Cell.blankWith(self.default_fg, self.default_bg);
        const row_start = @as(usize, self.cursor_row) * self.cols;
        switch (mode) {
            0 => { // cursor to end of line
                @memset(self.cells[row_start + self.cursor_col ..][0 .. self.cols - self.cursor_col], blank);
            },
            1 => { // start to cursor
                @memset(self.cells[row_start..][0 .. self.cursor_col + 1], blank);
            },
            2 => {
                @memset(self.cells[row_start..][0..self.cols], blank);
            },
            else => {},
        }
        for (self.cells[row_start..][0..self.cols]) |*c| c.dirty = true;
        self.dirty = true;
    }

    pub fn deleteChars(self: *Screen, n: u16) void {
        const count = @min(n, self.cols -| self.cursor_col);
        if (count == 0) return;
        const row_start = @as(usize, self.cursor_row) * self.cols;
        const from = row_start + self.cursor_col;
        const move_n = self.cols - self.cursor_col - count;
        if (move_n > 0) {
            std.mem.copyForwards(Cell, self.cells[from .. from + move_n], self.cells[from + count .. from + count + move_n]);
        }
        const blank = Cell.blankWith(self.default_fg, self.default_bg);
        @memset(self.cells[row_start + self.cols - count ..][0..count], blank);
        self.dirty = true;
    }

    pub fn insertChars(self: *Screen, n: u16) void {
        const count = @min(n, self.cols -| self.cursor_col);
        if (count == 0) return;
        const row_start = @as(usize, self.cursor_row) * self.cols;
        const from = row_start + self.cursor_col;
        const move_n = self.cols - self.cursor_col - count;
        if (move_n > 0) {
            std.mem.copyBackwards(Cell, self.cells[from + count .. from + count + move_n], self.cells[from .. from + move_n]);
        }
        const blank = Cell.blankWith(self.default_fg, self.default_bg);
        @memset(self.cells[from..][0..count], blank);
        self.dirty = true;
    }

    pub fn setScrollRegion(self: *Screen, top: u16, bottom: u16) void {
        const t = @min(top, self.rows -| 1);
        const b = @min(bottom, self.rows -| 1);
        if (t < b) {
            self.scroll_top = t;
            self.scroll_bottom = b;
        } else {
            self.scroll_top = 0;
            self.scroll_bottom = self.rows -| 1;
        }
        self.cursor_col = 0;
        self.cursor_row = if (self.origin_mode) self.scroll_top else 0;
    }

    pub fn resetAttrs(self: *Screen) void {
        self.fg = self.default_fg;
        self.bg = self.default_bg;
        self.attrs = .{};
    }

    /// CSI ? 47/1047/1049 h — vim, less, and other full-screen apps.
    pub fn enterAltScreen(self: *Screen, save_cursor: bool, clear: bool) void {
        if (save_cursor) self.saveCursor();
        if (!self.alt_active) {
            const tmp = self.cells;
            self.cells = self.alt_cells;
            self.alt_cells = tmp;
            self.alt_active = true;
        }
        self.view_offset = 0;
        if (clear) {
            const blank = Cell.blankWith(self.default_fg, self.default_bg);
            @memset(self.cells, blank);
            self.cursor_col = 0;
            self.cursor_row = 0;
            self.scroll_top = 0;
            self.scroll_bottom = self.rows -| 1;
        }
        for (self.cells) |*cell| cell.dirty = true;
        self.dirty = true;
    }

    /// CSI ? 47/1047/1049 l — restore the shell screen underneath.
    pub fn leaveAltScreen(self: *Screen, restore_cursor: bool) void {
        if (self.alt_active) {
            const tmp = self.cells;
            self.cells = self.alt_cells;
            self.alt_cells = tmp;
            self.alt_active = false;
        }
        self.view_offset = 0;
        if (restore_cursor) self.restoreCursor();
        for (self.cells) |*cell| cell.dirty = true;
        self.dirty = true;
    }

    pub fn softReset(self: *Screen) void {
        self.leaveAltScreen(false);
        self.auto_wrap = true;
        self.origin_mode = false;
        self.cursor_visible = true;
        self.resetAttrs();
        self.scroll_top = 0;
        self.scroll_bottom = self.rows -| 1;
        self.moveCursor(0, 0);
        self.eraseInDisplay(2);
    }

    pub fn clearDirty(self: *Screen) void {
        for (self.cells) |*c| c.dirty = false;
        self.dirty = false;
    }

    /// Collect plain text of the visible screen (for search / copy).
    pub fn lineText(self: *const Screen, row: u16, buf: []u8) usize {
        if (row >= self.rows or buf.len < self.cols) return 0;
        var i: usize = 0;
        while (i < self.cols) : (i += 1) {
            const cp = self.visibleCell(@intCast(i), row).codepoint;
            buf[i] = if (cp < 128) @intCast(cp) else '?';
        }
        return self.cols;
    }
};

fn recolorDefaults(cells: []Cell, old_fg: Color, old_bg: Color, fg: Color, bg: Color) void {
    for (cells) |*cell| {
        if (cell.bg.eql(old_bg)) cell.bg = bg;
        if (cell.fg.eql(old_fg)) cell.fg = fg;
    }
}
