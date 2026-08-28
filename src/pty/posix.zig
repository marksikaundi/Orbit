//! POSIX PTY backend (macOS / Linux).

const std = @import("std");
const c = @import("../c.zig").c;
const options = @import("options.zig");

pub const CreateOptions = options.CreateOptions;
pub const ReadResult = options.ReadResult;

pub const Pty = struct {
    master_fd: c_int,
    child_pid: c.pid_t,
    cols: u16,
    rows: u16,
    /// False after the shell exits (EOF on master) or deinit.
    alive: bool = true,

    pub fn create(cols: u16, rows: u16) !Pty {
        return createWith(.{ .cols = cols, .rows = rows });
    }

    pub fn createWith(opts: CreateOptions) !Pty {
        var master: c_int = -1;
        var slave: c_int = -1;
        var ws = c.struct_winsize{
            .ws_row = opts.rows,
            .ws_col = opts.cols,
            .ws_xpixel = 0,
            .ws_ypixel = 0,
        };

        if (c.openpty(&master, &slave, null, null, &ws) != 0) {
            return error.OpenPtyFailed;
        }
        errdefer {
            _ = c.close(master);
            _ = c.close(slave);
        }

        const pid = c.fork();
        if (pid < 0) {
            return error.ForkFailed;
        }

        if (pid == 0) {
            // Child: become session leader and attach slave as controlling TTY.
            _ = c.close(master);
            if (c.setsid() < 0) c._exit(1);
            if (c.ioctl(slave, c.TIOCSCTTY, @as(c_int, 0)) < 0) c._exit(1);

            _ = c.dup2(slave, c.STDIN_FILENO);
            _ = c.dup2(slave, c.STDOUT_FILENO);
            _ = c.dup2(slave, c.STDERR_FILENO);
            if (slave > c.STDERR_FILENO) _ = c.close(slave);

            if (opts.cwd) |cwd| {
                var cwd_z: [std.fs.max_path_bytes:0]u8 = undefined;
                if (cwd.len >= cwd_z.len) c._exit(1);
                @memcpy(cwd_z[0..cwd.len], cwd);
                cwd_z[cwd.len] = 0;
                if (c.chdir(cwd_z[0..cwd.len :0]) != 0) {
                    // Non-fatal: continue in inherited cwd
                }
            }

            for (opts.env) |entry| {
                setEnvEntry(entry);
            }

            execChild(opts);
            c._exit(127);
        }

        // Parent
        _ = c.close(slave);
        try setNonBlocking(master);

        return .{
            .master_fd = master,
            .child_pid = pid,
            .cols = opts.cols,
            .rows = opts.rows,
            .alive = true,
        };
    }

    pub fn deinit(self: *Pty) void {
        if (self.alive) {
            self.terminateSession();
        }
        _ = c.close(self.master_fd);
        self.* = undefined;
    }

    /// Tear down the shell session without blocking the UI thread indefinitely.
    /// Child called `setsid()`, so negative pid targets the whole process group.
    fn terminateSession(self: *Pty) void {
        _ = c.kill(-self.child_pid, c.SIGTERM);
        _ = c.kill(self.child_pid, c.SIGTERM);

        var status: c_int = 0;
        var waited_ms: usize = 0;
        while (waited_ms < 150) : (waited_ms += 5) {
            const r = c.waitpid(self.child_pid, &status, c.WNOHANG);
            if (r != 0) {
                self.alive = false;
                return;
            }
            sleepMs(5);
        }

        _ = c.kill(-self.child_pid, c.SIGKILL);
        _ = c.kill(self.child_pid, c.SIGKILL);
        _ = c.waitpid(self.child_pid, &status, 0);
        self.alive = false;
    }

    pub fn resize(self: *Pty, cols: u16, rows: u16) void {
        self.cols = cols;
        self.rows = rows;
        var ws = c.struct_winsize{
            .ws_row = rows,
            .ws_col = cols,
            .ws_xpixel = 0,
            .ws_ypixel = 0,
        };
        _ = c.ioctl(self.master_fd, c.TIOCSWINSZ, &ws);
    }

    pub fn write(self: *Pty, bytes: []const u8) void {
        if (!self.alive) return;
        var offset: usize = 0;
        while (offset < bytes.len) {
            const n = c.write(self.master_fd, bytes.ptr + offset, bytes.len - offset);
            if (n < 0) {
                const err = std.c._errno().*;
                if (err == c.EAGAIN or err == c.EWOULDBLOCK) return;
                return;
            }
            offset += @intCast(n);
        }
    }

    /// Non-blocking read. Distinguishes "no data yet" from shell exit (EOF).
    pub fn read(self: *Pty, buffer: []u8) ReadResult {
        if (!self.alive) return .{ .len = 0, .eof = true };
        const n = c.read(self.master_fd, buffer.ptr, buffer.len);
        if (n < 0) {
            const err = std.c._errno().*;
            if (err == c.EAGAIN or err == c.EWOULDBLOCK) return .{ .len = 0, .eof = false };
            self.markExited();
            return .{ .len = 0, .eof = true };
        }
        if (n == 0) {
            self.markExited();
            return .{ .len = 0, .eof = true };
        }
        return .{ .len = @intCast(n), .eof = false };
    }

    fn markExited(self: *Pty) void {
        if (!self.alive) return;
        self.reapChild();
    }

    fn reapChild(self: *Pty) void {
        var status: c_int = 0;
        // Shell already exited (EOF) — reap without hanging the frame loop.
        const r = c.waitpid(self.child_pid, &status, c.WNOHANG);
        if (r == 0) {
            // Rare: EOF before the zombie is ready — brief bounded wait, then kill.
            var i: usize = 0;
            while (i < 20) : (i += 1) {
                if (c.waitpid(self.child_pid, &status, c.WNOHANG) != 0) break;
                sleepMs(5);
            } else {
                _ = c.kill(self.child_pid, c.SIGKILL);
                _ = c.waitpid(self.child_pid, &status, 0);
            }
        }
        self.alive = false;
    }
};

