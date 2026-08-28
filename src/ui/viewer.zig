//! Syntax-highlighted file preview — open from search, palette, or a file path.

const std = @import("std");
const highlight = @import("../syntax/highlight.zig");

pub const Language = highlight.Language;
pub const Kind = highlight.Kind;
pub const ScanState = highlight.ScanState;
pub const Span = highlight.Span;
pub const max_spans = highlight.max_spans;

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

    pub fn line(self: *const Viewer, index: usize) []const u8 {
        const content = self.content orelse return "";
        if (index >= self.line_offsets.len) return "";
        const start = self.line_offsets[index];
        const end = if (index + 1 < self.line_offsets.len) self.line_offsets[index + 1] else content.len;
        var slice = content[start..end];
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

    fn load(self: *Viewer, allocator: std.mem.Allocator, io: std.Io, abs_path: []const u8) void {
        const raw = readLimited(allocator, io, abs_path, max_file_bytes) catch |err| {
            self.error_msg = switch (err) {
                error.NotFound => allocator.dupe(u8, "File not found") catch null,
                error.FileTooLarge => blk: {
                    self.too_large = true;
                    break :blk allocator.dupe(u8, "File is too large to preview (512 KiB limit)") catch null;
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
    }
};

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
