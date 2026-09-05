//! xterm mouse protocol encoding (DECSET 1000 / 1002 / 1006).

const std = @import("std");

pub const Tracking = enum { off, x10, button, any };

pub const Button = enum(u8) {
    left = 0,
    middle = 1,
    right = 2,
    release = 3,
    wheel_up = 64,
    wheel_down = 65,
};

pub const Event = struct {
    button: u8,
    col: u16,
    row: u16,
    press: bool,
    motion: bool,
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
};

/// Write a mouse report into `buf`. Returns bytes written (0 if tracking is off).
pub fn encode(tracking: Tracking, sgr: bool, ev: Event, buf: []u8) usize {
    if (tracking == .off or buf.len < 8) return 0;
    if (tracking == .x10 and (!ev.press or ev.motion)) return 0;
    if (tracking == .button and ev.motion and !ev.press) return 0;

    var b = ev.button;
    if (ev.motion) b += 32;
    if (ev.shift) b += 4;
    if (ev.alt) b += 8;
    if (ev.ctrl) b += 16;

    const x = ev.col +| 1;
    const y = ev.row +| 1;

    if (sgr or tracking != .x10) {
        const final: u8 = if (ev.press or ev.motion) 'M' else 'm';
        const msg = std.fmt.bufPrint(buf, "\x1b[<{d};{d};{d}{c}", .{ b, x, y, final }) catch return 0;
        return msg.len;
    }

    // X10: CSI M Cb Cx Cy with +32 encoding; coords clamp to 223.
    if (buf.len < 6) return 0;
    buf[0] = 0x1B;
    buf[1] = '[';
    buf[2] = 'M';
    buf[3] = @intCast(32 + @min(b, 223));
    buf[4] = @intCast(32 + @min(x, 223));
    buf[5] = @intCast(32 + @min(y, 223));
    return 6;
}

pub fn wheelButton(yoff: f64) ?u8 {
    if (yoff > 0.1) return 64;
    if (yoff < -0.1) return 65;
    return null;
}
