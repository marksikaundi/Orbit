//! Cloud sync — git remote for ~/.config/orbit (config, workspaces, ssh hosts).
//!
//! Secrets (logs, session tokens) stay local. Set `[sync] remote = "git@…"` then:
//!   orbit sync          # pull --rebase then push
//!   orbit sync pull
//!   orbit sync push
//!   orbit sync status

const std = @import("std");
const paths = @import("../platform/paths.zig");

pub const Mode = enum { status, pull, push, sync };

pub fn run(allocator: std.mem.Allocator, io: std.Io, mode: Mode, remote: ?[]const u8) !void {
    const root = paths.configDir(allocator) catch {
        fail("could not resolve ~/.config/orbit", .{});
        std.process.exit(1);
    };
    defer allocator.free(root);
    paths.ensureDir(root);
    writeIgnore(io, root);

    if (!gitRepo(io, root)) {
        const r = remote orelse {
            fail("no [sync] remote in config.toml. Add:\n  [sync]\n  remote = \"git@github.com:you/orbit-dotfiles.git\"", .{});
            std.process.exit(1);
        };
        git(io, root, &.{ "init", "-b", "main" }) catch {
            fail("git init failed", .{});
            std.process.exit(1);
        };
        git(io, root, &.{ "remote", "add", "origin", r }) catch {
            fail("git remote add failed", .{});
            std.process.exit(1);
        };
        std.debug.print("Initialized Orbit sync at {s}\n", .{root});
    } else if (remote) |r| {
        _ = git(io, root, &.{ "remote", "set-url", "origin", r }) catch {};
    }

    switch (mode) {
        .status => {
            _ = git(io, root, &.{ "status", "-sb" }) catch {};
        },
        .pull => {
            std.debug.print("Pulling Orbit config…\n", .{});
            git(io, root, &.{ "pull", "--rebase", "--autostash", "origin", "HEAD" }) catch {
                fail("git pull failed", .{});
                std.process.exit(1);
            };
        },
        .push => {
            try commitIfNeeded(allocator, io, root);
            std.debug.print("Pushing Orbit config…\n", .{});
            git(io, root, &.{ "push", "-u", "origin", "HEAD" }) catch {
                fail("git push failed — set [sync] remote and create the empty repo first", .{});
                std.process.exit(1);
            };
        },
        .sync => {
            _ = git(io, root, &.{ "pull", "--rebase", "--autostash", "origin", "HEAD" }) catch {};
            try commitIfNeeded(allocator, io, root);
            git(io, root, &.{ "push", "-u", "origin", "HEAD" }) catch {
                fail("sync push failed", .{});
                std.process.exit(1);
            };
            std.debug.print("Orbit config synced.\n", .{});
        },
    }
}

fn commitIfNeeded(allocator: std.mem.Allocator, io: std.Io, root: []const u8) !void {
    _ = git(io, root, &.{ "add", "config.toml", "workspaces", "ssh.toml", "session.toml", ".gitignore" }) catch {};
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "git", "-C", root, "status", "--porcelain" },
        .stdout_limit = .limited(8 * 1024),
        .stderr_limit = .limited(1024),
    }) catch return;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (std.mem.trim(u8, result.stdout, " \t\r\n").len == 0) return;
    _ = git(io, root, &.{ "commit", "-m", "orbit sync" }) catch {};
}

fn gitRepo(io: std.Io, root: []const u8) bool {
    _ = io;
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const git_dir = std.fmt.bufPrint(&path_buf, "{s}{c}.git", .{ root, std.fs.path.sep }) catch return false;
    return paths.pathExists(git_dir);
}

fn git(io: std.Io, root: []const u8, args: []const []const u8) !void {
    var argv: [12][]const u8 = undefined;
    argv[0] = "git";
    argv[1] = "-C";
    argv[2] = root;
    if (args.len + 3 > argv.len) return error.TooManyArgs;
    for (args, 0..) |a, i| argv[i + 3] = a;
    var child = std.process.spawn(io, .{
        .argv = argv[0 .. args.len + 3],
        .stdin = .ignore,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch return error.SpawnFailed;
    const term = child.wait(io) catch return error.WaitFailed;
    switch (term) {
        .exited => |code| if (code != 0) return error.GitFailed,
        else => return error.GitFailed,
    }
}

fn writeIgnore(io: std.Io, root: []const u8) void {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}{c}.gitignore", .{ root, std.fs.path.sep }) catch return;
    const file = std.Io.Dir.createFileAbsolute(io, path, .{}) catch return;
    defer file.close(io);
    file.writeStreamingAll(io,
        \\# Orbit sync — keep secrets and caches local
        \\logs/
        \\*.log
        \\source_root
        \\plugins.enabled
        \\
    ) catch {};
}

fn fail(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("orbit sync: " ++ fmt ++ "\n", args);
}
