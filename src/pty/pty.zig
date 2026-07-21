const std = @import("std");
const builtin = @import("builtin");
const c = @import("../c.zig").c;

pub const Pty = struct {
    master_fd: c_int,
    child_pid: c.pid_t,
    cols: u16,
    rows: u16,

    pub fn create(cols: u16, rows: u16) !Pty {
        var master: c_int = -1;
        var slave: c_int = -1;
        var ws = c.struct_winsize{
            .ws_row = rows,
            .ws_col = cols,
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

            // Prefer user shell, then common defaults.
            const shell_env = std.c.getenv("SHELL");
            const shell: [*:0]const u8 = shell_env orelse "/bin/zsh";
            const argv = [_]?[*:0]const u8{ shell, "-l", null };
            _ = c.execvp(shell, @ptrCast(&argv));
            c._exit(127);
        }

        // Parent
        _ = c.close(slave);
        try setNonBlocking(master);

        return .{
            .master_fd = master,
            .child_pid = pid,
            .cols = cols,
            .rows = rows,
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
