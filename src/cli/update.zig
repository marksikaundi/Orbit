//! `orbit update` — check GitHub Releases and rebuild the local source tree.
//!
//! Orbit is distributed as source. A new GitHub Release does nothing to existing
//! installs until someone pulls and rebuilds. This command does that from the
//! terminal: compare `VERSION` to the latest `vX.Y.Z` tag, fetch it, rebuild,
//! and refresh the global launcher.

const std = @import("std");
const builtin = @import("builtin");
const version = @import("../version.zig");
const paths = @import("../platform/paths.zig");
const dev_root = @import("../dev_root.zig");

pub const official_repo = "https://github.com/marksikaundi/Orbit.git";
pub const official_api = "https://api.github.com/repos/marksikaundi/Orbit/releases/latest";

pub const Options = struct {
    check_only: bool = false,
    force: bool = false,
    /// Hidden: finish a Windows rebuild from a copy of this binary.
    rebuild_only: bool = false,
    rebuild_root: ?[]const u8 = null,
};

pub const Relation = enum { behind, current, ahead };

pub const SemVer = struct {
    major: u32,
    minor: u32,
    patch: u32,

    pub fn order(a: SemVer, b: SemVer) std.math.Order {
        if (a.major != b.major) return std.math.order(a.major, b.major);
        if (a.minor != b.minor) return std.math.order(a.minor, b.minor);
        return std.math.order(a.patch, b.patch);
    }
};

pub const Status = struct {
    current: []const u8,
    latest: []u8,
    latest_tag: []u8,
    relation: Relation,

    pub fn deinit(self: *Status, allocator: std.mem.Allocator) void {
        allocator.free(self.latest);
        allocator.free(self.latest_tag);
        self.* = undefined;
    }
};

pub fn run(allocator: std.mem.Allocator, io: std.Io, opts: Options) !void {
    if (opts.rebuild_only) {
        const root = opts.rebuild_root orelse {
            fail("rebuild path missing", .{});
            std.process.exit(2);
        };
        sleepMs(500);
        try rebuildAndSetup(allocator, io, root);
        std.debug.print("Orbit rebuilt. Restart the app to use the new version.\n", .{});
        return;
    }

    const root_opt = resolveSourceRoot(allocator, io);
    defer if (root_opt) |r| allocator.free(r);
    const query_root = root_opt orelse ".";

    var status = queryLatest(allocator, io, query_root) catch |err| {
        switch (err) {
            error.Offline => fail("could not reach GitHub. Check the network and try again.", .{}),
            error.NoRelease => fail("no numbered release tags found on GitHub.", .{}),
            error.OutOfMemory => return err,
        }
        std.process.exit(1);
    };
    defer status.deinit(allocator);

    printStatus(&status);

    if (opts.check_only) {
        if (status.relation == .behind) {
            std.debug.print("Run: orbit update\n", .{});
        }
        return;
    }

    switch (status.relation) {
        .current => return,
        .ahead => {
            std.debug.print("Nothing to install — this build is newer than the latest release.\n", .{});
            return;
        },
        .behind => {},
    }

    if (tryInstallPrebuilt(allocator, io, status.latest, status.latest_tag, root_opt)) {
        std.debug.print("\nOrbit updated {s} → {s} (prebuilt). Restart Orbit to use it.\n", .{ version.tagged, status.latest_tag });
        return;
    }

    const root = root_opt orelse {
        fail("no prebuilt archive for this platform, and source tree is not configured.", .{});
        std.debug.print("Install from https://github.com/marksikaundi/Orbit/releases or clone and run zig build setup.\n", .{});
        std.process.exit(1);
    };

    if (!gitRepo(root)) {
        fail("this install is not a git clone, so it cannot self-update.", .{});
        std.debug.print("Re-install with:\n", .{});
        std.debug.print("  git clone {s}\n", .{official_repo});
        std.debug.print("  cd Orbit && git checkout {s}\n", .{status.latest_tag});
        std.debug.print("  zig build -Doptimize=ReleaseFast && zig build setup\n", .{});
        std.process.exit(1);
    }

    if (!opts.force and try workingTreeDirty(allocator, io, root)) {
        fail("source tree has local changes. Commit, stash, or re-run: orbit update --force", .{});
        std.process.exit(1);
    }

    std.debug.print("\nFetching {s}…\n", .{status.latest_tag});
    fetchTag(io, root, status.latest_tag, opts.force) catch |err| {
        fail("git fetch failed ({s}).", .{@errorName(err)});
        std.process.exit(1);
    };
    checkoutTag(io, root, status.latest_tag, opts.force) catch |err| {
        fail("git checkout {s} failed ({s}).", .{ status.latest_tag, @errorName(err) });
        std.process.exit(1);
    };

    if (builtin.os.tag == .windows and orbitGuiLikelyOpen()) {
        std.debug.print("\nSource is now {s}. Quit Orbit (it locks orbit.exe), then run:\n", .{status.latest_tag});
        std.debug.print("  orbit update\n", .{});
        return;
    }

    if (builtin.os.tag == .windows) {
        try relaunchRebuild(allocator, io, root);
        return;
    }

    std.debug.print("Building {s}…\n", .{status.latest_tag});
    try rebuildAndSetup(allocator, io, root);
    std.debug.print("\nOrbit updated {s} → {s}. Restart Orbit to use it.\n", .{ version.tagged, status.latest_tag });
}

