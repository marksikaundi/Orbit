//! Detect http(s) URLs in a terminal line for click-to-open.

const std = @import("std");
const Screen = @import("../terminal/screen.zig").Screen;

pub const Span = struct {
    col: u16,
    len: u16,
};

/// Find an http/https URL covering `col` on visible `row`.
pub fn at(screen: *const Screen, col: u16, row: u16) ?Span {
    var line: [512]u8 = undefined;
    var n: usize = 0;
    var c: u16 = 0;
    while (c < screen.cols and n + 4 < line.len) : (c += 1) {
        const cp = screen.visibleCell(c, row).codepoint;
        if (cp == 0) continue;
        if (cp < 32 or cp == 0x7F) break;
        if (cp < 128) {
            line[n] = @intCast(cp);
            n += 1;
        } else {
            break;
        }
    }
    const text = line[0..n];
    var i: usize = 0;
    while (i < text.len) {
        const rest = text[i..];
        const start = indexOfUrl(rest) orelse break;
        const abs = i + start;
        const end = urlEnd(text, abs);
        if (abs <= col and col < end) {
            return .{ .col = @intCast(abs), .len = @intCast(end - abs) };
        }
        i = end;
    }
    return null;
}

pub fn sliceOf(screen: *const Screen, row: u16, span: Span, buf: []u8) []const u8 {
    var n: usize = 0;
    var c: u16 = span.col;
    const last = span.col +| span.len;
    while (c < last and c < screen.cols and n < buf.len) : (c += 1) {
        const cp = screen.visibleCell(c, row).codepoint;
        if (cp < 32 or cp >= 127) break;
        buf[n] = @intCast(cp);
        n += 1;
    }
    return buf[0..n];
}

fn indexOfUrl(s: []const u8) ?usize {
    if (std.mem.indexOf(u8, s, "https://")) |i| return i;
    if (std.mem.indexOf(u8, s, "http://")) |i| return i;
    return null;
}

fn urlEnd(s: []const u8, start: usize) usize {
    var i = start;
    while (i < s.len) : (i += 1) {
        const ch = s[i];
        if (!urlChar(ch)) break;
    }
    while (i > start) {
        const ch = s[i - 1];
        if (ch == '.' or ch == ',' or ch == ';' or ch == ':' or ch == ')' or ch == ']' or ch == '\'') {
            i -= 1;
            continue;
        }
        break;
    }
    return i;
}

fn urlChar(ch: u8) bool {
    if (ch >= 'a' and ch <= 'z') return true;
    if (ch >= 'A' and ch <= 'Z') return true;
    if (ch >= '0' and ch <= '9') return true;
    return switch (ch) {
        '-', '.', '_', '~', ':', '/', '?', '#', '[', ']', '@', '!', '$', '&', '\'', '(', ')', '*', '+', ',', ';', '=', '%' => true,
        else => false,
    };
}
