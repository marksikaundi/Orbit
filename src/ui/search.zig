//! Search — find text in the terminal, file names, or code inside workspace files.

const std = @import("std");
const Screen = @import("../terminal/screen.zig").Screen;
const pattern = @import("pattern.zig");

pub const Mode = enum { terminal, files, code };

pub const TermHit = struct {
    abs_row: usize,
    col: usize,
};

pub const CodeHit = struct {
    rel: []u8,
    line: usize,
    col: usize,
    snippet: [72]u8 = undefined,
    snippet_len: u8 = 0,

    pub fn snippetSlice(self: *const CodeHit) []const u8 {
        return self.snippet[0..self.snippet_len];
    }
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
    /// Code hits: path + line + snippet (owned rel path).
    code_hits: [max_hits]CodeHit = undefined,
    code_count: usize = 0,
    /// Absolute workspace / cwd being searched (owned).
    root: ?[]u8 = null,
    case_sensitive: bool = false,
    regex: bool = false,

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
        self.clearFileHits(allocator);
        self.clearCodeHits(allocator);
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

    pub fn clearCodeHits(self: *Search, allocator: std.mem.Allocator) void {
        var i: usize = 0;
        while (i < self.code_count) : (i += 1) {
            allocator.free(self.code_hits[i].rel);
        }
        self.code_count = 0;
    }

    pub fn querySlice(self: *const Search) []const u8 {
        return self.query[0..self.query_len];
    }

    pub fn hitCount(self: *const Search) usize {
        return switch (self.mode) {
            .terminal => self.term_count,
            .files => self.file_count,
            .code => self.code_count,
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

    pub fn toggleCase(self: *Search) void {
        self.case_sensitive = !self.case_sensitive;
        self.selected = 0;
    }

    pub fn toggleRegex(self: *Search) void {
        self.regex = !self.regex;
        self.selected = 0;
    }

    pub fn toggleMode(self: *Search) void {
        self.mode = switch (self.mode) {
            .terminal => .files,
            .files => .code,
            .code => .terminal,
        };
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
            const opts = pattern.Options{ .case_sensitive = self.case_sensitive, .regex = self.regex };
            while (from < line.len and self.term_count < max_hits) {
                if (pattern.find(line[from..], q, opts)) |rel| {
                    const col = from + rel;
                    self.term_hits[self.term_count] = .{ .abs_row = abs, .col = col };
                    self.term_count += 1;
                    from = col + @max(@as(usize, 1), q.len);
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
        return switch (self.mode) {
            .files => blk: {
                if (self.file_count == 0 or self.selected >= self.file_count) break :blk null;
                break :blk self.file_hits[self.selected];
            },
            .code => blk: {
                if (self.code_count == 0 or self.selected >= self.code_count) break :blk null;
                break :blk self.code_hits[self.selected].rel;
            },
            .terminal => null,
        };
    }

    pub fn selectedCodeHit(self: *const Search) ?*const CodeHit {
        if (self.mode != .code or self.code_count == 0 or self.selected >= self.code_count) return null;
        return &self.code_hits[self.selected];
    }

    /// Absolute path for the selected file (caller frees).
    pub fn selectedFileAbsolute(self: *const Search, allocator: std.mem.Allocator) !?[]u8 {
        const rel = self.selectedFilePath() orelse return null;
        const root = self.root orelse return null;
        return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, rel });
    }

    /// Rebuild code hits by grepping file contents under `root`.
    pub fn refreshCode(self: *Search, allocator: std.mem.Allocator, io: std.Io) void {
        self.clearCodeHits(allocator);
        const q = self.querySlice();
        const root = self.root orelse return;
        if (q.len == 0) return;

        var scanned: usize = 0;
        walkCode(allocator, io, root, "", q, &self.code_hits, &self.code_count, 0, &scanned) catch {};
        if (self.selected >= self.code_count and self.code_count > 0) {
            self.selected = self.code_count - 1;
        }
    }
};

fn lineTextAbs(screen: *const Screen, abs_row: usize, buf: *[512]u8) usize {
    const sb = screen.scrollback.items.len;
    const cols = @min(screen.cols, buf.len);
    if (abs_row < sb) {
        const row = screen.scrollbackRowAt(abs_row);
        var i: usize = 0;
        var n: usize = 0;
        while (i < cols) : (i += 1) {
            const cell = if (i < row.len) row[i] else continue;
            if (cell.wide == 2) continue;
            n += putCp(buf, n, cell.codepoint);
        }
        return trimTrailingSpaces(buf[0..n]);
    }
    const screen_row = abs_row - sb;
    if (screen_row >= screen.rows) return 0;
    var i: usize = 0;
    var n: usize = 0;
    while (i < cols) : (i += 1) {
        const cell = screen.cellAtConst(@intCast(i), @intCast(screen_row));
        if (cell.wide == 2) continue;
        n += putCp(buf, n, cell.codepoint);
    }
    return trimTrailingSpaces(buf[0..n]);
}

fn putCp(buf: *[512]u8, at: usize, cp: u21) usize {
    if (at >= buf.len) return 0;
    if (cp < 0x80) {
        buf[at] = if (cp == 0) ' ' else @intCast(cp);
        return 1;
    }
    var tmp: [4]u8 = undefined;
    const k = std.unicode.utf8Encode(cp, &tmp) catch return 0;
    if (at + k > buf.len) return 0;
    @memcpy(buf[at .. at + k], tmp[0..k]);
    return k;
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

const max_code_bytes: usize = 256 * 1024;
const max_scan_files: usize = 400;

fn walkCode(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    rel: []const u8,
    query: []const u8,
    out: *[max_hits]CodeHit,
    count: *usize,
    depth: u32,
    scanned: *usize,
) !void {
    if (count.* >= max_hits or depth > max_depth or scanned.* >= max_scan_files) return;

    const abs = if (rel.len == 0)
        try allocator.dupe(u8, root)
    else
        try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, rel });
    defer allocator.free(abs);

    var dir = std.Io.Dir.openDirAbsolute(io, abs, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (count.* >= max_hits or scanned.* >= max_scan_files) return;
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
                try walkCode(allocator, io, root, child_rel, query, out, count, depth + 1, scanned);
            },
            .file => {
                scanned.* += 1;
                const child_abs = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, child_rel });
                defer allocator.free(child_abs);
                grepFile(allocator, io, child_abs, child_rel, query, out, count) catch {};
            },
            else => {},
        }
    }
}

