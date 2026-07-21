//! Search — find text in the terminal buffer (incl. scrollback) or files in the workspace folder.

const std = @import("std");
const Screen = @import("../terminal/screen.zig").Screen;

pub const Mode = enum { terminal, files };

pub const TermHit = struct {
    abs_row: usize,
    col: usize,
};

pub const max_hits = 64;
pub const max_query = 128;

pub const Search = struct {
    active: bool = false,
    mode: Mode = .terminal,
    query: [max_query]u8 = undefined,
    query_len: usize = 0,
    selected: usize = 0,

    term_hits: [max_hits]TermHit = undefined,
    term_count: usize = 0,
    /// Highlight on the visible screen (after scrolling to a hit).
    match_row: ?u16 = null,
    match_col: ?u16 = null,

    /// Relative paths under `root` (owned).
    file_hits: [max_hits][]u8 = undefined,
    file_count: usize = 0,
    /// Absolute workspace / cwd being searched (owned).
    root: ?[]u8 = null,

    pub fn open(self: *Search, allocator: std.mem.Allocator, root_path: ?[]const u8) void {
        self.clearHits(allocator);
        self.active = true;
        self.mode = .terminal;
        self.query_len = 0;
        self.selected = 0;
        self.match_row = null;
        self.match_col = null;
        if (root_path) |p| {
            self.setRoot(allocator, p) catch {};
        }
    }

    pub fn close(self: *Search, allocator: std.mem.Allocator) void {
        self.clearHits(allocator);
        self.active = false;
        self.query_len = 0;
        self.match_row = null;
        self.match_col = null;
    }

    pub fn setRoot(self: *Search, allocator: std.mem.Allocator, path: []const u8) !void {
        if (self.root) |old| allocator.free(old);
        self.root = try allocator.dupe(u8, path);
    }

    pub fn clearHits(self: *Search, allocator: std.mem.Allocator) void {
        var i: usize = 0;
        while (i < self.file_count) : (i += 1) {
            allocator.free(self.file_hits[i]);
        }
        self.file_count = 0;
        self.term_count = 0;
        if (self.root) |r| {
            allocator.free(r);
            self.root = null;
        }
    }

    pub fn clearFileHits(self: *Search, allocator: std.mem.Allocator) void {
        var i: usize = 0;
        while (i < self.file_count) : (i += 1) {
            allocator.free(self.file_hits[i]);
        }
        self.file_count = 0;
    }

    pub fn querySlice(self: *const Search) []const u8 {
        return self.query[0..self.query_len];
    }

    pub fn hitCount(self: *const Search) usize {
        return switch (self.mode) {
            .terminal => self.term_count,
            .files => self.file_count,
        };
    }

    pub fn inputChar(self: *Search, codepoint: u32) void {
        if (!self.active) return;
        if (codepoint < 32 or codepoint > 126) return;
        if (self.query_len + 1 >= self.query.len) return;
        self.query[self.query_len] = @intCast(codepoint);
        self.query_len += 1;
        self.selected = 0;
    }

    pub fn backspace(self: *Search) void {
        if (self.query_len > 0) self.query_len -= 1;
        self.selected = 0;
    }

    pub fn toggleMode(self: *Search) void {
        self.mode = if (self.mode == .terminal) .files else .terminal;
        self.selected = 0;
    }

    pub fn moveUp(self: *Search) void {
        if (self.selected > 0) self.selected -= 1;
    }

    pub fn moveDown(self: *Search) void {
        const n = self.hitCount();
        if (n > 0 and self.selected + 1 < n) self.selected += 1;
    }

    /// Rebuild terminal hits from scrollback + screen (case-insensitive).
    pub fn refreshTerminal(self: *Search, screen: *const Screen) void {
        self.term_count = 0;
        self.match_row = null;
        self.match_col = null;
        const q = self.querySlice();
        if (q.len == 0) return;

        const total = screen.scrollback.items.len + screen.rows;
        var abs: usize = 0;
        while (abs < total and self.term_count < max_hits) : (abs += 1) {
            var line_buf: [512]u8 = undefined;
            const n = lineTextAbs(screen, abs, &line_buf);
            const line = line_buf[0..n];
            var from: usize = 0;
            while (from < line.len and self.term_count < max_hits) {
                if (indexOfIgnoreCase(line[from..], q)) |rel| {
                    const col = from + rel;
                    self.term_hits[self.term_count] = .{ .abs_row = abs, .col = col };
                    self.term_count += 1;
                    from = col + 1;
                } else break;
            }
        }
        if (self.selected >= self.term_count and self.term_count > 0) {
            self.selected = self.term_count - 1;
        }
    }

    /// Reveal the selected terminal hit: scroll into view and set highlight.
    pub fn revealSelectedTerminal(self: *Search, screen: *Screen) void {
        if (self.term_count == 0 or self.selected >= self.term_count) {
            self.match_row = null;
            self.match_col = null;
            return;
        }
        const hit = self.term_hits[self.selected];
        const sb = screen.scrollback.items.len;
        if (hit.abs_row < sb) {
            // Show this scrollback line near the top of the viewport.
            const offset = sb - hit.abs_row;
            screen.view_offset = @intCast(@min(offset, sb));
            self.match_row = 0;
            self.match_col = @intCast(@min(hit.col, screen.cols -| 1));
        } else {
            screen.view_offset = 0;
            const row = hit.abs_row - sb;
            self.match_row = @intCast(@min(row, screen.rows -| 1));
            self.match_col = @intCast(@min(hit.col, screen.cols -| 1));
        }
        screen.dirty = true;
    }

    /// Rebuild file name hits under `root` (case-insensitive substring).
    pub fn refreshFiles(self: *Search, allocator: std.mem.Allocator, io: std.Io) void {
        self.clearFileHits(allocator);
        const q = self.querySlice();
        const root = self.root orelse return;
        if (q.len == 0) return;

        walkFiles(allocator, io, root, "", q, &self.file_hits, &self.file_count, 0) catch {};
        if (self.selected >= self.file_count and self.file_count > 0) {
            self.selected = self.file_count - 1;
        }
    }

    pub fn selectedFilePath(self: *const Search) ?[]const u8 {
        if (self.mode != .files or self.file_count == 0 or self.selected >= self.file_count) return null;
        return self.file_hits[self.selected];
    }

    /// Absolute path for the selected file (caller frees).
    pub fn selectedFileAbsolute(self: *const Search, allocator: std.mem.Allocator) !?[]u8 {
        const rel = self.selectedFilePath() orelse return null;
        const root = self.root orelse return null;
        return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, rel });
    }
};

