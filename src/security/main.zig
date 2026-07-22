//! Orbit security scanner CLI — static checks for secrets and injection vectors.
//!
//! Run:  zig build security-scan
//!
//! Exit code 1 when any finding is at or above `--fail-on` (default: high).

const std = @import("std");
const build_options = @import("build_options");
const finding = @import("finding.zig");
const scan = @import("scan.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var fail_on: finding.Severity = .high;
    var root: []const u8 = build_options.source_root;
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args.deinit();
    _ = args.next(); // argv0
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--fail-on")) {
            const v = args.next() orelse {
                std.debug.print("error: --fail-on requires info|warning|high|critical\n", .{});
                std.process.exit(2);
            };
            fail_on = finding.Severity.parse(v) orelse {
                std.debug.print("error: unknown severity `{s}`\n", .{v});
                std.process.exit(2);
            };
        } else if (std.mem.eql(u8, arg, "--root")) {
            root = args.next() orelse {
                std.debug.print("error: --root requires a path\n", .{});
                std.process.exit(2);
            };
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            return;
        } else {
            std.debug.print("error: unknown argument `{s}` (try --help)\n", .{arg});
            std.process.exit(2);
        }
    }

    std.debug.print("Orbit security scan\n", .{});
    std.debug.print("  root:     {s}\n", .{root});
    std.debug.print("  fail-on:  {s}\n", .{fail_on.label()});
    std.debug.print("────────────────────────────────────────\n", .{});

    var report = try scan.scanTree(gpa, io, .{
        .root = root,
        .min_severity = .info,
    });
    defer report.deinit();

    if (report.findings.items.len == 0) {
        std.debug.print("No findings in {d} file(s).\n\n", .{report.files_scanned});
        return;
    }

    // Sort: critical first, then path.
    std.mem.sort(finding.Finding, report.findings.items, {}, struct {
        fn less(_: void, a: finding.Finding, b: finding.Finding) bool {
            if (a.severity.rank() != b.severity.rank()) return a.severity.rank() > b.severity.rank();
            const pc = std.mem.order(u8, a.path, b.path);
            if (pc != .eq) return pc == .lt;
            return a.line < b.line;
        }
    }.less);

    for (report.findings.items) |f| {
        std.debug.print("[{s}] {s}:{d}: {s} ({s})\n", .{
            f.severity.label(),
            f.path,
            f.line,
            f.message,
            f.rule_id,
        });
        if (f.snippet.len > 0) {
            std.debug.print("         | {s}\n", .{f.snippet});
        }
    }

    const blocking = report.countAtLeast(fail_on);
    const warnings = report.findings.items.len - blocking;
    std.debug.print("────────────────────────────────────────\n", .{});
    std.debug.print(
        "Scanned {d} file(s): {d} finding(s) ({d} at/above {s}, {d} lower).\n\n",
        .{ report.files_scanned, report.findings.items.len, blocking, fail_on.label(), warnings },
    );

    if (blocking > 0) {
        std.debug.print("Security scan failed — fix HIGH/CRITICAL issues or lower --fail-on.\n", .{});
        std.process.exit(1);
    }

    if (report.findings.items.len > 0) {
        std.debug.print("Warnings only — review recommended, build not blocked.\n", .{});
    }
}

fn printHelp() void {
    std.debug.print(
        \\Orbit security scanner
        \\
        \\Usage: orbit-security-scan [options]
        \\
        \\Options:
        \\  --root PATH          Repository root to scan (default: build source root)
        \\  --fail-on LEVEL      Exit 1 if any finding >= LEVEL
        \\                       (info|warning|high|critical; default: high)
        \\  -h, --help           Show this help
        \\
        \\Scans src/, scripts/, and assets/plugins/ for secrets, shell injection
        \\patterns, and dangerous plugin insert payloads.
        \\
    , .{});
}