pub fn queryLatest(allocator: std.mem.Allocator, io: std.Io, source_root: []const u8) !Status {
    const latest_tag = try discoverLatestTag(allocator, io, source_root);
    errdefer allocator.free(latest_tag);
    const latest = try stripVAlloc(allocator, latest_tag);
    errdefer allocator.free(latest);

    const cur = parseSemver(version.string) orelse return error.NoRelease;
    const nxt = parseSemver(latest) orelse return error.NoRelease;
    const relation: Relation = switch (cur.order(nxt)) {
        .lt => .behind,
        .eq => .current,
        .gt => .ahead,
    };
    return .{
        .current = version.string,
        .latest = latest,
        .latest_tag = latest_tag,
        .relation = relation,
    };
}

pub fn shortMessage(status: *const Status, buf: []u8) []const u8 {
    return switch (status.relation) {
        .behind => std.fmt.bufPrint(buf, "update available: {s} (you have v{s})", .{ status.latest_tag, status.current }) catch "update available",
        .current => std.fmt.bufPrint(buf, "up to date ({s})", .{status.latest_tag}) catch "up to date",
        .ahead => std.fmt.bufPrint(buf, "dev build v{s} (latest release {s})", .{ status.current, status.latest_tag }) catch "newer than latest release",
    };
}

/// Parse `X.Y.Z` or `vX.Y.Z`. Returns null for floating tags (`latest`) and junk.
pub fn parseSemver(raw: []const u8) ?SemVer {
    const s = stripV(std.mem.trim(u8, raw, " \t\r\n"));
    if (s.len == 0) return null;
    var parts = std.mem.splitScalar(u8, s, '.');
    const a = parts.next() orelse return null;
    const b = parts.next() orelse return null;
    const c = parts.next() orelse return null;
    if (parts.next() != null) return null;
    const major = std.fmt.parseInt(u32, a, 10) catch return null;
    const minor = std.fmt.parseInt(u32, b, 10) catch return null;
    const patch = std.fmt.parseInt(u32, c, 10) catch return null;
    return .{ .major = major, .minor = minor, .patch = patch };
}

/// Pick the highest `vX.Y.Z` (or `X.Y.Z`) from `git ls-remote --tags` output.
pub fn latestTagFromLsRemote(text: []const u8) ?[]const u8 {
    var best: ?SemVer = null;
    var best_slice: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0) continue;
        const tab = std.mem.lastIndexOfScalar(u8, line, '\t') orelse std.mem.lastIndexOfScalar(u8, line, ' ');
        const ref = if (tab) |i| std.mem.trim(u8, line[i + 1 ..], " \t") else line;
        const name = tagName(ref);
        if (isFloatingTag(name)) continue;
        const ver = parseSemver(name) orelse continue;
        if (best == null or ver.order(best.?) == .gt) {
            best = ver;
            best_slice = name;
        }
    }
    return best_slice;
}

