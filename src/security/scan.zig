//! Walk the repo and emit security findings for source, scripts, and plugins.

const std = @import("std");
const finding = @import("finding.zig");
const rules = @import("rules.zig");
const plugin_audit = @import("plugin_audit.zig");

const skip_dirs = [_][]const u8{
    ".git",
    ".zig-cache",
    "zig-out",
    "vendor",
    "node_modules",
    "target",
    "dist",
    "__pycache__",
};

const scan_exts = [_][]const u8{ ".zig", ".c", ".h", ".m", ".sh", ".toml" };

pub const ScanOptions = struct {
    /// Absolute repository root.
    root: []const u8,
    /// Minimum severity to keep (info = keep all).
    min_severity: finding.Severity = .info,
    /// Relative roots to walk (empty = default set).
    roots: []const []const u8 = &.{ "src", "scripts", "assets/plugins" },
};

pub const Report = struct {
    allocator: std.mem.Allocator,
    findings: std.ArrayList(finding.Finding) = .empty,
    files_scanned: usize = 0,

    pub fn deinit(self: *Report) void {
        for (self.findings.items) |f| {
            self.allocator.free(f.path);
            self.allocator.free(f.message);
            if (f.snippet.len > 0) self.allocator.free(f.snippet);
        }
        self.findings.deinit(self.allocator);
    }

    pub fn highestSeverity(self: *const Report) ?finding.Severity {
        var best: ?finding.Severity = null;
        for (self.findings.items) |f| {
            if (best == null or f.severity.rank() > best.?.rank()) best = f.severity;
        }
        return best;
    }

    pub fn countAtLeast(self: *const Report, sev: finding.Severity) usize {
        var n: usize = 0;
        for (self.findings.items) |f| {
            if (f.severity.rank() >= sev.rank()) n += 1;
        }
        return n;
    }
};

pub fn scanTree(allocator: std.mem.Allocator, io: std.Io, opts: ScanOptions) !Report {
    var report: Report = .{ .allocator = allocator };
    errdefer report.deinit();

    const default_roots = [_][]const u8{ "src", "scripts", "assets/plugins" };
    const walk_roots: []const []const u8 = if (opts.roots.len > 0) opts.roots else &default_roots;
    for (walk_roots) |rel| {
        try walkDir(allocator, io, opts.root, rel, opts.min_severity, &report, 0);
    }
    return report;
}

/// Scan an in-memory buffer (used by tests and single-file checks).
pub fn scanBuffer(
    allocator: std.mem.Allocator,
    path: []const u8,
    data: []const u8,
    min_severity: finding.Severity,
    report: *Report,
) !void {
    report.files_scanned += 1;
    try scanLines(allocator, path, data, min_severity, report);
    if (std.mem.endsWith(u8, path, ".toml")) {
        try scanPluginToml(allocator, path, data, min_severity, report);
    }
}

fn walkDir(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    rel: []const u8,
    min_severity: finding.Severity,
    report: *Report,
    depth: u32,
) !void {
    if (depth > 24) return;

    const abs = if (rel.len == 0)
        try allocator.dupe(u8, root)
    else
        try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, rel });
    defer allocator.free(abs);

    var dir = std.Io.Dir.openDirAbsolute(io, abs, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        const name = entry.name;
        if (name.len == 0 or std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;

        const child_rel = if (rel.len == 0)
            try allocator.dupe(u8, name)
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ rel, name });
        defer allocator.free(child_rel);

        switch (entry.kind) {
            .directory => {
                if (shouldSkipDir(name)) continue;
                try walkDir(allocator, io, root, child_rel, min_severity, report, depth + 1);
            },
            .file => {
                if (!shouldScanFile(name)) continue;
                try scanFile(allocator, io, root, child_rel, min_severity, report);
            },
            else => {},
        }
    }
}

fn scanFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    rel: []const u8,
    min_severity: finding.Severity,
    report: *Report,
) !void {
    const abs = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, rel });
    defer allocator.free(abs);

    const file = std.Io.Dir.openFileAbsolute(io, abs, .{}) catch return;
    defer file.close(io);
    var buf: [4096]u8 = undefined;
    var reader = file.reader(io, &buf);
    const data = reader.interface.allocRemaining(allocator, .limited(512 * 1024)) catch return;
    defer allocator.free(data);

    try scanBuffer(allocator, rel, data, min_severity, report);
}

