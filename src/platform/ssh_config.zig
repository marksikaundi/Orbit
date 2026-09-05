//! Read Host entries from ~/.ssh/config for the SSH picker.

const std = @import("std");
const paths = @import("paths.zig");

pub const max_hosts = 48;
pub const max_name = 64;

pub const Host = struct {
    name: [max_name]u8 = undefined,
    name_len: u8 = 0,

    pub fn slice(self: *const Host) []const u8 {
        return self.name[0..self.name_len];
    }
};

pub fn load(allocator: std.mem.Allocator, io: std.Io, out: []Host) usize {
    const path = sshConfigPath(allocator) orelse return 0;
    defer allocator.free(path);
    const file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return 0;
    defer file.close(io);
    var buf: [4096]u8 = undefined;
    var reader = file.reader(io, &buf);
    const data = reader.interface.allocRemaining(allocator, .limited(128 * 1024)) catch return 0;
    defer allocator.free(data);
    return parse(data, out);
}

pub fn parse(data: []const u8, out: []Host) usize {
    var n: usize = 0;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        if (n >= out.len) break;
        var line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (!startsIgnoreCase(line, "host ") and !startsIgnoreCase(line, "host\t")) continue;
        const rest = std.mem.trim(u8, line[4..], " \t");
        var toks = std.mem.tokenizeAny(u8, rest, " \t");
        while (toks.next()) |tok| {
            if (n >= out.len) break;
            if (tok.len == 0 or tok[0] == '*' or tok[0] == '!') continue;
            if (tok[0] == '?') continue;
            var h: Host = .{};
            const copy = @min(tok.len, max_name);
            @memcpy(h.name[0..copy], tok[0..copy]);
            h.name_len = @intCast(copy);
            // Dedup
            var dup = false;
            for (out[0..n]) |prev| {
                if (std.mem.eql(u8, prev.slice(), h.slice())) {
                    dup = true;
                    break;
                }
            }
            if (dup) continue;
            out[n] = h;
            n += 1;
        }
    }
    return n;
}

fn startsIgnoreCase(s: []const u8, prefix: []const u8) bool {
    if (s.len < prefix.len) return false;
    return std.ascii.eqlIgnoreCase(s[0..prefix.len], prefix);
}

fn sshConfigPath(allocator: std.mem.Allocator) ?[]u8 {
    const home = paths.homeDir() orelse return null;
    return std.fmt.allocPrint(allocator, "{s}{c}.ssh{c}config", .{
        home,
        std.fs.path.sep,
        std.fs.path.sep,
    }) catch null;
}