/// Extract `"tag_name"` from a GitHub release JSON blob.
pub fn tagFromReleaseJson(text: []const u8) ?[]const u8 {
    const key = "\"tag_name\"";
    const start = std.mem.indexOf(u8, text, key) orelse return null;
    var i = start + key.len;
    while (i < text.len and (text[i] == ' ' or text[i] == '\t' or text[i] == ':')) i += 1;
    if (i >= text.len or text[i] != '"') return null;
    i += 1;
    const from = i;
    while (i < text.len and text[i] != '"') i += 1;
    if (i >= text.len or from == i) return null;
    const name = text[from..i];
    if (isFloatingTag(name)) return null;
    if (parseSemver(name) == null) return null;
    return name;
}

pub fn isFloatingTag(name: []const u8) bool {
    return std.mem.eql(u8, name, "latest") or
        std.mem.eql(u8, name, "2026-live-latest") or
        std.mem.startsWith(u8, name, "2026-live");
}

fn printStatus(status: *const Status) void {
    std.debug.print("Orbit {s}\n", .{version.tagged});
    switch (status.relation) {
        .behind => std.debug.print("Latest release: {s} — update available.\n", .{status.latest_tag}),
        .current => std.debug.print("Latest release: {s} — already up to date.\n", .{status.latest_tag}),
        .ahead => std.debug.print("Latest release: {s} — this build is ahead.\n", .{status.latest_tag}),
    }
}

fn discoverLatestTag(allocator: std.mem.Allocator, io: std.Io, source_root: []const u8) ![]u8 {
    if (gitRepo(source_root)) {
        if (lsRemoteTag(allocator, io, source_root, &.{ "git", "ls-remote", "--tags", "--refs", "origin" })) |t| return t;
        if (lsRemoteTag(allocator, io, source_root, &.{ "git", "ls-remote", "--tags", "--refs", official_repo })) |t| return t;
    } else {
        if (lsRemoteTag(allocator, io, source_root, &.{ "git", "ls-remote", "--tags", "--refs", official_repo })) |t| return t;
    }
    if (latestFromGithubApi(allocator, io)) |t| return t;
    return error.Offline;
}

fn lsRemoteTag(allocator: std.mem.Allocator, io: std.Io, cwd: []const u8, argv: []const []const u8) ?[]u8 {
    const result = std.process.run(allocator, io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
        .stdout_limit = .limited(256 * 1024),
        .stderr_limit = .limited(16 * 1024),
        .timeout = timeoutMs(20_000),
    }) catch return null;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (!exitedZero(result.term)) return null;
    const name = latestTagFromLsRemote(result.stdout) orelse return null;
    return allocator.dupe(u8, name) catch null;
}

fn latestFromGithubApi(allocator: std.mem.Allocator, io: std.Io) ?[]u8 {
    const curl_name: []const u8 = if (builtin.os.tag == .windows) "curl.exe" else "curl";
    const result = std.process.run(allocator, io, .{
        .argv = &.{
            curl_name,
            "-fsSL",
            "--max-time",
            "20",
            "-H",
            "Accept: application/vnd.github+json",
            "-H",
            "User-Agent: Orbit-Updater",
            official_api,
        },
        .stdout_limit = .limited(256 * 1024),
        .stderr_limit = .limited(16 * 1024),
        .timeout = timeoutMs(25_000),
    }) catch return null;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (!exitedZero(result.term)) return null;
    const name = tagFromReleaseJson(result.stdout) orelse return null;
    return allocator.dupe(u8, name) catch null;
}

fn fetchTag(io: std.Io, root: []const u8, tag: []const u8, force: bool) !void {
    var argv_buf: [8][]const u8 = undefined;
    var n: usize = 0;
    argv_buf[n] = "git";
    n += 1;
    argv_buf[n] = "fetch";
    n += 1;
    if (force) {
        argv_buf[n] = "--force";
        n += 1;
    }
    argv_buf[n] = official_repo;
    n += 1;
    argv_buf[n] = "tag";
    n += 1;
    argv_buf[n] = tag;
    n += 1;
    try runInherit(io, argv_buf[0..n], root);
}

