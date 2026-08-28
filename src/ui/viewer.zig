//! Syntax-highlighted file editor overlay — open from search, palette, or a path.
//! Completions are keywords / common APIs / names in the file (not a full LSP).

const std = @import("std");
const highlight = @import("../syntax/highlight.zig");
const complete = @import("../syntax/complete.zig");

pub const Language = highlight.Language;
pub const Kind = highlight.Kind;
pub const ScanState = highlight.ScanState;
pub const Span = highlight.Span;
pub const max_spans = highlight.max_spans;
pub const CompleteHit = complete.Hit;
pub const max_complete = complete.max_results;

pub const max_file_bytes: usize = 512 * 1024;

pub const Viewer = struct {
    active: bool = false,
    /// Path shown in the header (relative when opened from search).
    display: ?[]u8 = null,
    abs_path: ?[]u8 = null,
    content: ?[]u8 = null,
    line_offsets: []usize = &.{},
    line_states: []ScanState = &.{},
    language: Language = .none,
    scroll: usize = 0,
    cursor_row: usize = 0,
    cursor_col: usize = 0,
    want_col: usize = 0,
    dirty: bool = false,
    discard_armed: bool = false,
    /// Skip the next onChar (Ctrl+Space / Tab already handled as a key).
    suppress_next_char: bool = false,
    complete_open: bool = false,
    complete_sel: usize = 0,
    complete_n: usize = 0,
    complete_hits: [max_complete]CompleteHit = undefined,
    /// True when the file is binary / not previewable.
    binary: bool = false,
    too_large: bool = false,
    error_msg: ?[]u8 = null,

    pub fn open(
        self: *Viewer,
        allocator: std.mem.Allocator,
        io: std.Io,
        abs_path: []const u8,
        display: []const u8,
    ) void {
        self.close(allocator);
        self.active = true;
        self.language = highlight.detectLanguage(abs_path);
        self.display = allocator.dupe(u8, display) catch null;
        self.abs_path = allocator.dupe(u8, abs_path) catch null;
        self.load(allocator, io, abs_path);
    }

    pub fn close(self: *Viewer, allocator: std.mem.Allocator) void {
        if (self.display) |p| allocator.free(p);
        if (self.abs_path) |p| allocator.free(p);
        if (self.content) |p| allocator.free(p);
        if (self.line_offsets.len > 0) allocator.free(self.line_offsets);
        if (self.line_states.len > 0) allocator.free(self.line_states);
        if (self.error_msg) |p| allocator.free(p);
        self.* = .{};
    }

    pub fn displayName(self: *const Viewer) []const u8 {
        if (self.display) |d| return d;
        if (self.abs_path) |p| return p;
        return "untitled";
    }

    pub fn lineCount(self: *const Viewer) usize {
        return self.line_offsets.len;
    }

    pub fn canEdit(self: *const Viewer) bool {
        return self.active and self.content != null and self.error_msg == null and !self.binary;
    }

    pub fn line(self: *const Viewer, index: usize) []const u8 {
        const body = self.content orelse return "";
        if (index >= self.line_offsets.len) return "";
        const start = self.line_offsets[index];
        const end = if (index + 1 < self.line_offsets.len) self.line_offsets[index + 1] else body.len;
        var slice = body[start..end];
        if (slice.len > 0 and slice[slice.len - 1] == '\n') slice = slice[0 .. slice.len - 1];
        if (slice.len > 0 and slice[slice.len - 1] == '\r') slice = slice[0 .. slice.len - 1];
        return slice;
    }

    pub fn lineState(self: *const Viewer, index: usize) ScanState {
        if (index >= self.line_states.len) return .code;
        return self.line_states[index];
    }

    pub fn scrollBy(self: *Viewer, delta: i32, visible: usize) void {
        const total = self.lineCount();
        if (total == 0) {
            self.scroll = 0;
            return;
        }
        const max_scroll = if (total > visible) total - visible else 0;
        const next: i64 = @as(i64, @intCast(self.scroll)) + delta;
        if (next < 0) {
            self.scroll = 0;
        } else if (next > @as(i64, @intCast(max_scroll))) {
            self.scroll = max_scroll;
        } else {
            self.scroll = @intCast(next);
        }
    }

    pub fn clampScroll(self: *Viewer, visible: usize) void {
        self.scrollBy(0, visible);
    }

    pub fn ensureCursorVisible(self: *Viewer, visible: usize) void {
        const vis = @max(visible, 1);
        if (self.cursor_row < self.scroll) {
            self.scroll = self.cursor_row;
        } else if (self.cursor_row >= self.scroll + vis) {
            self.cursor_row = @min(self.cursor_row, if (self.lineCount() == 0) 0 else self.lineCount() - 1);
            self.scroll = self.cursor_row - vis + 1;
        }
        self.clampScroll(vis);
    }

    pub fn insertChar(self: *Viewer, allocator: std.mem.Allocator, codepoint: u32) void {
        if (!self.canEdit()) return;
        if (codepoint < 32 or codepoint == 127) return;
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(codepoint), &buf) catch return;
        self.insertBytes(allocator, buf[0..len]);
        self.refreshCompletion(false);
    }

    pub fn insertBytes(self: *Viewer, allocator: std.mem.Allocator, bytes: []const u8) void {
        if (!self.canEdit() or bytes.len == 0) return;
        const at = self.cursorByte();
        self.splice(allocator, at, 0, bytes) catch return;
        self.cursor_col += bytes.len;
        self.want_col = self.cursor_col;
        self.discard_armed = false;
    }

    pub fn newline(self: *Viewer, allocator: std.mem.Allocator) void {
        if (!self.canEdit()) return;
        self.splice(allocator, self.cursorByte(), 0, "\n") catch return;
        self.cursor_row += 1;
        self.cursor_col = 0;
        self.want_col = 0;
        self.complete_open = false;
        self.discard_armed = false;
        self.clampCursor();
    }

    pub fn backspace(self: *Viewer, allocator: std.mem.Allocator) void {
        if (!self.canEdit()) return;
        if (self.cursor_col > 0) {
            const text = self.line(self.cursor_row);
            const prev = utf8Prev(text, @min(self.cursor_col, text.len));
            const del = self.cursor_col - prev;
            const at = self.cursorByte() - del;
            self.splice(allocator, at, del, "") catch return;
            self.cursor_col = prev;
            self.want_col = self.cursor_col;
        } else if (self.cursor_row > 0) {
            const prev_len = self.line(self.cursor_row - 1).len;
            const body = self.content orelse return;
            const pos = self.line_offsets[self.cursor_row];
            var del_start = pos;
            if (del_start > 0 and body[del_start - 1] == '\n') del_start -= 1;
            if (del_start > 0 and body[del_start - 1] == '\r') del_start -= 1;
            self.splice(allocator, del_start, pos - del_start, "") catch return;
            self.cursor_row -= 1;
            self.cursor_col = prev_len;
            self.want_col = self.cursor_col;
        } else {
            return;
        }
        self.discard_armed = false;
        self.refreshCompletion(false);
    }

    pub fn deleteForward(self: *Viewer, allocator: std.mem.Allocator) void {
        if (!self.canEdit()) return;
        const text = self.line(self.cursor_row);
        if (self.cursor_col < text.len) {
            const next = utf8Next(text, self.cursor_col);
            const del = next - self.cursor_col;
            self.splice(allocator, self.cursorByte(), del, "") catch return;
        } else if (self.cursor_row + 1 < self.lineCount()) {
            const body = self.content orelse return;
            const pos = self.cursorByte();
            var del: usize = 0;
            if (pos < body.len and body[pos] == '\r') del += 1;
            if (pos + del < body.len and body[pos + del] == '\n') del += 1;
            if (del == 0) return;
            self.splice(allocator, pos, del, "") catch return;
        } else {
            return;
        }
        self.discard_armed = false;
        self.refreshCompletion(false);
    }

    pub fn moveLeft(self: *Viewer) void {
        if (self.cursor_col > 0) {
            const text = self.line(self.cursor_row);
            self.cursor_col = utf8Prev(text, @min(self.cursor_col, text.len));
        } else if (self.cursor_row > 0) {
            self.cursor_row -= 1;
            self.cursor_col = self.line(self.cursor_row).len;
        }
        self.want_col = self.cursor_col;
        self.refreshCompletion(false);
    }

    pub fn moveRight(self: *Viewer) void {
        const text = self.line(self.cursor_row);
        if (self.cursor_col < text.len) {
            self.cursor_col = utf8Next(text, self.cursor_col);
        } else if (self.cursor_row + 1 < self.lineCount()) {
            self.cursor_row += 1;
            self.cursor_col = 0;
        }
        self.want_col = self.cursor_col;
        self.refreshCompletion(false);
    }

    pub fn moveUp(self: *Viewer) void {
        if (self.cursor_row == 0) return;
        self.cursor_row -= 1;
        self.cursor_col = @min(self.want_col, self.line(self.cursor_row).len);
        self.complete_open = false;
    }

    pub fn moveDown(self: *Viewer) void {
        if (self.cursor_row + 1 >= self.lineCount()) return;
        self.cursor_row += 1;
        self.cursor_col = @min(self.want_col, self.line(self.cursor_row).len);
        self.complete_open = false;
    }

    pub fn moveLineStart(self: *Viewer) void {
        self.cursor_col = 0;
        self.want_col = 0;
        self.complete_open = false;
    }

    pub fn moveLineEnd(self: *Viewer) void {
        self.cursor_col = self.line(self.cursor_row).len;
        self.want_col = self.cursor_col;
        self.complete_open = false;
    }

    pub fn moveFileStart(self: *Viewer) void {
        self.cursor_row = 0;
        self.cursor_col = 0;
        self.want_col = 0;
        self.scroll = 0;
        self.complete_open = false;
    }

    pub fn moveFileEnd(self: *Viewer) void {
        if (self.lineCount() == 0) return;
        self.cursor_row = self.lineCount() - 1;
        self.cursor_col = self.line(self.cursor_row).len;
        self.want_col = self.cursor_col;
        self.complete_open = false;
    }

    pub fn page(self: *Viewer, delta_lines: i32, visible: usize) void {
        const vis = @max(visible, 1);
        const next: i64 = @as(i64, @intCast(self.cursor_row)) + delta_lines;
        const last: i64 = if (self.lineCount() == 0) 0 else @intCast(self.lineCount() - 1);
        if (next < 0) {
            self.cursor_row = 0;
        } else if (next > last) {
            self.cursor_row = @intCast(last);
        } else {
            self.cursor_row = @intCast(next);
        }
        self.cursor_col = @min(self.want_col, self.line(self.cursor_row).len);
        self.complete_open = false;
        self.ensureCursorVisible(vis);
    }

    pub fn completeMove(self: *Viewer, delta: i32) void {
        if (!self.complete_open or self.complete_n == 0) return;
        const n: i32 = @intCast(self.complete_n);
        var sel: i32 = @intCast(self.complete_sel);
        sel += delta;
        while (sel < 0) sel += n;
        while (sel >= n) sel -= n;
        self.complete_sel = @intCast(sel);
    }

    pub fn acceptCompletion(self: *Viewer, allocator: std.mem.Allocator) bool {
        if (!self.complete_open or self.complete_n == 0) return false;
        if (self.complete_sel >= self.complete_n) return false;
        const hit = self.complete_hits[self.complete_sel];
        const text = self.line(self.cursor_row);
        const col = @min(self.cursor_col, text.len);
        const prefix = complete.identPrefix(text, col);
        const at = self.cursorByte() - prefix.len;
        self.splice(allocator, at, prefix.len, hit.insert()) catch return false;
        self.cursor_col = col - prefix.len + hit.insert().len;
        self.want_col = self.cursor_col;
        self.complete_open = false;
        self.complete_n = 0;
        self.discard_armed = false;
        return true;
    }

    pub fn refreshCompletion(self: *Viewer, force: bool) void {
        if (!self.canEdit()) {
            self.complete_open = false;
            return;
        }
        const text = self.line(self.cursor_row);
        const col = @min(self.cursor_col, text.len);
        if (!force and col > 0) {
            const kind = highlight.kindAt(text, self.language, col - 1);
            if (kind == .comment or kind == .string) {
                self.complete_open = false;
                return;
            }
        }
        const prefix = complete.identPrefix(text, col);
        if (!force and prefix.len == 0) {
            self.complete_open = false;
            return;
        }
        const buf = self.content orelse "";
        self.complete_n = complete.suggest(self.language, prefix, buf, &self.complete_hits);
        self.complete_open = self.complete_n > 0;
        if (self.complete_sel >= self.complete_n) self.complete_sel = 0;
    }

    pub fn save(self: *Viewer, io: std.Io) bool {
        const path = self.abs_path orelse return false;
        const data = self.content orelse return false;
        const file = std.Io.Dir.createFileAbsolute(io, path, .{}) catch return false;
        defer file.close(io);
        file.writeStreamingAll(io, data) catch return false;
        self.dirty = false;
        self.discard_armed = false;
        return true;
    }

    fn cursorByte(self: *const Viewer) usize {
        const body = self.content orelse return 0;
        if (self.line_offsets.len == 0) return 0;
        const row = @min(self.cursor_row, self.line_offsets.len - 1);
        const start = self.line_offsets[row];
        const text = self.line(row);
        const col = @min(self.cursor_col, text.len);
        return @min(start + col, body.len);
    }

    fn clampCursor(self: *Viewer) void {
        const n = self.lineCount();
        if (n == 0) {
            self.cursor_row = 0;
            self.cursor_col = 0;
            return;
        }
        if (self.cursor_row >= n) self.cursor_row = n - 1;
        const text = self.line(self.cursor_row);
        if (self.cursor_col > text.len) self.cursor_col = text.len;
    }

    fn splice(self: *Viewer, allocator: std.mem.Allocator, at: usize, delete_n: usize, insert: []const u8) !void {
        const old = self.content orelse return error.NoContent;
        const at_c = @min(at, old.len);
        const del = @min(delete_n, old.len - at_c);
        const new_len = old.len - del + insert.len;
        if (new_len > max_file_bytes) return error.FileTooLarge;
        const next = try allocator.alloc(u8, new_len);
        @memcpy(next[0..at_c], old[0..at_c]);
        if (insert.len > 0) @memcpy(next[at_c..][0..insert.len], insert);
        @memcpy(next[at_c + insert.len ..], old[at_c + del ..]);
        allocator.free(old);
        self.content = next;
        self.dirty = true;
        try self.rebuild(allocator);
    }

    fn rebuild(self: *Viewer, allocator: std.mem.Allocator) !void {
        const body = self.content orelse return;
        const new_off = try buildLineOffsets(allocator, body);
        const old_off = self.line_offsets;
        self.line_offsets = new_off;
        const new_st = buildLineStates(allocator, self, self.language) catch {
            self.line_offsets = old_off;
            allocator.free(new_off);
            return error.OutOfMemory;
        };
        if (old_off.len > 0) allocator.free(old_off);
        if (self.line_states.len > 0) allocator.free(self.line_states);
        self.line_states = new_st;
        self.clampCursor();
    }

    fn load(self: *Viewer, allocator: std.mem.Allocator, io: std.Io, abs_path: []const u8) void {
        const raw = readLimited(allocator, io, abs_path, max_file_bytes) catch |err| {
            self.error_msg = switch (err) {
                error.NotFound => allocator.dupe(u8, "File not found") catch null,
                error.FileTooLarge => blk: {
                    self.too_large = true;
                    break :blk allocator.dupe(u8, "File is too large to edit (512 KiB limit)") catch null;
                },
                else => allocator.dupe(u8, "Could not read file") catch null,
            };
            return;
        };
        if (looksBinary(raw)) {
            allocator.free(raw);
            self.binary = true;
            self.error_msg = allocator.dupe(u8, "Binary file — nothing to highlight") catch null;
            return;
        }

        const expanded = expandTabs(allocator, raw) catch {
            allocator.free(raw);
            self.error_msg = allocator.dupe(u8, "Out of memory") catch null;
            return;
        };
        allocator.free(raw);

        var body = expanded;
        if (std.mem.startsWith(u8, body, "\xEF\xBB\xBF")) {
            const trimmed = allocator.dupe(u8, body[3..]) catch body;
            if (trimmed.ptr != body.ptr) allocator.free(body);
            body = trimmed;
        }

        self.content = body;
        self.line_offsets = buildLineOffsets(allocator, body) catch {
            self.error_msg = allocator.dupe(u8, "Out of memory") catch null;
            return;
        };
        self.line_states = buildLineStates(allocator, self, self.language) catch {
            self.error_msg = allocator.dupe(u8, "Out of memory") catch null;
            return;
        };
        self.cursor_row = 0;
        self.cursor_col = 0;
        self.want_col = 0;
        self.dirty = false;
    }
};

