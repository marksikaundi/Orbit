//! Case-sensitive / regex-lite matching for terminal search.

const std = @import("std");

pub const Options = struct {
    case_sensitive: bool = false,
    regex: bool = false,
};

/// First index of `pat` in `hay`, honoring `opts`.
pub fn find(hay: []const u8, pat: []const u8, opts: Options) ?usize {
    if (pat.len == 0) return null;
    if (!opts.regex) {
        return if (opts.case_sensitive)
            std.mem.indexOf(u8, hay, pat)
        else
            indexOfIgnoreCase(hay, pat);
    }
    return regexFind(hay, pat, opts.case_sensitive);
}

pub fn indexOfIgnoreCase(hay: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or needle.len > hay.len) return if (needle.len == 0) 0 else null;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        if (eqlIgnoreCase(hay[i .. i + needle.len], needle)) return i;
    }
    return null;
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (std.ascii.toLower(x) != std.ascii.toLower(y)) return false;
    }
    return true;
}

/// Minimal regex: literals, `.`, `*`, `+`, `?`, `^`, `$`, `\d\w\s`, `[abc]`, `[a-z]`.
fn regexFind(hay: []const u8, pat: []const u8, case_sensitive: bool) ?usize {
    var start: usize = 0;
    const anchored = pat.len > 0 and pat[0] == '^';
    const p = if (anchored) pat[1..] else pat;
    if (anchored) {
        return if (regexMatchHere(hay, 0, p, case_sensitive)) 0 else null;
    }
    while (start <= hay.len) : (start += 1) {
        if (regexMatchHere(hay, start, p, case_sensitive)) return start;
    }
    return null;
}

fn regexMatchHere(hay: []const u8, hi: usize, pat: []const u8, cs: bool) bool {
    if (pat.len == 0) return true;
    if (pat.len == 1 and pat[0] == '$') return hi == hay.len;

    const atom, const rest0 = takeAtom(pat) orelse return false;
    var rest = rest0;
    var quant: u8 = 0; // 0 none, '*' '+' '?'
    if (rest.len > 0 and (rest[0] == '*' or rest[0] == '+' or rest[0] == '?')) {
        quant = rest[0];
        rest = rest[1..];
    }

    if (quant == 0) {
        if (hi >= hay.len) return false;
        if (!atomMatch(hay[hi], atom, cs)) return false;
        return regexMatchHere(hay, hi + 1, rest, cs);
    }
    if (quant == '?') {
        if (hi < hay.len and atomMatch(hay[hi], atom, cs)) {
            if (regexMatchHere(hay, hi + 1, rest, cs)) return true;
        }
        return regexMatchHere(hay, hi, rest, cs);
    }
    var count: usize = 0;
    var i = hi;
    while (i < hay.len and atomMatch(hay[i], atom, cs)) {
        count += 1;
        i += 1;
        if (quant == '*' or quant == '+') {
            // greedy with backtrack
        } else break;
    }
    if (quant == '+' and count == 0) return false;
    var k = count;
    while (true) {
        if (regexMatchHere(hay, hi + k, rest, cs)) return true;
        if (k == 0) return quant == '*';
        k -= 1;
        if (quant == '+' and k == 0) {
            return regexMatchHere(hay, hi, rest, cs) and false; // already handled
        }
        if (k == 0 and quant == '+') return false;
        if (k == 0) return regexMatchHere(hay, hi, rest, cs);
    }
}

const Atom = union(enum) {
    any,
    lit: u8,
    cls: [32]u8,
    digit,
    word,
    space,
};

fn takeAtom(pat: []const u8) ?struct { Atom, []const u8 } {
    if (pat.len == 0) return null;
    if (pat[0] == '.') return .{ .any, pat[1..] };
    if (pat[0] == '\\' and pat.len >= 2) {
        return switch (pat[1]) {
            'd' => .{ .digit, pat[2..] },
            'w' => .{ .word, pat[2..] },
            's' => .{ .space, pat[2..] },
            else => .{ .{ .lit = pat[1] }, pat[2..] },
        };
    }
    if (pat[0] == '[') {
        const close = std.mem.indexOfScalar(u8, pat[1..], ']') orelse return .{ .{ .lit = '[' }, pat[1..] };
        var cls: [32]u8 = .{0} ** 32;
        const inner = pat[1 .. 1 + close];
        var n: usize = 0;
        var i: usize = 0;
        while (i < inner.len and n < cls.len) {
            if (i + 2 < inner.len and inner[i + 1] == '-') {
                var a = inner[i];
                var b = inner[i + 2];
                if (a > b) {
                    const t = a;
                    a = b;
                    b = t;
                }
                var ch = a;
                while (ch <= b and n < cls.len) : (ch += 1) {
                    cls[n] = ch;
                    n += 1;
                }
                i += 3;
            } else {
                cls[n] = inner[i];
                n += 1;
                i += 1;
            }
        }
        return .{ .{ .cls = cls }, pat[2 + close ..] };
    }
    return .{ .{ .lit = pat[0] }, pat[1..] };
}

fn atomMatch(ch: u8, atom: Atom, cs: bool) bool {
    return switch (atom) {
        .any => true,
        .lit => |l| if (cs) ch == l else std.ascii.toLower(ch) == std.ascii.toLower(l),
        .digit => ch >= '0' and ch <= '9',
        .word => (ch >= '0' and ch <= '9') or (ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z') or ch == '_',
        .space => ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r',
        .cls => |cls| blk: {
            for (cls) |c| {
                if (c == 0) break;
                if (cs) {
                    if (ch == c) break :blk true;
                } else if (std.ascii.toLower(ch) == std.ascii.toLower(c)) break :blk true;
            }
            break :blk false;
        },
    };
}
