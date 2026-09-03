//! Run a plugin `[tool]` — user-owned command or script, never auto-executes.

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");

pub const max_stdout: usize = 256 * 1024;
pub const max_stderr: usize = 64 * 1024;

pub const Context = struct {
    plugin: []const u8 = "",
    action: []const u8 = "",
    file: []const u8 = "",
    language: []const u8 = "",
    cwd: []const u8 = "",
    selection: []const u8 = "",
    buffer: []const u8 = "",
    plugin_dir: []const u8 = "",
    prompt: []const u8 = "",
};

pub const Result = struct {
    allocator: std.mem.Allocator,
    stdout: []u8,
    stderr: []u8,
    code: u8,

    pub fn deinit(self: *Result) void {
        self.allocator.free(self.stdout);
        self.allocator.free(self.stderr);
        self.* = undefined;
    }
};

pub fn expand(allocator: std.mem.Allocator, template: []const u8, ctx: Context) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < template.len) {
        if (template[i] == '{' ) {
            if (matchToken(template, i, "{file}")) |n| {
                try out.appendSlice(allocator, ctx.file);
                i += n;
                continue;
            }
            if (matchToken(template, i, "{cwd}")) |n| {
                try out.appendSlice(allocator, ctx.cwd);
                i += n;
                continue;
            }
            if (matchToken(template, i, "{language}")) |n| {
                try out.appendSlice(allocator, ctx.language);
                i += n;
                continue;
            }
            if (matchToken(template, i, "{action}")) |n| {
                try out.appendSlice(allocator, ctx.action);
                i += n;
                continue;
            }
            if (matchToken(template, i, "{plugin}")) |n| {
                try out.appendSlice(allocator, ctx.plugin);
                i += n;
                continue;
            }
            if (matchToken(template, i, "{dir}")) |n| {
                try out.appendSlice(allocator, ctx.plugin_dir);
                i += n;
                continue;
            }
            if (matchToken(template, i, "{prompt}")) |n| {
                try out.appendSlice(allocator, ctx.prompt);
                i += n;
                continue;
            }
            if (matchToken(template, i, "{selection}")) |n| {
                try out.appendSlice(allocator, ctx.selection);
                i += n;
                continue;
            }
        }
        try out.append(allocator, template[i]);
        i += 1;
    }
    return out.toOwnedSlice(allocator);
}

pub fn stdinFor(tool: *const types.ToolSpec, ctx: Context) []const u8 {
    return switch (tool.stdin) {
        .none => "",
        .buffer => if (ctx.buffer.len > 0) ctx.buffer else ctx.selection,
        .selection => if (ctx.selection.len > 0) ctx.selection else ctx.buffer,
    };
}

pub fn run(
    allocator: std.mem.Allocator,
    io: std.Io,
    plugin: *const types.Plugin,
    ctx: Context,
) !Result {
    if (!plugin.tool.hasRunner()) return error.NoTool;

    var argv_owned: std.ArrayList([]u8) = .empty;
    defer {
        for (argv_owned.items) |s| allocator.free(s);
        argv_owned.deinit(allocator);
    }

    const script_abs = try resolveScript(allocator, plugin);
    defer if (script_abs) |p| allocator.free(p);

    const command = blk: {
        if (plugin.tool.command) |c| {
            if (c.len > 0) break :blk c;
        }
        if (script_abs != null) break :blk if (builtin.os.tag == .windows) "sh" else "sh";
        return error.NoTool;
    };

    try argv_owned.append(allocator, try allocator.dupe(u8, command));
    if (script_abs) |path| {
        try argv_owned.append(allocator, try allocator.dupe(u8, path));
    }
    for (plugin.tool.args) |arg| {
        try argv_owned.append(allocator, try expand(allocator, arg, ctx));
    }

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    for (argv_owned.items) |s| try argv.append(allocator, s);

    const stdin_data = stdinFor(&plugin.tool, ctx);
    const cwd = if (ctx.cwd.len > 0) ctx.cwd else plugin.dir;
    const timeout: std.Io.Timeout = .{
        .duration = .{
            .raw = .fromMilliseconds(@intCast(@max(@as(u32, 1), plugin.tool.timeout_ms))),
            .clock = .awake,
        },
    };

    if (stdin_data.len == 0) {
        const spawned = std.process.run(allocator, io, .{
            .argv = argv.items,
            .cwd = .{ .path = cwd },
            .stdout_limit = .limited(max_stdout),
            .stderr_limit = .limited(max_stderr),
            .timeout = timeout,
        }) catch |err| switch (err) {
            error.Timeout => return error.Timeout,
            error.FileNotFound => return error.CommandNotFound,
            else => return error.SpawnFailed,
        };
        const code: u8 = switch (spawned.term) {
            .exited => |c| c,
            else => 1,
        };
        return .{
            .allocator = allocator,
            .stdout = spawned.stdout,
            .stderr = spawned.stderr,
            .code = code,
        };
    }

    return runWithStdin(allocator, io, argv.items, cwd, stdin_data, timeout);
}