fn checkoutTag(io: std.Io, root: []const u8, tag: []const u8, force: bool) !void {
    if (force) {
        try runInherit(io, &.{ "git", "checkout", "--force", tag }, root);
    } else {
        try runInherit(io, &.{ "git", "checkout", tag }, root);
    }
}

fn rebuildAndSetup(_: std.mem.Allocator, io: std.Io, root: []const u8) !void {
    const zig_name: []const u8 = if (builtin.os.tag == .windows) "zig.exe" else "zig";
    runInherit(io, &.{ zig_name, "build", "-Doptimize=ReleaseFast" }, root) catch |err| {
        fail("zig build failed ({s}). Is Zig 0.16+ on PATH?", .{@errorName(err)});
        return err;
    };
    runInherit(io, &.{ zig_name, "build", "setup" }, root) catch |err| {
        fail("zig build setup failed ({s}). The binary may still be in zig-out.", .{@errorName(err)});
        return err;
    };
}

fn relaunchRebuild(allocator: std.mem.Allocator, io: std.Io, root: []const u8) !void {
    var exe_buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = std.process.executablePath(io, &exe_buf) catch {
        std.debug.print("Building…\n", .{});
        try rebuildAndSetup(allocator, io, root);
        return;
    };
    const exe = exe_buf[0..n];
    const tmp = try tmpUpdateExe(allocator);
    defer allocator.free(tmp);
    copyFile(allocator, io, exe, tmp) catch {
        std.debug.print("Building…\n", .{});
        try rebuildAndSetup(allocator, io, root);
        return;
    };

    std.debug.print("Rebuilding from a helper so Windows can replace orbit.exe…\n", .{});
    var child = std.process.spawn(io, .{
        .argv = &.{ tmp, "--orbit-rebuild", root },
        .cwd = .{ .path = root },
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
        .create_no_window = false,
    }) catch {
        try rebuildAndSetup(allocator, io, root);
        return;
    };
    _ = &child;
    std.process.exit(0);
}

fn tmpUpdateExe(allocator: std.mem.Allocator) ![]u8 {
    if (std.c.getenv("TEMP")) |t| {
        const span = std.mem.span(t);
        if (span.len > 0) return try std.fmt.allocPrint(allocator, "{s}\\orbit-selfupdate.exe", .{span});
    }
    if (std.c.getenv("TMP")) |t| {
        const span = std.mem.span(t);
        if (span.len > 0) return try std.fmt.allocPrint(allocator, "{s}\\orbit-selfupdate.exe", .{span});
    }
    return try allocator.dupe(u8, "orbit-selfupdate.exe");
}

fn copyFile(allocator: std.mem.Allocator, io: std.Io, src: []const u8, dst: []const u8) !void {
    const in = try std.Io.Dir.openFileAbsolute(io, src, .{});
    defer in.close(io);
    var buf: [4096]u8 = undefined;
    var reader = in.reader(io, &buf);
    const data = try reader.interface.allocRemaining(allocator, .limited(128 * 1024 * 1024));
    defer allocator.free(data);
    const out = try std.Io.Dir.createFileAbsolute(io, dst, .{});
    defer out.close(io);
    try out.writeStreamingAll(io, data);
}

fn workingTreeDirty(allocator: std.mem.Allocator, io: std.Io, root: []const u8) !bool {
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "git", "status", "--porcelain" },
        .cwd = .{ .path = root },
        .stdout_limit = .limited(64 * 1024),
        .stderr_limit = .limited(4096),
        .timeout = timeoutMs(15_000),
    }) catch return error.Offline;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (!exitedZero(result.term)) return error.Offline;
    return std.mem.trim(u8, result.stdout, " \t\r\n").len > 0;
}

fn runInherit(io: std.Io, argv: []const []const u8, cwd: []const u8) !void {
    var child = std.process.spawn(io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
        .create_no_window = false,
    }) catch |err| switch (err) {
        error.FileNotFound => {
            fail("command not found: {s}", .{argv[0]});
            return err;
        },
        else => return err,
    };
    const term = try child.wait(io);
    if (!exitedZero(term)) return error.CommandFailed;
}