fn scanLines(
    allocator: std.mem.Allocator,
    path: []const u8,
    data: []const u8,
    min_severity: finding.Severity,
    report: *Report,
) !void {
    var line_no: u32 = 1;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, " \t\r");
        defer line_no += 1;
        if (line.len == 0) continue;
        if (isCommentOnly(path, line)) continue;
        if (isSelfReferentialHit(path, line)) continue;

        for (rules.source_rules) |rule| {
            if (!rules.ruleApplies(rule, path)) continue;
            if (rule.severity.rank() < min_severity.rank()) continue;
            if (!rules.lineMatches(rule, line)) continue;
            if (std.mem.eql(u8, rule.id, "secret.aws-access-key") and !rules.looksLikeAwsKey(line)) continue;
            if (std.mem.eql(u8, rule.id, "inject.curl-pipe")) {
                if (!curlLooksDangerous(line, path)) continue;
            }

            try appendFinding(allocator, report, .{
                .severity = rule.severity,
                .rule_id = rule.id,
                .path = path,
                .line = line_no,
                .message = rule.message,
                .snippet = trimSnippet(line),
            });
        }
    }
}

/// Lightweight plugin.toml pass: audit `insert` payloads and hook inserts.
fn scanPluginToml(
    allocator: std.mem.Allocator,
    path: []const u8,
    data: []const u8,
    min_severity: finding.Severity,
    report: *Report,
) !void {
    var line_no: u32 = 1;
    var in_command = false;
    var in_hooks = false;
    var is_insert = false;
    var cmd_id: []const u8 = "";
    var cmd_id_line: u32 = 1;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        defer line_no += 1;
        if (line.len == 0 or line[0] == '#') continue;

        if (std.mem.eql(u8, line, "[[commands]]")) {
            in_command = true;
            in_hooks = false;
            is_insert = false;
            cmd_id = "";
            cmd_id_line = line_no;
            continue;
        }
        if (std.mem.eql(u8, line, "[hooks]")) {
            in_command = false;
            in_hooks = true;
            is_insert = false;
            continue;
        }
        if (line[0] == '[') {
            in_command = false;
            in_hooks = false;
            is_insert = false;
            continue;
        }

        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const val_raw = std.mem.trim(u8, line[eq + 1 ..], " \t");
        const val = unquoteView(val_raw);

        if (in_hooks) {
            if (!std.mem.startsWith(u8, val, "insert:")) continue;
            const payload = val["insert:".len..];
            try reportPayloadHits(allocator, path, line_no, key, payload, min_severity, report);
            continue;
        }

        if (!in_command) continue;

        if (std.mem.eql(u8, key, "id")) {
            cmd_id = val;
            cmd_id_line = line_no;
        } else if (std.mem.eql(u8, key, "action")) {
            is_insert = std.mem.eql(u8, val, "insert");
        } else if (std.mem.eql(u8, key, "payload") and is_insert) {
            const id_part = if (cmd_id.len > 0) cmd_id else "(unnamed)";
            const report_line = if (cmd_id.len > 0) cmd_id_line else line_no;
            try reportPayloadHits(allocator, path, report_line, id_part, val, min_severity, report);
        }
    }
}

fn reportPayloadHits(
    allocator: std.mem.Allocator,
    path: []const u8,
    line: u32,
    id_part: []const u8,
    payload: []const u8,
    min_severity: finding.Severity,
    report: *Report,
) !void {
    var hits: std.ArrayList(plugin_audit.PayloadHit) = .empty;
    defer hits.deinit(allocator);
    try plugin_audit.auditInsertPayloadAll(payload, &hits, allocator);
    for (hits.items) |hit| {
        if (hit.severity.rank() < min_severity.rank()) continue;
        const msg = try std.fmt.allocPrint(allocator, "command `{s}`: {s}", .{ id_part, hit.message });
        try appendFindingOwnedMessage(allocator, report, .{
            .severity = hit.severity,
            .rule_id = hit.rule_id,
            .path = path,
            .line = line,
            .message = msg,
            .snippet = trimSnippet(payload),
        });
    }
}

