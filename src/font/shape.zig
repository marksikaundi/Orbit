//! Programming-ligature shaping (HarfBuzz-compatible API).
//!
//! System HarfBuzz is optional (`-Dharfbuzz`). This module always provides
//! the sequences coding fonts expect so `=>` `!=` `->` render as one unit.

const std = @import("std");

pub const Ligature = struct {
    seq: []const u21,
};

pub const table = [_][]const u21{
    &[_]u21{ '.', '.', '.' },
    &[_]u21{ '=', '=', '=' },
    &[_]u21{ '!', '=', '=' },
    &[_]u21{ '=', '>' },
    &[_]u21{ '=', '=' },
    &[_]u21{ '!', '=' },
    &[_]u21{ '-', '>' },
    &[_]u21{ '<', '-' },
    &[_]u21{ '<', '=' },
    &[_]u21{ '>', '=' },
    &[_]u21{ ':', '=' },
    &[_]u21{ ':', ':' },
    &[_]u21{ '|', '>' },
    &[_]u21{ '&', '&' },
    &[_]u21{ '|', '|' },
    &[_]u21{ '<', '<' },
    &[_]u21{ '>', '>' },
};

/// Longest matching ligature starting at `cps[0]`.
pub fn match(cps: []const u21) ?[]const u21 {
    if (cps.len < 2) return null;
    var best: ?[]const u21 = null;
    for (table) |seq| {
        if (cps.len < seq.len) continue;
        if (std.mem.eql(u21, cps[0..seq.len], seq)) {
            if (best == null or seq.len > best.?.len) best = seq;
        }
    }
    return best;
}

/// Match a screen row of codepoints starting at `col`.
pub fn matchRow(screen: anytype, row: u16, col: u16) ?u8 {
    if (col + 1 >= screen.cols) return null;
    var buf: [4]u21 = undefined;
    var n: u8 = 0;
    var c = col;
    while (c < screen.cols and n < buf.len) : (c += 1) {
        buf[n] = screen.visibleCell(c, row).codepoint;
        n += 1;
    }
    const hit = match(buf[0..n]) orelse return null;
    return @intCast(hit.len);
}
