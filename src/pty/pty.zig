//! Portable PTY facade — POSIX (macOS/Linux) or ConPTY (Windows).

const builtin = @import("builtin");
const options = @import("options.zig");

pub const CreateOptions = options.CreateOptions;
pub const ReadResult = options.ReadResult;

pub const Pty = switch (builtin.os.tag) {
    .windows => @import("windows.zig").Pty,
    .macos, .linux => @import("posix.zig").Pty,
    else => @compileError("Orbit PTY supports macOS, Linux, and Windows only"),
};
