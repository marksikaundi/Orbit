//! Unit tests — PTY lifecycle must not hang the UI thread.

const std = @import("std");
const Pty = @import("../../pty/pty.zig").Pty;
const c = @import("../../c.zig").c;

fn sleepMs(ms: u64) void {
    var req = c.struct_timespec{
        .tv_sec = @intCast(ms / 1000),
        .tv_nsec = @intCast((ms % 1000) * std.time.ns_per_ms),
    };
    _ = c.nanosleep(&req, null);
}

test "deinit of a live shell returns promptly" {
    var pty = try Pty.create(40, 12);
    // Hung waitpid after SIGTERM used to freeze Orbit ("not responding") on Ctrl+W.
    pty.deinit();
}

test "deinit after shell exit returns promptly" {
    var pty = try Pty.create(40, 12);
    pty.write("exit\r");
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
    pty.write("printf hi\r");
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