fn execChild(opts: CreateOptions) void {
    const shell_path = resolveShell(opts.shell);
    if (opts.command.len == 0) {
        const argv = [_]?[*:0]const u8{ shell_path, "-l", null };
        _ = c.execvp(shell_path, @ptrCast(&argv));
        return;
    }

    var storage: [48][768]u8 = undefined;
    var argv: [56]?[*:0]const u8 = undefined;
    if (opts.command.len > storage.len) return;
    if (opts.wait_after_command and opts.command.len + 6 > argv.len) return;

    if (opts.wait_after_command) {
        const script: [*:0]const u8 = "exec \"$@\"; exec \"$0\" -l";
        var n: usize = 0;
        argv[n] = shell_path;
        n += 1;
        argv[n] = "-l";
        n += 1;
        argv[n] = "-c";
        n += 1;
        argv[n] = script;
        n += 1;
        argv[n] = shell_path;
        n += 1;
        for (opts.command, 0..) |arg, i| {
            if (arg.len >= storage[i].len) return;
            @memcpy(storage[i][0..arg.len], arg);
            storage[i][arg.len] = 0;
            argv[n] = storage[i][0..arg.len :0];
            n += 1;
        }
        argv[n] = null;
        _ = c.execvp(shell_path, @ptrCast(&argv));
        return;
    }

    for (opts.command, 0..) |arg, i| {
        if (arg.len >= storage[i].len) return;
        @memcpy(storage[i][0..arg.len], arg);
        storage[i][arg.len] = 0;
        argv[i] = storage[i][0..arg.len :0];
    }
    argv[opts.command.len] = null;
    _ = c.execvp(argv[0].?, @ptrCast(&argv));
}

fn resolveShell(shell: ?[]const u8) [*:0]const u8 {
    if (shell) |s| {
        const Static = struct {
            var buf: [512]u8 = undefined;
        };
        if (s.len + 1 > Static.buf.len) {
            return "/bin/zsh";
        }
        @memcpy(Static.buf[0..s.len], s);
        Static.buf[s.len] = 0;
        return @ptrCast(&Static.buf);
    }
    const shell_env = std.c.getenv("SHELL");
    return shell_env orelse "/bin/zsh";
}

fn setEnvEntry(entry: []const u8) void {
    const eq = std.mem.indexOfScalar(u8, entry, '=') orelse return;
    const key = entry[0..eq];
    if (options.isUnsafeEnvKey(key)) return;
    var key_buf: [256:0]u8 = undefined;
    var val_buf: [1024:0]u8 = undefined;
    const val = entry[eq + 1 ..];
    if (key.len >= key_buf.len or val.len >= val_buf.len) return;
    @memcpy(key_buf[0..key.len], key);
    key_buf[key.len] = 0;
    @memcpy(val_buf[0..val.len], val);
    val_buf[val.len] = 0;
    _ = c.setenv(key_buf[0..key.len :0], val_buf[0..val.len :0], 1);
}

fn setNonBlocking(fd: c_int) !void {
    const flags = c.fcntl(fd, c.F_GETFL, @as(c_int, 0));
    if (flags < 0) return error.FcntlFailed;
    if (c.fcntl(fd, c.F_SETFL, flags | c.O_NONBLOCK) < 0) return error.FcntlFailed;
}

fn sleepMs(ms: u64) void {
    var req = c.struct_timespec{
        .tv_sec = @intCast(ms / 1000),
        .tv_nsec = @intCast((ms % 1000) * std.time.ns_per_ms),
    };
    _ = c.nanosleep(&req, null);
}
