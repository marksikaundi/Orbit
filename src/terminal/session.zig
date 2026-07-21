//! One shell session: PTY + screen + parser + selection.

const std = @import("std");
const Pty = @import("../pty/pty.zig").Pty;
const Screen = @import("screen.zig").Screen;
const Parser = @import("parser.zig").Parser;
const Selection = @import("selection.zig").Selection;
const Color = @import("cell.zig").Color;

pub const Session = struct {
    allocator: std.mem.Allocator,
    pty: Pty,
    screen: Screen,
    parser: Parser,
    selection: Selection = .{},
    title: []u8,
    read_buf: [8192]u8 = undefined,

    pub fn create(allocator: std.mem.Allocator, cols: u16, rows: u16, title: []const u8) !*Session {
        const self = try allocator.create(Session);
        errdefer allocator.destroy(self);

        var pty = try Pty.create(cols, rows);
        errdefer pty.deinit();

        var screen = try Screen.init(allocator, cols, rows);
        errdefer screen.deinit();

        const title_owned = try allocator.dupe(u8, title);
        errdefer allocator.free(title_owned);

        self.* = .{
            .allocator = allocator,
            .pty = pty,
            .screen = screen,
            .parser = Parser.init(),
            .title = title_owned,
        };
        return self;
    }

    pub fn destroy(self: *Session) void {
        self.allocator.free(self.title);
        self.screen.deinit();
        self.pty.deinit();
        self.allocator.destroy(self);
    }

    pub fn setTheme(self: *Session, fg: Color, bg: Color) void {
        self.screen.setThemeColors(fg, bg);
    }

    pub fn setScrollback(self: *Session, max: usize) void {
        self.screen.scrollback_max = max;
    }

    pub fn resize(self: *Session, cols: u16, rows: u16) void {
        self.screen.resize(cols, rows) catch return;
        self.pty.resize(cols, rows);
    }

    pub fn tick(self: *Session) void {
        const n = self.pty.read(&self.read_buf);
        if (n > 0) {
            self.parser.feed(&self.screen, self.read_buf[0..n]);
        }
    }

    pub fn write(self: *Session, bytes: []const u8) void {
        self.pty.write(bytes);
    }
};
