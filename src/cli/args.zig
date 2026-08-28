//! Launch CLI — directory/command flags used by IDEs, plus help / version / ide-setup.

const std = @import("std");

pub const Action = enum { run, help, version, ide_setup };

pub const ParseError = error{
    MissingValue,
    UnknownArgument,
    OutOfMemory,
};

pub const Launch = struct {
    action: Action = .run,
    /// Absolute or as-given working directory for the first shell.
    cwd: ?[]u8 = null,
    title: ?[]u8 = null,
    /// `-e` / `--command` argv (owned slices).
    execute: [][]u8 = &.{},
    wait_after_command: bool = false,
    skip_home: bool = false,
    /// `ide-setup --editor` value (null = all detected).
    editor: ?[]u8 = null,

    pub fn deinit(self: *Launch, allocator: std.mem.Allocator) void {
        if (self.cwd) |p| allocator.free(p);
        if (self.title) |t| allocator.free(t);
        if (self.editor) |e| allocator.free(e);
        for (self.execute) |a| allocator.free(a);
        if (self.execute.len > 0) allocator.free(self.execute);
        self.* = undefined;
    }
};

/// `args[0]` is argv0. Remaining tokens are flags / positionals.
pub fn parse(allocator: std.mem.Allocator, args: []const []const u8) ParseError!Launch {
    var out: Launch = .{};
    errdefer out.deinit(allocator);

    if (args.len <= 1) return out;

    var i: usize = 1;
    var execute_at: ?usize = null;

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (execute_at != null) break;

        if (i == 1 and isIdeSetup(arg)) {
            out.action = .ide_setup;
            continue;
        }
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            out.action = .help;
            return out;
        }
        if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--version")) {
            out.action = .version;
            return out;
        }
        if (std.mem.eql(u8, arg, "--wait-after-command") or std.mem.eql(u8, arg, "--wait-after-command=true")) {
            out.wait_after_command = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--wait-after-command=false")) {
            out.wait_after_command = false;
            continue;
        }
        if (takeEq(arg, "--working-directory")) |v| {
            try setCwd(&out, allocator, v);
            continue;
        }
        if (takeEq(arg, "--workdir")) |v| {
            try setCwd(&out, allocator, v);
            continue;
        }
        if (takeEq(arg, "--directory")) |v| {
            try setCwd(&out, allocator, v);
            continue;
        }
        if (takeEq(arg, "--cwd")) |v| {
            try setCwd(&out, allocator, v);
            continue;
        }
        if (takeEq(arg, "--title")) |v| {
            try setOwned(&out.title, allocator, v);
            continue;
        }
        if (takeEq(arg, "--editor")) |v| {
            try setOwned(&out.editor, allocator, v);
            continue;
        }

        if (isCwdFlag(arg) or std.mem.eql(u8, arg, "-d")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            try setCwd(&out, allocator, args[i]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--title") or std.mem.eql(u8, arg, "-t")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            try setOwned(&out.title, allocator, args[i]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--editor")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            try setOwned(&out.editor, allocator, args[i]);
            continue;
        }
        if (std.mem.eql(u8, arg, "-e") or std.mem.eql(u8, arg, "--command") or std.mem.eql(u8, arg, "--")) {
            execute_at = i + 1;
            break;
        }
        if (arg.len > 0 and arg[0] == '-') {
            return error.UnknownArgument;
        }

        // Positional path: folder to open (or a file — use its parent).
        try setCwd(&out, allocator, arg);
    }

    if (execute_at) |start| {
        if (start < args.len) {
            const n = args.len - start;
            const owned = try allocator.alloc([]u8, n);
            var filled: usize = 0;
            errdefer {
                for (owned[0..filled]) |a| allocator.free(a);
                allocator.free(owned);
            }
            for (args[start..], 0..) |a, k| {
                owned[k] = try allocator.dupe(u8, a);
                filled = k + 1;
            }
            out.execute = owned;
            out.skip_home = true;
        }
    }

    return out;
}

pub fn printHelp() void {
    std.debug.print(
        \\Orbit terminal — stay in the flow
        \\
        \\Usage:
        \\  orbit [path] [options]
        \\  orbit ide-setup [--editor cursor|code|codium|windsurf|all]
        \\
        \\Launch:
        \\  path                         Folder (or file) to open a shell in
        \\  -d, --working-directory DIR  Working directory (Alacritty / Ghostty / VS Code)
        \\      --workdir DIR            Same (Konsole)
        \\      --directory DIR          Same (Kitty)
        \\      --cwd DIR                Same
        \\  -e, --command CMD [args…]    Run command instead of a login shell
        \\  --                           Rest of argv is the command
        \\      --wait-after-command     Keep a shell open after -e exits
        \\  -t, --title TITLE            First tab title
        \\  -h, --help                   Show this help
        \\  -V, --version                Print version
        \\
        \\IDEs (Cursor, VS Code, VSCodium, Windsurf, …):
        \\  orbit ide-setup              Set Orbit as the external terminal and
        \\                               install the editor extension (Open in Orbit)
        \\
        \\Examples:
        \\  orbit ~/code/api
        \\  orbit --working-directory=/tmp
        \\  orbit -e git status
        \\
    , .{});
}

fn isIdeSetup(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "ide-setup") or std.mem.eql(u8, arg, "--ide-setup");
}

fn isCwdFlag(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "--working-directory") or
        std.mem.eql(u8, arg, "--workdir") or
        std.mem.eql(u8, arg, "--directory") or
        std.mem.eql(u8, arg, "--cwd");
}

fn takeEq(arg: []const u8, flag: []const u8) ?[]const u8 {
    if (arg.len <= flag.len + 1) return null;
    if (!std.mem.startsWith(u8, arg, flag)) return null;
    if (arg[flag.len] != '=') return null;
    return arg[flag.len + 1 ..];
}

fn setCwd(out: *Launch, allocator: std.mem.Allocator, path: []const u8) !void {
    try setOwned(&out.cwd, allocator, path);
    out.skip_home = true;
}

fn setOwned(slot: *?[]u8, allocator: std.mem.Allocator, value: []const u8) !void {
    if (slot.*) |old| allocator.free(old);
    slot.* = try allocator.dupe(u8, value);
}
