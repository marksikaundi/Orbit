//! Shared PTY option / result types (POSIX + Windows ConPTY).

pub const CreateOptions = struct {
    cols: u16,
    rows: u16,
    /// Working directory for the shell process (absolute or relative).
    cwd: ?[]const u8 = null,
    /// Shell executable path; defaults are platform-specific.
    shell: ?[]const u8 = null,
    /// Extra environment entries as "KEY=VALUE".
    env: []const []const u8 = &.{},
};

pub const ReadResult = struct {
    len: usize,
    /// Master hit EOF — shell has exited (e.g. user typed `exit`).
    eof: bool,
};