fn utf8Prev(s: []const u8, col: usize) usize {
    if (col == 0 or s.len == 0) return 0;
    var i = @min(col, s.len) - 1;
    while (i > 0 and (s[i] & 0xC0) == 0x80) i -= 1;
    return i;
}

fn utf8Next(s: []const u8, col: usize) usize {
    if (col >= s.len) return s.len;
    var i = col + 1;
    while (i < s.len and (s[i] & 0xC0) == 0x80) i += 1;
    return i;
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
    const n = @min(data.len, 4096);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const ch = data[i];
        if (ch == 0) return true;
        if (ch < 0x09 and ch != '\n' and ch != '\r' and ch != '\t') return true;
    }
    return false;
}

fn expandTabs(allocator: std.mem.Allocator, src: []const u8) ![]u8 {
    var extra: usize = 0;
    for (src) |ch| {
        if (ch == '\t') extra += 3;
    }
    if (extra == 0) return allocator.dupe(u8, src);
    var out = try allocator.alloc(u8, src.len + extra);
    var j: usize = 0;
    for (src) |ch| {
        if (ch == '\t') {
            out[j] = ' ';
            out[j + 1] = ' ';
            out[j + 2] = ' ';
            out[j + 3] = ' ';
            j += 4;
        } else {
            out[j] = ch;
            j += 1;
        }
    }
    return out[0..j];
}

