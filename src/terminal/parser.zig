const Screen = @import("screen.zig").Screen;

/// Minimal Phase 1 stream handler: printable text + basic controls,
/// skips CSI/OSC escape sequences so shell output is readable.
pub const Parser = struct {
    state: State = .ground,

    const State = enum {
        ground,
        esc,
        csi,
        osc,
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

    fn consume(self: *Parser, screen: *Screen, byte: u8) void {
        switch (self.state) {
            .ground => switch (byte) {
                0x1B => self.state = .esc,
                else => screen.putChar(byte),
            },
            .esc => switch (byte) {
                '[' => self.state = .csi,
                ']' => self.state = .osc,
                '(', ')', '*', '+' => self.state = .esc, // charset designate; wait one more in simple form
                else => self.state = .ground, // swallow single-char ESC sequences
            },
            .csi => {
                // CSI ends on a byte in 0x40-0x7E
                if (byte >= 0x40 and byte <= 0x7E) {
                    self.state = .ground;
                }
            },
            .osc => switch (byte) {
                0x07 => self.state = .ground, // BEL terminator
                0x1B => self.state = .osc_esc,
                else => {},
            },
            .osc_esc => {
                if (byte == '\\') {
                    self.state = .ground; // ST
                } else {
                    self.state = .osc;
                }
            },
        }
    }
};

test "parser strips csi" {
    const std = @import("std");
    var screen = try Screen.init(std.testing.allocator, 20, 2);
    defer screen.deinit();
    var parser = Parser.init();
    parser.feed(&screen, "\x1b[31mHi\x1b[0m");
    try std.testing.expectEqual(@as(u21, 'H'), screen.cellAtConst(0, 0).codepoint);
    try std.testing.expectEqual(@as(u21, 'i'), screen.cellAtConst(1, 0).codepoint);
}
