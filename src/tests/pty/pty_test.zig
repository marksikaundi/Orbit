//! Unit tests — PTY lifecycle must not hang the UI thread.

const std = @import("std");
const builtin = @import("builtin");
const Pty = @import("../../pty/pty.zig").Pty;

fn sleepMs(ms: u64) void {
    if (builtin.os.tag == .windows) {
        const Sleep = struct {
            extern "kernel32" fn Sleep(dwMilliseconds: u32) callconv(.winapi) void;
        };
        Sleep.Sleep(@intCast(ms));
        return;
    }
    const c = @import("../../c.zig").c;
    var req = c.struct_timespec{
        .tv_sec = @intCast(ms / 1000),
        .tv_nsec = @intCast((ms % 1000) * std.time.ns_per_ms),
    };
    _ = c.nanosleep(&req, null);
}

fn exitCommand() []const u8 {
    return if (builtin.os.tag == .windows) "exit\r\n" else "exit\r";
}

fn echoCommand() []const u8 {
    return if (builtin.os.tag == .windows) "echo hi\r\n" else "printf hi\r";
}

test "deinit of a live shell returns promptly" {
    var pty = try Pty.create(40, 12);
    // Blocking waitpid after SIGKILL used to freeze Orbit ("not responding") on Ctrl+W.
    pty.deinit();
}

test "deinit after shell exit returns promptly" {
    var pty = try Pty.create(40, 12);
    pty.write(exitCommand());
    var buf: [512]u8 = undefined;
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        const r = pty.read(&buf);
        if (r.eof) break;
        sleepMs(10);
    }
    pty.deinit();
}

test "write and read do not crash after create" {
    var pty = try Pty.create(40, 12);
    defer pty.deinit();
    pty.write(echoCommand());
    var buf: [512]u8 = undefined;
    var saw: usize = 0;
    var i: usize = 0;
    while (i < 30) : (i += 1) {
        const r = pty.read(&buf);
        saw += r.len;
        if (r.eof) break;
        if (saw > 0) break;
        sleepMs(10);
    }
}
