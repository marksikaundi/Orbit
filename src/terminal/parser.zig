const std = @import("std");
const Screen = @import("screen.zig").Screen;
const cell_mod = @import("cell.zig");
const Color = cell_mod.Color;

/// VT100/xterm-style stream parser for common CSI/OSC/SGR sequences.
pub const Parser = struct {
    state: State = .ground,
    intermediate: u8 = 0,
    params: [16]u16 = .{0} ** 16,
    param_count: u8 = 0,
    param_idx: u8 = 0,
    osc_buf: [256]u8 = undefined,
    osc_len: u16 = 0,
    /// CSI private prefix: `?` (DEC), `>` (secondary DA), `=` (ANSI).
    private_marker: u8 = 0,
    /// Replies for DSR / DA that the PTY must write back (cursor report, etc.).
    reply_buf: [128]u8 = undefined,
    reply_len: u8 = 0,
    /// Last OSC 9 / OSC 99 notify payload (for status toast).
    notify_msg: [96]u8 = undefined,
    notify_len: u16 = 0,
    utf8_buf: [4]u8 = undefined,
    utf8_len: u8 = 0,
    utf8_need: u8 = 0,

    const State = enum {
        ground,
        esc,
        csi_entry,
        csi_param,
        csi_intermediate,
        osc_string,
        osc_esc,
    };

    pub fn init() Parser {
        return .{};
    }

    pub fn feed(self: *Parser, screen: *Screen, bytes: []const u8) void {
        for (bytes) |byte| {
            self.consume(screen, byte);
        }
    }

    fn resetParams(self: *Parser) void {
        self.params = .{0} ** 16;
        self.param_count = 0;
        self.param_idx = 0;
        self.intermediate = 0;
        self.private_marker = 0;
    }

    fn consume(self: *Parser, screen: *Screen, byte: u8) void {
        switch (self.state) {
            .ground => self.ground(screen, byte),
            .esc => self.esc(screen, byte),
            .csi_entry, .csi_param, .csi_intermediate => self.csi(screen, byte),
            .osc_string => self.osc(screen, byte),
            .osc_esc => {
                if (byte == '\\') {
                    self.finishOsc(screen);
                    self.state = .ground;
                } else {
                    self.state = .osc_string;
                    self.oscPush(byte);
                }
            },
        }
    }

    fn ground(self: *Parser, screen: *Screen, byte: u8) void {
        if (byte == 0x1B) {
            self.state = .esc;
            return;
        }
        // UTF-8 multi-byte
        if (self.utf8_need > 0) {
            if (byte & 0xC0 == 0x80) {
                self.utf8_buf[self.utf8_len] = byte;
                self.utf8_len += 1;
                self.utf8_need -= 1;
                if (self.utf8_need == 0) {
                    const cp = std.unicode.utf8Decode(self.utf8_buf[0..self.utf8_len]) catch {
                        self.utf8_len = 0;
                        return;
                    };
                    self.utf8_len = 0;
                    screen.putChar(@intCast(cp));
                }
            } else {
                self.utf8_need = 0;
                self.utf8_len = 0;
                self.ground(screen, byte);
            }
            return;
        }
        if (byte >= 0xC0) {
            self.utf8_need = std.unicode.utf8ByteSequenceLength(byte) catch 0;
            if (self.utf8_need <= 1) {
                self.utf8_need = 0;
                screen.putChar(byte);
                return;
            }
            self.utf8_buf[0] = byte;
            self.utf8_len = 1;
            self.utf8_need -= 1;
            return;
        }
        screen.putChar(byte);
    }

    fn esc(self: *Parser, screen: *Screen, byte: u8) void {
        switch (byte) {
            '[' => {
                self.resetParams();
                self.state = .csi_entry;
            },
            ']' => {
                self.osc_len = 0;
                self.state = .osc_string;
            },
            '7' => {
                screen.saveCursor();
                self.state = .ground;
            },
            '8' => {
                screen.restoreCursor();
                self.state = .ground;
            },
            'D' => {
                screen.index();
                self.state = .ground;
            },
            'M' => {
                screen.reverseIndex();
                self.state = .ground;
            },
            'E' => {
                screen.cursor_col = 0;
                screen.lineFeed();
                self.state = .ground;
            },
            'c' => {
                screen.softReset();
                self.state = .ground;
            },
            '(', ')', '*', '+' => {
                // charset designate — swallow next byte
                self.state = .esc; // wait: use intermediate hack
                self.intermediate = byte;
            },
            else => {
                if (self.intermediate == '(' or self.intermediate == ')' or self.intermediate == '*' or self.intermediate == '+') {
                    self.intermediate = 0;
                    self.state = .ground;
                } else {
                    self.state = .ground;
                }
            },
        }
    }

    fn csi(self: *Parser, screen: *Screen, byte: u8) void {
        if (byte == '?' or byte == '>' or byte == '=') {
            self.private_marker = byte;
            return;
        }
        if (byte >= 0x30 and byte <= 0x39) { // digit
            self.state = .csi_param;
            const d: u16 = byte - '0';
            const cur = &self.params[self.param_idx];
            cur.* = @min(cur.* *| 10 +| d, 9999);
            if (self.param_count == self.param_idx) self.param_count += 1;
            return;
        }
        if (byte == ';') {
            self.state = .csi_param;
            if (self.param_idx + 1 < self.params.len) {
                self.param_idx += 1;
                if (self.param_count <= self.param_idx) self.param_count = self.param_idx + 1;
            }
            return;
        }
        if (byte >= 0x20 and byte <= 0x2F) { // intermediate
            self.state = .csi_intermediate;
            self.intermediate = byte;
            return;
        }
        if (byte >= 0x40 and byte <= 0x7E) {
            self.dispatchCsi(screen, byte);
            self.state = .ground;
            return;
        }
        // ignore C0 in CSI except ESC
        if (byte == 0x1B) {
            self.state = .esc;
        }
    }

    fn param(self: *const Parser, idx: u8, default: u16) u16 {
        if (idx < self.param_count and self.params[idx] != 0) return self.params[idx];
        // 0 often means default for cursor ops
        if (idx < self.param_count) return if (self.params[idx] == 0) default else self.params[idx];
        return default;
    }

    /// CSI L/M/S/T repeats: more than the region height is wasted work and froze the UI at 9999.
    fn regionRepeat(self: *const Parser, screen: *const Screen) u16 {
        const height = screen.scroll_bottom -| screen.scroll_top +| 1;
        return @min(self.param(0, 1), @max(height, 1));
    }

    fn dispatchCsi(self: *Parser, screen: *Screen, final: u8) void {
        switch (final) {
            'A' => screen.moveCursorRel(0, -@as(i32, @intCast(self.param(0, 1)))),
            'B' => screen.moveCursorRel(0, @as(i32, @intCast(self.param(0, 1)))),
            'C' => screen.moveCursorRel(@as(i32, @intCast(self.param(0, 1))), 0),
            'D' => screen.moveCursorRel(-@as(i32, @intCast(self.param(0, 1))), 0),
            'E' => {
                screen.moveCursorRel(0, @as(i32, @intCast(self.param(0, 1))));
                screen.cursor_col = 0;
            },
            'F' => {
                screen.moveCursorRel(0, -@as(i32, @intCast(self.param(0, 1))));
                screen.cursor_col = 0;
            },
            'G' => screen.moveCursor(self.param(0, 1) -| 1, screen.cursor_row),
            'H', 'f' => {
                const row = self.param(0, 1) -| 1;
                const col = self.param(1, 1) -| 1;
                screen.moveCursor(col, row);
            },
            'J' => screen.eraseInDisplay(self.param(0, 0)),
            'K' => screen.eraseInLine(self.param(0, 0)),
            'L' => { // insert lines — approximate as scroll down at cursor
                var n = self.regionRepeat(screen);
                while (n > 0) : (n -= 1) {
                    // shift rows down within region from cursor
                    const top = screen.cursor_row;
                    const bottom = screen.scroll_bottom;
                    if (top >= bottom) break;
                    var r: u16 = bottom;
                    while (r > top) : (r -= 1) {
                        const dst = screen.cells[@as(usize, r) * screen.cols ..][0..screen.cols];
                        const src = screen.cells[@as(usize, r - 1) * screen.cols ..][0..screen.cols];
                        @memcpy(dst, src);
                    }
                    const blank = cell_mod.Cell.blankWith(screen.default_fg, screen.default_bg);
                    @memset(screen.cells[@as(usize, top) * screen.cols ..][0..screen.cols], blank);
                }
                screen.dirty = true;
            },
            'M' => { // delete lines
                var n = self.regionRepeat(screen);
                while (n > 0) : (n -= 1) {
                    const top = screen.cursor_row;
                    const bottom = screen.scroll_bottom;
                    var r = top;
                    while (r < bottom) : (r += 1) {
                        const dst = screen.cells[@as(usize, r) * screen.cols ..][0..screen.cols];
                        const src = screen.cells[@as(usize, r + 1) * screen.cols ..][0..screen.cols];
                        @memcpy(dst, src);
                    }
                    const blank = cell_mod.Cell.blankWith(screen.default_fg, screen.default_bg);
                    @memset(screen.cells[@as(usize, bottom) * screen.cols ..][0..screen.cols], blank);
                }
                screen.dirty = true;
            },
            'P' => screen.deleteChars(self.param(0, 1)),
            '@' => screen.insertChars(self.param(0, 1)),
            'S' => { // scroll up
                var n = self.regionRepeat(screen);
                while (n > 0) : (n -= 1) screen.scrollUpRegion();
            },
            'T' => {
                var n = self.regionRepeat(screen);
                while (n > 0) : (n -= 1) screen.scrollDownRegion();
            },
            'd' => screen.moveCursor(screen.cursor_col, self.param(0, 1) -| 1),
            'm' => self.applySgr(screen),
            'r' => {
                const top = if (self.param_count == 0) 1 else self.param(0, 1);
                const bottom = if (self.param_count < 2) screen.rows else self.param(1, screen.rows);
                screen.setScrollRegion(top -| 1, bottom -| 1);
            },
            's' => screen.saveCursor(),
            'u' => screen.restoreCursor(),
            'n' => self.deviceStatus(screen),
            'h', 'l' => self.setMode(screen, final == 'h'),
            'c' => self.deviceAttributes(),
            else => {},
        }
    }

    fn setMode(self: *Parser, screen: *Screen, enable: bool) void {
        if (self.private_marker != '?') return;
        var i: u8 = 0;
        const n = if (self.param_count == 0) @as(u8, 1) else self.param_count;
        while (i < n) : (i += 1) {
            const mode: u16 = if (self.param_count == 0) 0 else self.params[i];
            switch (mode) {
                6 => screen.origin_mode = enable,
                7 => screen.auto_wrap = enable,
                25 => screen.cursor_visible = enable,
                47, 1047 => {
                    if (enable) screen.enterAltScreen(false, false) else screen.leaveAltScreen(false);
                },
                1048 => {
                    if (enable) screen.saveCursor() else screen.restoreCursor();
                },
                1049 => {
                    if (enable) screen.enterAltScreen(true, true) else screen.leaveAltScreen(true);
                },
                else => {},
            }
        }
    }

    fn deviceStatus(self: *Parser, screen: *const Screen) void {
        if (self.private_marker == '?') return;
        const p = self.param(0, 0);
        if (p == 5) {
            self.appendReply("\x1b[0n");
            return;
        }
        if (p == 6) {
            var tmp: [32]u8 = undefined;
            const msg = std.fmt.bufPrint(
                &tmp,
                "\x1b[{d};{d}R",
                .{ screen.cursor_row + 1, screen.cursor_col + 1 },
            ) catch return;
            self.appendReply(msg);
        }
    }

    fn deviceAttributes(self: *Parser) void {
        if (self.private_marker == '>') {
            // Secondary DA — report as xterm-like so vim/less enable 256-color + alt screen.
            self.appendReply("\x1b[>0;276;0c");
            return;
        }
        if (self.private_marker != 0) return;
        // Primary DA — VT220 + ANSI color.
        self.appendReply("\x1b[?62;22c");
    }

    fn appendReply(self: *Parser, bytes: []const u8) void {
        const space = self.reply_buf.len - self.reply_len;
        if (space == 0 or bytes.len == 0) return;
        const n = @min(bytes.len, space);
        @memcpy(self.reply_buf[self.reply_len..][0..n], bytes[0..n]);
        self.reply_len += @intCast(n);
    }

    // Make scrollUpRegion/scrollDownRegion accessible — they're private on Screen.
    // We called them from parser — need to make them pub. Fix screen.zig.

    fn applySgr(self: *Parser, screen: *Screen) void {
        if (self.param_count == 0) {
            screen.resetAttrs();
            return;
        }
        var i: u8 = 0;
        while (i < self.param_count) : (i += 1) {
            const p = self.params[i];
            switch (p) {
                0 => screen.resetAttrs(),
                1 => screen.attrs.bold = true,
                2 => screen.attrs.dim = true,
                3 => screen.attrs.italic = true,
                4 => screen.attrs.underline = true,
                5, 6 => screen.attrs.blink = true,
                7 => screen.attrs.reverse = true,
                8 => screen.attrs.hidden = true,
                9 => screen.attrs.strikethrough = true,
                22 => {
                    screen.attrs.bold = false;
                    screen.attrs.dim = false;
                },
                23 => screen.attrs.italic = false,
                24 => screen.attrs.underline = false,
                25 => screen.attrs.blink = false,
                27 => screen.attrs.reverse = false,
                28 => screen.attrs.hidden = false,
                29 => screen.attrs.strikethrough = false,
                30...37 => screen.fg = Color.fromIndex(@intCast(p - 30)),
                38 => {
                    // 38;5;n or 38;2;r;g;b
                    if (i + 1 < self.param_count) {
                        i += 1;
                        if (self.params[i] == 5 and i + 1 < self.param_count) {
                            i += 1;
                            screen.fg = Color.fromIndex(@intCast(@min(self.params[i], 255)));
                        } else if (self.params[i] == 2 and i + 3 < self.param_count) {
                            const r: u8 = @intCast(@min(self.params[i + 1], 255));
                            const g: u8 = @intCast(@min(self.params[i + 2], 255));
                            const b: u8 = @intCast(@min(self.params[i + 3], 255));
                            i += 3;
                            screen.fg = Color.rgb(r, g, b);
                        }
                    }
                },
                39 => screen.fg = screen.default_fg,
                40...47 => screen.bg = Color.fromIndex(@intCast(p - 40)),
                48 => {
                    if (i + 1 < self.param_count) {
                        i += 1;
                        if (self.params[i] == 5 and i + 1 < self.param_count) {
                            i += 1;
                            screen.bg = Color.fromIndex(@intCast(@min(self.params[i], 255)));
                        } else if (self.params[i] == 2 and i + 3 < self.param_count) {
                            const r: u8 = @intCast(@min(self.params[i + 1], 255));
                            const g: u8 = @intCast(@min(self.params[i + 2], 255));
                            const b: u8 = @intCast(@min(self.params[i + 3], 255));
                            i += 3;
                            screen.bg = Color.rgb(r, g, b);
                        }
                    }
                },
                49 => screen.bg = screen.default_bg,
                90...97 => screen.fg = Color.fromIndex(@intCast(p - 90 + 8)),
                100...107 => screen.bg = Color.fromIndex(@intCast(p - 100 + 8)),
                else => {},
            }
        }
    }

    fn oscPush(self: *Parser, byte: u8) void {
        if (self.osc_len < self.osc_buf.len) {
            self.osc_buf[self.osc_len] = byte;
            self.osc_len += 1;
        }
    }

    fn osc(self: *Parser, screen: *Screen, byte: u8) void {
        switch (byte) {
            0x07 => {
                self.finishOsc(screen);
                self.state = .ground;
            },
            0x1B => self.state = .osc_esc,
            else => self.oscPush(byte),
        }
    }

    fn finishOsc(self: *Parser, screen: *Screen) void {
        _ = screen;
        const data = self.osc_buf[0..self.osc_len];
        // OSC 0/2 — window title (ignored for now).
        // OSC 9 ; message — iTerm2-style notification → status toast.
        // OSC 99 ; message — Orbit status toast.
        if (std.mem.startsWith(u8, data, "9;") or std.mem.startsWith(u8, data, "99;")) {
            const msg = if (std.mem.startsWith(u8, data, "99;"))
                data["99;".len..]
            else
                data["9;".len..];
            const n = @min(msg.len, self.notify_msg.len);
            if (n > 0) {
                @memcpy(self.notify_msg[0..n], msg[0..n]);
                self.notify_len = @intCast(n);
            }
        }
        self.osc_len = 0;
    }
};