fn lineTextAbs(screen: *const Screen, abs_row: usize, buf: *[512]u8) usize {
    const sb = screen.scrollback.items.len;
    const cols = @min(screen.cols, buf.len);
    if (abs_row < sb) {
        const row = screen.scrollback.items[abs_row];
        var i: usize = 0;
        while (i < cols) : (i += 1) {
            const cp = if (i < row.len) row[i].codepoint else ' ';
            buf[i] = if (cp < 128) @intCast(cp) else '?';
        }
        return trimTrailingSpaces(buf[0..cols]);
    }
    const screen_row = abs_row - sb;
    if (screen_row >= screen.rows) return 0;
    var i: usize = 0;
    while (i < cols) : (i += 1) {
        const cp = screen.cellAtConst(@intCast(i), @intCast(screen_row)).codepoint;
        buf[i] = if (cp < 128) @intCast(cp) else '?';
    }
    return trimTrailingSpaces(buf[0..cols]);
}

fn trimTrailingSpaces(line: []u8) usize {
    var n = line.len;
    while (n > 0 and (line[n - 1] == ' ' or line[n - 1] == 0)) : (n -= 1) {}
    return n;
}

pub fn indexOfIgnoreCase(hay: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or needle.len > hay.len) return null;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        if (eqlIgnoreCase(hay[i .. i + needle.len], needle)) return i;
    }
    return null;
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (toLower(x) != toLower(y)) return false;
    }
    return true;
}

fn toLower(ch: u8) u8 {
    if (ch >= 'A' and ch <= 'Z') return ch + 32;
    return ch;
}

fn containsIgnoreCase(hay: []const u8, needle: []const u8) bool {
    return indexOfIgnoreCase(hay, needle) != null;
}

const max_depth: u32 = 4;
const skip_dirs = [_][]const u8{ ".git", "node_modules", ".zig-cache", "zig-out", "target", ".build", "dist", "__pycache__" };

fn shouldSkipDir(name: []const u8) bool {
    for (skip_dirs) |s| {
        if (std.mem.eql(u8, s, name)) return true;
    }
    if (name.len > 0 and name[0] == '.') return true;
    return false;
}

fn walkFiles(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    rel: []const u8,
    query: []const u8,
    out: *[max_hits][]u8,
    count: *usize,
    depth: u32,
) !void {
    if (count.* >= max_hits or depth > max_depth) return;

    const abs = if (rel.len == 0)
        try allocator.dupe(u8, root)
    else
        try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, rel });
    defer allocator.free(abs);

    var dir = std.Io.Dir.openDirAbsolute(io, abs, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (count.* >= max_hits) return;
        const name = entry.name;
        if (name.len == 0 or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;

        const child_rel = if (rel.len == 0)
            try allocator.dupe(u8, name)
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ rel, name });
        defer allocator.free(child_rel);

        switch (entry.kind) {
            .directory => {
                if (shouldSkipDir(name)) continue;
                try walkFiles(allocator, io, root, child_rel, query, out, count, depth + 1);
            },
            .file => {
                if (containsIgnoreCase(name, query) or containsIgnoreCase(child_rel, query)) {
                    out[count.*] = try allocator.dupe(u8, child_rel);
                    count.* += 1;
                }
            },
            else => {},
        }
    }
}
