//! Shared PTY option / result types (POSIX + Windows ConPTY).

const std = @import("std");

pub const CreateOptions = struct {
    cols: u16,
    rows: u16,
    /// Working directory for the shell process (absolute or relative).
    cwd: ?[]const u8 = null,
    /// Shell executable path; defaults are platform-specific.
    shell: ?[]const u8 = null,
    /// Extra environment entries as "KEY=VALUE".
    env: []const []const u8 = &.{},
    /// If non-empty, exec this argv instead of a login shell (`orbit -e`).
    command: []const []const u8 = &.{},
    /// After `command` exits, start a login shell so the window stays open.
    wait_after_command: bool = false,
};

pub const ReadResult = struct {
    len: usize,
    /// Master hit EOF — shell has exited (e.g. user typed `exit`).
    eof: bool,
};

/// Environment keys that must never be injected from workspace/plugin data.
pub fn isUnsafeEnvKey(key: []const u8) bool {
    const blocked = [_][]const u8{
        "LD_PRELOAD",
        "LD_LIBRARY_PATH",
        "DYLD_INSERT_LIBRARIES",
        "DYLD_LIBRARY_PATH",
        "DYLD_FORCE_FLAT_NAMESPACE",
        "BASH_ENV",
        "ENV",
        "SHELLOPTS",
        "GCONV_PATH",
        "TERMINFO",
        "PERL5OPT",
        "PYTHONPATH",
        "NODE_OPTIONS",
        "ZDOTDIR",
        // Windows process-hijack vectors (also blocked on child env overlays).
        "PATHEXT",
        "ComSpec",
        "COMSPEC",
        "PSModulePath",
        "PATH",
    };
    for (blocked) |b| {
        if (std.ascii.eqlIgnoreCase(key, b)) return true;
    }
    return false;
}