fn unquoteView(s: []const u8) []const u8 {
    if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') return s[1 .. s.len - 1];
    if (s.len >= 2 and s[0] == '\'' and s[s.len - 1] == '\'') return s[1 .. s.len - 1];
    return s;
}

fn appendFinding(allocator: std.mem.Allocator, report: *Report, f: finding.Finding) !void {
    const path = try allocator.dupe(u8, f.path);
    errdefer allocator.free(path);
    const message = try allocator.dupe(u8, f.message);
    errdefer allocator.free(message);
    try report.findings.append(allocator, .{
        .severity = f.severity,
        .rule_id = f.rule_id,
        .path = path,
        .line = f.line,
        .message = message,
        .snippet = "",
    });
    if (f.snippet.len > 0) {
        const snip = try allocator.dupe(u8, f.snippet);
        report.findings.items[report.findings.items.len - 1].snippet = snip;
    }
}

fn appendFindingOwnedMessage(allocator: std.mem.Allocator, report: *Report, f: finding.Finding) !void {
    const path = try allocator.dupe(u8, f.path);
    errdefer {
        allocator.free(path);
        allocator.free(f.message);
    }
    try report.findings.append(allocator, .{
        .severity = f.severity,
        .rule_id = f.rule_id,
        .path = path,
        .line = f.line,
        .message = f.message,
        .snippet = "",
    });
    if (f.snippet.len > 0) {
        const snip = try allocator.dupe(u8, f.snippet);
        report.findings.items[report.findings.items.len - 1].snippet = snip;
    }
}

fn isSelfReferentialHit(path: []const u8, line: []const u8) bool {
    // Rule tables and security unit fixtures intentionally contain the needles.
    if (std.mem.startsWith(u8, path, "src/tests/security/")) return true;
    if (std.mem.indexOf(u8, line, ".pattern =") != null) return true;
    if (std.mem.indexOf(u8, line, ".message =") != null) return true;
    if (std.mem.indexOf(u8, line, "looksLikeAwsKey(") != null) return true;
    if (std.mem.indexOf(u8, line, "auditInsertPayload(") != null) return true;
    return false;
}

fn curlLooksDangerous(line: []const u8, path: []const u8) bool {
    const lower_pipe = indexOfIgnoreCase(line, "|") != null and
        (indexOfIgnoreCase(line, "sh") != null or indexOfIgnoreCase(line, "bash") != null);
    if (lower_pipe) return true;
    return std.mem.endsWith(u8, path, ".sh") or std.mem.endsWith(u8, path, ".toml");
}

fn isCommentOnly(path: []const u8, line: []const u8) bool {
    const t = std.mem.trimStart(u8, line, " \t");
    if (std.mem.endsWith(u8, path, ".zig")) return t.len >= 2 and t[0] == '/' and t[1] == '/';
    if (std.mem.endsWith(u8, path, ".c") or std.mem.endsWith(u8, path, ".h") or std.mem.endsWith(u8, path, ".m")) {
        return (t.len >= 2 and t[0] == '/' and t[1] == '/') or (t.len >= 2 and t[0] == '/' and t[1] == '*');
    }
    if (std.mem.endsWith(u8, path, ".sh")) return t.len >= 1 and t[0] == '#';
    if (std.mem.endsWith(u8, path, ".toml")) return t.len >= 1 and t[0] == '#';
    return false;
}

fn shouldSkipDir(name: []const u8) bool {
    for (skip_dirs) |s| {
        if (std.mem.eql(u8, s, name)) return true;
    }
    if (name.len > 0 and name[0] == '.') return true;
    return false;
}

fn shouldScanFile(name: []const u8) bool {
    for (scan_exts) |ext| {
        if (std.mem.endsWith(u8, name, ext)) return true;
    }
    return false;
}

fn trimSnippet(line: []const u8) []const u8 {
    const t = std.mem.trim(u8, line, " \t\r");
    if (t.len <= 120) return t;
    return t[0..120];
}

fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (needle.len > haystack.len) return null;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i..][0..needle.len], needle)) return i;
    }
    return null;
}
