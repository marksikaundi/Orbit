//! Security scan findings — severity, location, and message.

const std = @import("std");

pub const Severity = enum {
    info,
    warning,
    high,
    critical,

    pub fn label(self: Severity) []const u8 {
        return switch (self) {
            .info => "INFO",
            .warning => "WARNING",
            .high => "HIGH",
            .critical => "CRITICAL",
        };
    }

    pub fn rank(self: Severity) u8 {
        return switch (self) {
            .info => 0,
            .warning => 1,
            .high => 2,
            .critical => 3,
        };
    }

    pub fn parse(s: []const u8) ?Severity {
        if (std.ascii.eqlIgnoreCase(s, "info")) return .info;
        if (std.ascii.eqlIgnoreCase(s, "warning") or std.ascii.eqlIgnoreCase(s, "warn")) return .warning;
        if (std.ascii.eqlIgnoreCase(s, "high")) return .high;
        if (std.ascii.eqlIgnoreCase(s, "critical") or std.ascii.eqlIgnoreCase(s, "crit")) return .critical;
        return null;
    }
};

pub const Finding = struct {
    severity: Severity,
    rule_id: []const u8,
    path: []const u8,
    line: u32,
    message: []const u8,
    /// Optional snippet (borrowed; valid while the scanned buffer lives).
    snippet: []const u8 = "",
};
