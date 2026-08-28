//! One shell session: PTY + screen + parser + selection + workspace metadata.

const std = @import("std");
const Pty = @import("../pty/pty.zig").Pty;
const Screen = @import("screen.zig").Screen;
const Parser = @import("parser.zig").Parser;
const Selection = @import("selection.zig").Selection;
const Color = @import("cell.zig").Color;
const shell_guard = @import("../platform/shell.zig");
const options = @import("../pty/options.zig");

pub const SessionOptions = struct {
    cols: u16,
    rows: u16,
    title: []const u8 = "Shell",
    cwd: ?[]const u8 = null,
    shell: ?[]const u8 = null,
    env: []const []const u8 = &.{},
    command: []const []const u8 = &.{},
    wait_after_command: bool = false,
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
    /// True after the PTY has produced any output (prompt / MOTD). Used to defer injected commands.
    output_seen: bool = false,
    /// Pending status toast from OSC notify or notable terminal lines.
    pending_status: [96]u8 = undefined,
    pending_status_len: usize = 0,
    /// Strip ANSI while assembling printable lines for event detection.
    line_buf: [160]u8 = undefined,
    line_len: usize = 0,
    ansi: AnsiSkip = .none,

    const AnsiSkip = enum { none, esc, csi, osc };

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
        const shell_owned = try allocator.dupe(u8, shell_guard.sanitize(opts.shell));
        errdefer allocator.free(shell_owned);

        var env_owned: [][]u8 = &.{};
        if (opts.env.len > 0) {
            var filtered: std.ArrayList([]u8) = .empty;
            errdefer {
                for (filtered.items) |e| allocator.free(e);
                filtered.deinit(allocator);
            }
            for (opts.env) |e| {
                const eq = std.mem.indexOfScalar(u8, e, '=') orelse continue;
                if (options.isUnsafeEnvKey(e[0..eq])) continue;
                try filtered.append(allocator, try allocator.dupe(u8, e));
            }
            env_owned = try filtered.toOwnedSlice(allocator);
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
            .command = opts.command,
            .wait_after_command = opts.wait_after_command,
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
                self.output_seen = true;
                const chunk = self.read_buf[0..result.len];
                self.parser.feed(&self.screen, chunk);
                self.ingestForStatus(chunk);
                if (self.parser.notify_len > 0) {
                    self.pushStatus(self.parser.notify_msg[0..self.parser.notify_len]);
                    self.parser.notify_len = 0;
                }
            }
            if (result.eof) {
                self.alive = false;
                return;
            }
            if (result.len == 0) return;
        }
    }

    /// Consume a pending status message produced by OSC / notable lines.
    pub fn takeStatus(self: *Session) ?[]const u8 {
        if (self.pending_status_len == 0) return null;
        const msg = self.pending_status[0..self.pending_status_len];
        self.pending_status_len = 0;
        return msg;
    }

    pub fn write(self: *Session, bytes: []const u8) void {
        if (!self.alive) return;
        self.pty.write(bytes);
    }

    fn pushStatus(self: *Session, msg: []const u8) void {
        const trimmed = trimWs(msg);
        if (trimmed.len == 0) return;
        const n = @min(trimmed.len, self.pending_status.len);
        @memcpy(self.pending_status[0..n], trimmed[0..n]);
        self.pending_status_len = n;
    }

    /// Build printable lines (skipping CSI/OSC) and surface create/edit/error notices.
    fn ingestForStatus(self: *Session, bytes: []const u8) void {
        for (bytes) |b| {
            switch (self.ansi) {
                .none => {
                    if (b == 0x1B) {
                        self.ansi = .esc;
                        continue;
                    }
                    if (b == '\n' or b == '\r') {
                        self.classifyCompletedLine();
                        self.line_len = 0;
                        continue;
                    }
                    if (b >= 0x20 and b != 0x7F) {
                        if (self.line_len < self.line_buf.len) {
                            self.line_buf[self.line_len] = b;
                            self.line_len += 1;
                        }
                    }
                },
                .esc => {
                    if (b == '[') {
                        self.ansi = .csi;
                    } else if (b == ']') {
                        self.ansi = .osc;
                    } else {
                        self.ansi = .none;
                    }
                },
                .csi => {
                    if (b >= 0x40 and b <= 0x7E) self.ansi = .none;
                },
                .osc => {
                    if (b == 0x07) {
                        self.ansi = .none;
                    } else if (b == 0x1B) {
                        self.ansi = .esc; // OSC … ST (ESC \)
                    }
                },
            }
        }
    }

    fn classifyCompletedLine(self: *Session) void {
        if (self.line_len < 4) return;
        const line = trimWs(self.line_buf[0..self.line_len]);
        if (line.len < 4) return;

        // Conservative markers so everyday prompts don't spam the toast.
        const notable =
            containsIgnoreCase(line, "error:") or
            containsIgnoreCase(line, "fatal:") or
            containsIgnoreCase(line, "panic:") or
            startsWithIgnoreCase(line, "error ") or
            containsIgnoreCase(line, " failed") or
            containsIgnoreCase(line, "created ") or
            containsIgnoreCase(line, "created:") or
            containsIgnoreCase(line, "wrote ") or
            containsIgnoreCase(line, "written ") or
            containsIgnoreCase(line, "saved ") or
            containsIgnoreCase(line, "saved.") or
            containsIgnoreCase(line, "edited ") or
            containsIgnoreCase(line, "deleted ") or
            containsIgnoreCase(line, "removed ");

        if (!notable) return;
        self.pushStatus(line);
    }

    fn freeEnv(allocator: std.mem.Allocator, env: [][]u8) void {
        for (env) |e| allocator.free(e);
        if (env.len > 0) allocator.free(env);
    }

    fn defaultCwd() []const u8 {
        return @import("../platform/paths.zig").defaultCwd();
    }
};

fn trimWs(s: []const u8) []const u8 {
    var start: usize = 0;
    var end = s.len;
    while (start < end and (s[start] == ' ' or s[start] == '\t')) : (start += 1) {}
    while (end > start and (s[end - 1] == ' ' or s[end - 1] == '\t')) : (end -= 1) {}
    return s[start..end];
}

fn containsIgnoreCase(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0 or needle.len > hay.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(hay[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn startsWithIgnoreCase(hay: []const u8, needle: []const u8) bool {
    if (needle.len > hay.len) return false;
    return std.ascii.eqlIgnoreCase(hay[0..needle.len], needle);
}
