//! Parse linter output into jumpable diagnostics.

const std = @import("std");

pub const Diagnostic = struct {
    path: []const u8,
    line: u32,
    col: u32,
    message: []const u8,
};

pub const max_diagnostics: usize = 64;

/// Parse GNU/unix `path:line:col: message` (col optional).
pub fn parseUnix(text: []const u8, out: []Diagnostic) usize {
    var n: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        if (n >= out.len) break;
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (parseUnixLine(line)) |d| {
            out[n] = d;
            n += 1;
        }
    }
    return n;
}

pub fn parseUnixLine(line: []const u8) ?Diagnostic {
    const colon1 = std.mem.indexOfScalar(u8, line, ':') orelse return null;
    if (colon1 == 0 or colon1 + 1 >= line.len) return null;
    const rest = line[colon1 + 1 ..];
    const colon2 = std.mem.indexOfScalar(u8, rest, ':') orelse return null;

    const line_s = std.mem.trim(u8, rest[0..colon2], " \t");
    const line_no = std.fmt.parseInt(u32, line_s, 10) catch return null;
    if (line_no == 0) return null;

    var col: u32 = 1;
    var msg = rest[colon2 + 1 ..];
    const colon3 = std.mem.indexOfScalar(u8, msg, ':');
    if (colon3) |c3| {
        const col_s = std.mem.trim(u8, msg[0..c3], " \t");
        if (std.fmt.parseInt(u32, col_s, 10) catch null) |parsed| {
            col = @max(parsed, 1);
            msg = msg[c3 + 1 ..];
        }
    }
    msg = std.mem.trim(u8, msg, " \t");
    if (msg.len == 0) msg = line;

    return .{
        .path = line[0..colon1],
        .line = line_no,
        .col = col,
        .message = msg,
    };
}

/// Zero-based row/col for the viewer (clamped).
pub fn viewerPos(d: Diagnostic) struct { row: usize, col: usize } {
    const row: usize = if (d.line == 0) 0 else d.line - 1;
    const col: usize = if (d.col == 0) 0 else d.col - 1;
    return .{ .row = row, .col = col };
}