fn grepFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    abs: []const u8,
    rel: []const u8,
    query: []const u8,
    out: *[max_hits]CodeHit,
    count: *usize,
) !void {
    if (count.* >= max_hits) return;
    const raw = readLimited(allocator, io, abs, max_code_bytes) catch return;
    defer allocator.free(raw);
    if (looksBinary(raw)) return;

    var line_i: usize = 0;
    var i: usize = 0;
    while (i < raw.len and count.* < max_hits) {
        const start = i;
        while (i < raw.len and raw[i] != '\n') i += 1;
        var line = raw[start..i];
        if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
        var from: usize = 0;
        while (from < line.len and count.* < max_hits) {
            if (indexOfIgnoreCase(line[from..], query)) |rel_col| {
                const col = from + rel_col;
                var hit: CodeHit = .{
                    .rel = try allocator.dupe(u8, rel),
                    .line = line_i,
                    .col = col,
                };
                fillSnippet(&hit, line, col);
                out[count.*] = hit;
                count.* += 1;
                from = col + 1;
            } else break;
        }
        if (i < raw.len) i += 1;
        line_i += 1;
    }
}

fn fillSnippet(hit: *CodeHit, line: []const u8, col: usize) void {
    var start: usize = 0;
    while (start < line.len and (line[start] == ' ' or line[start] == '\t')) start += 1;
    const body = line[start..];
    const adj = if (col >= start) col - start else 0;
    const keep = hit.snippet.len;
    var from: usize = 0;
    if (body.len > keep) {
        from = if (adj > keep / 4) adj - keep / 4 else 0;
        if (from + keep > body.len) from = body.len - keep;
    }
    const n = @min(keep, body.len - from);
    if (n > 0) @memcpy(hit.snippet[0..n], body[from..][0..n]);
    hit.snippet_len = @intCast(n);
}

fn readLimited(allocator: std.mem.Allocator, io: std.Io, path: []const u8, limit: usize) ![]u8 {
    const file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return error.NotFound;
    defer file.close(io);
    var buf: [4096]u8 = undefined;
    var reader = file.reader(io, &buf);
    return reader.interface.allocRemaining(allocator, .limited(limit)) catch |err| switch (err) {
        error.StreamTooLong => return error.FileTooLarge,
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.ReadFailed,
    };
}

fn looksBinary(data: []const u8) bool {
    const n = @min(data.len, 1024);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const ch = data[i];
        if (ch == 0) return true;
        if (ch < 0x09 and ch != '\n' and ch != '\r' and ch != '\t') return true;
    }
    return false;
}