fn resolveSourceRoot(allocator: std.mem.Allocator, io: std.Io) ?[]u8 {
    if (dev_root.resolve(allocator, io)) |p| return p;
    if (std.c.getenv("ORBIT_SOURCE_ROOT")) |raw| {
        const span = std.mem.span(raw);
        if (span.len > 0 and buildZigExists(span)) {
            return allocator.dupe(u8, span) catch null;
        }
    }
    return null;
}

fn gitRepo(root: []const u8) bool {
    return pathJoinExists(root, ".git");
}

fn buildZigExists(dir: []const u8) bool {
    return pathJoinExists(dir, "build.zig");
}

fn pathJoinExists(dir: []const u8, name: []const u8) bool {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const p = std.fmt.bufPrint(&buf, "{s}{c}{s}", .{ dir, std.fs.path.sep, name }) catch return false;
    return paths.pathExists(p);
}

fn orbitGuiLikelyOpen() bool {
    if (std.c.getenv("ORBIT_TERMINAL")) |v| {
        return v[0] != 0;
    }
    return false;
}

fn tagName(ref: []const u8) []const u8 {
    const prefix = "refs/tags/";
    if (std.mem.startsWith(u8, ref, prefix)) return ref[prefix.len..];
    return ref;
}

fn stripV(s: []const u8) []const u8 {
    if (s.len > 0 and (s[0] == 'v' or s[0] == 'V')) return s[1..];
    return s;
}

fn stripVAlloc(allocator: std.mem.Allocator, tag: []const u8) ![]u8 {
    return try allocator.dupe(u8, stripV(tag));
}

fn exitedZero(term: std.process.Child.Term) bool {
    return switch (term) {
        .exited => |c| c == 0,
        else => false,
    };
}

fn timeoutMs(ms: i64) std.Io.Timeout {
    return .{
        .duration = .{
            .raw = .fromMilliseconds(ms),
            .clock = .awake,
        },
    };
}

fn sleepMs(ms: u64) void {
    if (builtin.os.tag == .windows) {
        const Sleep = struct {
            extern "kernel32" fn Sleep(dwMilliseconds: u32) callconv(.winapi) void;
        };
        Sleep.Sleep(@intCast(ms));
        return;
    }
    const c = @import("../c.zig").c;
    var req = c.struct_timespec{
        .tv_sec = @intCast(ms / 1000),
        .tv_nsec = @intCast((ms % 1000) * std.time.ns_per_ms),
    };
    _ = c.nanosleep(&req, null);
}

fn fail(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("orbit update: " ++ fmt ++ "\n", args);
}

fn tryInstallPrebuilt(
    allocator: std.mem.Allocator,
    io: std.Io,
    ver: []const u8,
    tag: []const u8,
    source_root: ?[]const u8,
) bool {
    var name_buf: [96]u8 = undefined;
    const asset = prebuiltAssetName(ver, &name_buf) orelse return false;
    var url_buf: [256]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buf, "https://github.com/marksikaundi/Orbit/releases/download/{s}/{s}", .{ tag, asset }) catch return false;

    const dest_dir = source_root orelse {
        std.debug.print("Trying prebuilt {s}…\n", .{asset});
        return downloadAndUnpack(allocator, io, url, asset, null);
    };
    std.debug.print("Trying prebuilt {s}…\n", .{asset});
    return downloadAndUnpack(allocator, io, url, asset, dest_dir);
}

fn prebuiltAssetName(ver: []const u8, buf: []u8) ?[]const u8 {
    const os = switch (builtin.os.tag) {
        .macos => "macos",
        .linux => "linux",
        .windows => "windows",
        else => return null,
    };
    const arch = switch (builtin.cpu.arch) {
        .aarch64 => "aarch64",
        .x86_64 => "x86_64",
        else => return null,
    };
    const ext = if (builtin.os.tag == .linux) "tar.gz" else "zip";
    return std.fmt.bufPrint(buf, "orbit-{s}-{s}-{s}.{s}", .{ ver, os, arch, ext }) catch null;
}

