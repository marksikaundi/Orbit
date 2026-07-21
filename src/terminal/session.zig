//! One shell session: PTY + screen + parser + selection + workspace metadata.

const std = @import("std");
const Pty = @import("../pty/pty.zig").Pty;
const Screen = @import("screen.zig").Screen;
const Parser = @import("parser.zig").Parser;
const Selection = @import("selection.zig").Selection;
const Color = @import("cell.zig").Color;

pub const SessionOptions = struct {
    cols: u16,
    rows: u16,
    title: []const u8 = "Shell",
    cwd: ?[]const u8 = null,
    shell: ?[]const u8 = null,
    env: []const []const u8 = &.{},
};

pub const Session = struct {
    allocator: std.mem.Allocator,
    pty: Pty,
    screen: Screen,
    parser: Parser,
    selection: Selection = .{},
    title: []u8,
    cwd: []u8,
    shell: []u8,
    env: [][]u8,
    read_buf: [8192]u8 = undefined,
    /// False after the shell exits (`exit`, Ctrl+D, crash).
    alive: bool = true,

    pub fn create(allocator: std.mem.Allocator, cols: u16, rows: u16, title: []const u8) !*Session {
        return createWith(allocator, .{
            .cols = cols,
            .rows = rows,
            .title = title,
        });
    }

    pub fn createWith(allocator: std.mem.Allocator, opts: SessionOptions) !*Session {
        const self = try allocator.create(Session);
        errdefer allocator.destroy(self);

        const cwd_owned = try allocator.dupe(u8, opts.cwd orelse defaultCwd());
        errdefer allocator.free(cwd_owned);
        const shell_owned = try allocator.dupe(u8, opts.shell orelse defaultShell());
        errdefer allocator.free(shell_owned);

        var env_owned: [][]u8 = &.{};
        if (opts.env.len > 0) {
            env_owned = try allocator.alloc([]u8, opts.env.len);
            errdefer allocator.free(env_owned);
            for (opts.env, 0..) |e, i| {
                env_owned[i] = try allocator.dupe(u8, e);
            }
        }
        errdefer freeEnv(allocator, env_owned);

        // Build env slice for PTY (as []const []const u8)
        var env_refs: []const []const u8 = &.{};
        var env_refs_owned: ?[][]const u8 = null;
        if (env_owned.len > 0) {
            const refs = try allocator.alloc([]const u8, env_owned.len);
            for (env_owned, 0..) |e, i| refs[i] = e;
            env_refs_owned = refs;
            env_refs = refs;
        }
        defer if (env_refs_owned) |r| allocator.free(r);

        var pty = try Pty.createWith(.{
            .cols = opts.cols,
            .rows = opts.rows,
            .cwd = cwd_owned,
            .shell = shell_owned,
            .env = env_refs,
        });
        errdefer pty.deinit();

        var screen = try Screen.init(allocator, opts.cols, opts.rows);
        errdefer screen.deinit();

        const title_owned = try allocator.dupe(u8, opts.title);
        errdefer allocator.free(title_owned);

        self.* = .{
            .allocator = allocator,
            .pty = pty,
            .screen = screen,
            .parser = Parser.init(),
            .title = title_owned,
            .cwd = cwd_owned,
            .shell = shell_owned,
            .env = env_owned,
            .alive = true,
        };
        return self;
    }

    pub fn destroy(self: *Session) void {
        freeEnv(self.allocator, self.env);
        self.allocator.free(self.shell);
        self.allocator.free(self.cwd);
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
        if (!self.alive) return;
        // Drain all available output; shell exit surfaces as EOF.
        while (true) {
            const result = self.pty.read(&self.read_buf);
            if (result.len > 0) {
                self.parser.feed(&self.screen, self.read_buf[0..result.len]);
            }
            if (result.eof) {
                self.alive = false;
                return;
            }
            if (result.len == 0) return;
        }
    }

    pub fn write(self: *Session, bytes: []const u8) void {
        if (!self.alive) return;
        self.pty.write(bytes);
    }

    fn freeEnv(allocator: std.mem.Allocator, env: [][]u8) void {
        for (env) |e| allocator.free(e);
        if (env.len > 0) allocator.free(env);
    }

    fn defaultCwd() []const u8 {
        if (std.c.getenv("HOME")) |h| return std.mem.span(h);
        return "/";
    }

    fn defaultShell() []const u8 {
        if (std.c.getenv("SHELL")) |s| return std.mem.span(s);
        return "/bin/zsh";
    }
};