fn runWithStdin(
    allocator: std.mem.Allocator,
    io: std.Io,
    argv: []const []const u8,
    cwd: []const u8,
    stdin_data: []const u8,
    timeout: std.Io.Timeout,
) !Result {
    var child = std.process.spawn(io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
        .create_no_window = true,
    }) catch |err| switch (err) {
        error.FileNotFound => return error.CommandNotFound,
        else => return error.SpawnFailed,
    };
    defer child.kill(io);

    if (child.stdin) |sin| {
        sin.writeStreamingAll(io, stdin_data) catch {};
        sin.close(io);
        child.stdin = null;
    }

    var multi_reader_buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
    var multi_reader: std.Io.File.MultiReader = undefined;
    multi_reader.init(allocator, io, multi_reader_buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer multi_reader.deinit();

    const stdout_reader = multi_reader.reader(0);
    const stderr_reader = multi_reader.reader(1);

    while (multi_reader.fill(64, timeout)) |_| {
        if (stdout_reader.buffered().len > max_stdout) return error.StreamTooLong;
        if (stderr_reader.buffered().len > max_stderr) return error.StreamTooLong;
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.Timeout => return error.Timeout,
        else => return error.SpawnFailed,
    }

    multi_reader.checkAnyError() catch return error.SpawnFailed;
    const term = child.wait(io) catch return error.SpawnFailed;
    const stdout = multi_reader.toOwnedSlice(0) catch return error.SpawnFailed;
    errdefer allocator.free(stdout);
    const stderr = multi_reader.toOwnedSlice(1) catch return error.SpawnFailed;

    return .{
        .allocator = allocator,
        .stdout = stdout,
        .stderr = stderr,
        .code = switch (term) {
            .exited => |c| c,
            else => 1,
        },
    };
}

fn resolveScript(allocator: std.mem.Allocator, plugin: *const types.Plugin) !?[]u8 {
    const script = plugin.tool.script orelse return null;
    if (script.len == 0) return null;
    if (std.mem.indexOf(u8, script, "..") != null) return error.UnsafeScriptPath;

    if (std.fs.path.isAbsolute(script)) {
        if (!std.mem.startsWith(u8, script, plugin.dir)) return error.UnsafeScriptPath;
        return try allocator.dupe(u8, script);
    }

    const joined = try std.fs.path.join(allocator, &.{ plugin.dir, script });
    errdefer allocator.free(joined);
    if (std.mem.indexOf(u8, joined, "..") != null) return error.UnsafeScriptPath;
    if (!std.mem.startsWith(u8, joined, plugin.dir)) return error.UnsafeScriptPath;
    return joined;
}

fn matchToken(hay: []const u8, at: usize, token: []const u8) ?usize {
    if (at + token.len > hay.len) return null;
    if (!std.mem.eql(u8, hay[at .. at + token.len], token)) return null;
    return token.len;
}
