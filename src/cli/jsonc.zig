//! Tiny JSONC string-key upsert for editor settings.json (comments allowed).

const std = @import("std");

pub const Pair = struct { k: []const u8, v: []const u8 };

/// Set `"key": "value"` in JSONC. Creates an object if `src` is empty.
/// Preserves surrounding text/comments when the key already exists.
pub fn upsertString(allocator: std.mem.Allocator, src: []const u8, key: []const u8, value: []const u8) ![]u8 {
    const quoted_val = try quoteJsonString(allocator, value);
    defer allocator.free(quoted_val);
    const replacement = try std.fmt.allocPrint(allocator, "\"{s}\": {s}", .{ key, quoted_val });
    defer allocator.free(replacement);

    const trimmed = std.mem.trim(u8, src, " \t\r\n");
    if (trimmed.len == 0) {
        return std.fmt.allocPrint(allocator, "{{\n    {s}\n}}\n", .{replacement});
    }

    if (findKeyValueRange(src, key)) |range| {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);
        try out.appendSlice(allocator, src[0..range.start]);
        try out.appendSlice(allocator, replacement);
        try out.appendSlice(allocator, src[range.end..]);
        return out.toOwnedSlice(allocator);
    }

    return insertBeforeClosingBrace(allocator, src, replacement);
}

pub fn upsertMany(
    allocator: std.mem.Allocator,
    src: []const u8,
    pairs: []const Pair,
) ![]u8 {
    var current = try allocator.dupe(u8, src);
    for (pairs) |p| {
        const next = try upsertString(allocator, current, p.k, p.v);
        allocator.free(current);
        current = next;
    }
    return current;
}

const Range = struct { start: usize, end: usize };

fn findKeyValueRange(src: []const u8, key: []const u8) ?Range {
    var i: usize = 0;
    while (i < src.len) {
        i = skipJunk(src, i);
        if (i >= src.len) break;
        if (src[i] != '"') {
            i += 1;
            continue;
        }
        const key_start = i;
        i += 1;
        const key_end = consumeJsonString(src, i) orelse return null;
        const got = src[i..key_end];
        i = key_end + 1; // skip closing quote
        i = skipJunk(src, i);
        if (i >= src.len or src[i] != ':') continue;
        if (!std.mem.eql(u8, got, key)) continue;
        i += 1;
        i = skipJunk(src, i);
        const value_end = skipJsonValue(src, i) orelse src.len;
        return .{ .start = key_start, .end = value_end };
    }
    return null;
}

fn insertBeforeClosingBrace(allocator: std.mem.Allocator, src: []const u8, replacement: []const u8) ![]u8 {
    const start = skipJunk(src, 0);
    const close_end = if (start < src.len and src[start] == '{')
        skipBalanced(src, start, '{', '}')
    else
        null;
    const brace = if (close_end) |end| end - 1 else {
        return std.fmt.allocPrint(allocator, "{{\n    {s}\n}}\n", .{replacement});
    };

    const before = std.mem.trimEnd(u8, src[0..brace], " \t\r\n");
    const needs_comma = before.len > 0 and before[before.len - 1] != '{' and before[before.len - 1] != ',';

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, std.mem.trimEnd(u8, src[0..brace], " \t"));
    if (needs_comma) try out.append(allocator, ',');
    try out.appendSlice(allocator, "\n    ");
    try out.appendSlice(allocator, replacement);
    try out.appendSlice(allocator, "\n");
    try out.appendSlice(allocator, src[brace..]);
    if (src.len == 0 or src[src.len - 1] != '\n') try out.append(allocator, '\n');
    return out.toOwnedSlice(allocator);
}

fn skipJunk(src: []const u8, start: usize) usize {
    var i = start;
    while (i < src.len) {
        const c = src[i];
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == ',') {
            i += 1;
            continue;
        }
        if (c == '/' and i + 1 < src.len and src[i + 1] == '/') {
            i += 2;
            while (i < src.len and src[i] != '\n') : (i += 1) {}
            continue;
        }
        if (c == '/' and i + 1 < src.len and src[i + 1] == '*') {
            i += 2;
            while (i + 1 < src.len and !(src[i] == '*' and src[i + 1] == '/')) : (i += 1) {}
            if (i + 1 < src.len) i += 2;
            continue;
        }
        break;
    }
    return i;
}

fn consumeJsonString(src: []const u8, start: usize) ?usize {
    var i = start;
    while (i < src.len) : (i += 1) {
        if (src[i] == '\\') {
            i += 1;
            continue;
        }
        if (src[i] == '"') return i;
    }
    return null;
}

fn skipJsonValue(src: []const u8, start: usize) ?usize {
    if (start >= src.len) return start;
    const c = src[start];
    if (c == '"') {
        const end = consumeJsonString(src, start + 1) orelse return null;
        return end + 1;
    }
    if (c == '{') return skipBalanced(src, start, '{', '}');
    if (c == '[') return skipBalanced(src, start, '[', ']');
    var i = start;
    while (i < src.len) : (i += 1) {
        switch (src[i]) {
            ',', '}', ']', ' ', '\t', '\n', '\r' => return i,
            else => {},
        }
    }
    return i;
}

fn skipBalanced(src: []const u8, start: usize, open: u8, close: u8) ?usize {
    var depth: usize = 0;
    var i = start;
    var in_str = false;
    var esc = false;
    while (i < src.len) {
        if (!in_str) {
            if (src[i] == '/' and i + 1 < src.len and src[i + 1] == '/') {
                i += 2;
                while (i < src.len and src[i] != '\n') : (i += 1) {}
                continue;
            }
            if (src[i] == '/' and i + 1 < src.len and src[i + 1] == '*') {
                i += 2;
                while (i + 1 < src.len and !(src[i] == '*' and src[i + 1] == '/')) : (i += 1) {}
                i = if (i + 1 < src.len) i + 2 else src.len;
                continue;
            }
        }
        const c = src[i];
        if (in_str) {
            if (esc) {
                esc = false;
            } else if (c == '\\') {
                esc = true;
            } else if (c == '"') {
                in_str = false;
            }
            i += 1;
            continue;
        }
        if (c == '"') {
            in_str = true;
            i += 1;
            continue;
        }
        if (c == open) depth += 1;
        if (c == close) {
            if (depth == 0) return null;
            depth -= 1;
            if (depth == 0) return i + 1;
        }
        i += 1;
    }
    return null;
}

fn quoteJsonString(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.append(allocator, '"');
    for (value) |c| {
        switch (c) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => {
                if (c < 0x20) {
                    var hex: [6]u8 = undefined;
                    const s = std.fmt.bufPrint(&hex, "\\u{x:0>4}", .{c}) catch unreachable;
                    try out.appendSlice(allocator, s);
                } else {
                    try out.append(allocator, c);
                }
            },
        }
    }
    try out.append(allocator, '"');
    return out.toOwnedSlice(allocator);
}
