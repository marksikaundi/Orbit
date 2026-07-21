const std = @import("std");
const builtin = @import("builtin");
const c = @import("../c.zig").c;

pub const CreateOptions = struct {
    cols: u16,
    rows: u16,
    /// Working directory for the shell process (absolute or relative).
    cwd: ?[]const u8 = null,
    /// Shell executable path; defaults to $SHELL or /bin/zsh.
    shell: ?[]const u8 = null,
    /// Extra environment entries as "KEY=VALUE".
    env: []const []const u8 = &.{},
};

pub const Pty = struct {
    master_fd: c_int,
    child_pid: c.pid_t,
    cols: u16,
    rows: u16,

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
                var cwd_z: [std.fs.max_path_bytes]u8 = undefined;
                if (cwd.len + 1 > cwd_z.len) c._exit(1);
                @memcpy(cwd_z[0..cwd.len], cwd);
                cwd_z[cwd.len] = 0;
                if (c.chdir(&cwd_z) != 0) {
                    // Non-fatal: continue in inherited cwd
                }
            }

            for (opts.env) |entry| {
                setEnvEntry(entry);
            }

            const shell_path = resolveShell(opts.shell);
            const argv = [_]?[*:0]const u8{ shell_path, "-l", null };
            _ = c.execvp(shell_path, @ptrCast(&argv));
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
        };
    }

    pub fn deinit(self: *Pty) void {
        _ = c.kill(self.child_pid, c.SIGTERM);
        _ = c.close(self.master_fd);
        self.* = undefined;
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

    /// Non-blocking read into buffer. Returns bytes read (0 if nothing available).
    pub fn read(self: *Pty, buffer: []u8) usize {
        const n = c.read(self.master_fd, buffer.ptr, buffer.len);
        if (n < 0) {
            const err = std.c._errno().*;
            if (err == c.EAGAIN or err == c.EWOULDBLOCK) return 0;
            return 0;
        }
        return @intCast(n);
    }
};

fn resolveShell(shell: ?[]const u8) [*:0]const u8 {
    if (shell) |s| {
        // Shell path must remain valid for the lifetime of exec — use static buffer in child only.
        // Child process: copy to static storage.
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
    var key_buf: [256]u8 = undefined;
    var val_buf: [1024]u8 = undefined;
    const key = entry[0..eq];
    const val = entry[eq + 1 ..];
    if (key.len + 1 > key_buf.len or val.len + 1 > val_buf.len) return;
    @memcpy(key_buf[0..key.len], key);
    key_buf[key.len] = 0;
    @memcpy(val_buf[0..val.len], val);
    val_buf[val.len] = 0;
    _ = c.setenv(&key_buf, &val_buf, 1);
}

fn setNonBlocking(fd: c_int) !void {
    const flags = c.fcntl(fd, c.F_GETFL, @as(c_int, 0));
    if (flags < 0) return error.FcntlFailed;
    if (c.fcntl(fd, c.F_SETFL, flags | c.O_NONBLOCK) < 0) return error.FcntlFailed;
}

comptime {
    if (builtin.os.tag != .macos and builtin.os.tag != .linux) {
        @compileError("Phase 1 PTY supports macOS and Linux only");
    }
}