fn downloadAndUnpack(
    allocator: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
    asset: []const u8,
    source_root: ?[]const u8,
) bool {
    const curl_name: []const u8 = if (builtin.os.tag == .windows) "curl.exe" else "curl";
    const tmp = paths.joinConfig(allocator, &.{ "tmp", asset }) catch return false;
    defer allocator.free(tmp);
    if (std.fs.path.dirname(tmp)) |dir| paths.ensureDir(dir);

    const curl = std.process.run(allocator, io, .{
        .argv = &.{ curl_name, "-fsSL", "--max-time", "120", "-o", tmp, url },
        .stdout_limit = .limited(1024),
        .stderr_limit = .limited(8 * 1024),
        .timeout = timeoutMs(130_000),
    }) catch return false;
    defer allocator.free(curl.stdout);
    defer allocator.free(curl.stderr);
    if (!exitedZero(curl.term)) return false;

    const dest = source_root orelse {
        const home = paths.homeDir() orelse return false;
        return unpackArchive(allocator, io, tmp, asset, home);
    };
    var out_buf: [std.fs.max_path_bytes]u8 = undefined;
    const zig_out = std.fmt.bufPrint(&out_buf, "{s}{c}zig-out", .{ dest, std.fs.path.sep }) catch return false;
    paths.ensureDir(zig_out);
    return unpackArchive(allocator, io, tmp, asset, zig_out);
}

fn unpackArchive(allocator: std.mem.Allocator, io: std.Io, archive: []const u8, asset: []const u8, dest: []const u8) bool {
    _ = allocator;
    if (std.mem.endsWith(u8, asset, ".tar.gz")) {
        var child = std.process.spawn(io, .{
            .argv = &.{ "tar", "-xzf", archive, "-C", dest },
            .stdin = .ignore,
            .stdout = .ignore,
            .stderr = .inherit,
        }) catch return false;
        const term = child.wait(io) catch return false;
        return switch (term) {
            .exited => |code| code == 0,
            else => false,
        };
    }
    var child = std.process.spawn(io, .{
        .argv = &.{ "unzip", "-o", "-q", archive, "-d", dest },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .inherit,
    }) catch return false;
    const term = child.wait(io) catch return false;
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

test "parseSemver accepts v-prefix and rejects junk" {
    const a = parseSemver("v2.1.0").?;
    try std.testing.expectEqual(@as(u32, 2), a.major);
    try std.testing.expectEqual(@as(u32, 1), a.minor);
    try std.testing.expectEqual(@as(u32, 0), a.patch);
    try std.testing.expect(parseSemver("2.1.2") != null);
    try std.testing.expect(parseSemver("latest") == null);
    try std.testing.expect(parseSemver("v2") == null);
    try std.testing.expect(parseSemver("1.2.3.4") == null);
}

test "semver order" {
    const older = parseSemver("2.1.0").?;
    const newer = parseSemver("2.1.2").?;
    try std.testing.expectEqual(std.math.Order.lt, older.order(newer));
    try std.testing.expectEqual(std.math.Order.gt, newer.order(older));
    try std.testing.expectEqual(std.math.Order.eq, newer.order(parseSemver("v2.1.2").?));
    try std.testing.expectEqual(std.math.Order.lt, parseSemver("2.9.9").?.order(parseSemver("3.0.0").?));
}

test "latestTagFromLsRemote skips floating tags" {
    const text =
        "abc\trefs/tags/v2.0.0\n" ++
        "def\trefs/tags/latest\n" ++
        "ghi\trefs/tags/2026-live-latest\n" ++
        "jkl\trefs/tags/v2.1.2\n" ++
        "mno\trefs/tags/v2.1.0\n";
    const tag = latestTagFromLsRemote(text).?;
    try std.testing.expectEqualStrings("v2.1.2", tag);
}

test "tagFromReleaseJson" {
    const json = "{\"url\":\"x\",\"tag_name\": \"v2.1.2\", \"name\":\"Orbit\"}";
    try std.testing.expectEqualStrings("v2.1.2", tagFromReleaseJson(json).?);
    try std.testing.expect(tagFromReleaseJson("{\"tag_name\":\"latest\"}") == null);
    try std.testing.expect(tagFromReleaseJson("{}") == null);
}