fn buildLineOffsets(allocator: std.mem.Allocator, content: []const u8) ![]usize {
    var list: std.ArrayList(usize) = .empty;
    errdefer list.deinit(allocator);
    try list.append(allocator, 0);
    var i: usize = 0;
    while (i < content.len) : (i += 1) {
        if (content[i] == '\n') {
            try list.append(allocator, i + 1);
        }
    }
    if (content.len > 0 and content[content.len - 1] == '\n' and list.items.len > 1) {
        // Keep the trailing empty line so the last newline is visible.
    }
    return list.toOwnedSlice(allocator);
}

fn buildLineStates(allocator: std.mem.Allocator, viewer: *const Viewer, lang: Language) ![]ScanState {
    const n = viewer.line_offsets.len;
    const states = try allocator.alloc(ScanState, n);
    var state: ScanState = .code;
    var spans: [max_spans]Span = undefined;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        states[i] = state;
        const text = viewer.line(i);
        _ = highlight.highlightLine(text, lang, &state, &spans);
    }
    return states;
}

pub const detectLanguage = highlight.detectLanguage;
pub const languageLabel = highlight.languageLabel;
pub const colorFor = highlight.colorFor;
pub const highlightLine = highlight.highlightLine;
pub const identPrefix = complete.identPrefix;
