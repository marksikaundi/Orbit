//! Audit plugin insert payloads for command-injection / destructive patterns.

const std = @import("std");
const finding = @import("finding.zig");

pub const PayloadHit = struct {
    severity: finding.Severity,
    rule_id: []const u8,
    message: []const u8,
};

const PayloadRule = struct {
    id: []const u8,
    severity: finding.Severity,
    pattern: []const u8,
    message: []const u8,
    ignore_case: bool = true,
};

const payload_rules = [_]PayloadRule{
    .{
        .id = "plugin.pipe-shell",
        .severity = .critical,
        .pattern = "| sh",
        .message = "Plugin insert payload pipes into a shell",
    },
    .{
        .id = "plugin.pipe-shell",
        .severity = .critical,
        .pattern = "| bash",
        .message = "Plugin insert payload pipes into bash",
    },
    .{
        .id = "plugin.pipe-shell",
        .severity = .critical,
        .pattern = "|zsh",
        .message = "Plugin insert payload pipes into zsh",
    },
    .{
        .id = "plugin.curl-remote",
        .severity = .high,
        .pattern = "curl ",
        .message = "Plugin insert runs curl — review for remote code execution",
    },
    .{
        .id = "plugin.wget-remote",
        .severity = .high,
        .pattern = "wget ",
        .message = "Plugin insert runs wget — review for remote code execution",
    },
    .{
        .id = "plugin.rm-rf",
        .severity = .critical,
        .pattern = "rm -rf /",
        .message = "Plugin insert payload is a destructive rm -rf /",
    },
    .{
        .id = "plugin.rm-rf-home",
        .severity = .critical,
        .pattern = "rm -rf ~",
        .message = "Plugin insert payload recursively deletes home",
    },
    .{
        .id = "plugin.fork-bomb",
        .severity = .critical,
        .pattern = ":(){",
        .message = "Plugin insert payload looks like a fork bomb",
        .ignore_case = false,
    },
    .{
        .id = "plugin.mkfs",
        .severity = .critical,
        .pattern = "mkfs.",
        .message = "Plugin insert payload formats a filesystem",
    },
    .{
        .id = "plugin.dd",
        .severity = .high,
        .pattern = "dd if=",
        .message = "Plugin insert payload uses dd (raw device I/O)",
    },
    .{
        .id = "plugin.eval",
        .severity = .high,
        .pattern = "eval ",
        .message = "Plugin insert payload uses eval",
    },
    .{
        .id = "plugin.reverse-shell",
        .severity = .critical,
        .pattern = "nc -e",
        .message = "Plugin insert payload looks like a reverse shell",
    },
    .{
        .id = "plugin.reverse-shell",
        .severity = .critical,
        .pattern = "/dev/tcp/",
        .message = "Plugin insert payload uses /dev/tcp (possible reverse shell)",
    },
    .{
        .id = "plugin.chmod-777",
        .severity = .warning,
        .pattern = "chmod -R 777",
        .message = "Plugin insert payload sets world-writable permissions",
    },
    .{
        .id = "plugin.sudo",
        .severity = .warning,
        .pattern = "sudo ",
        .message = "Plugin insert payload escalates with sudo",
    },
};

/// Scan a single plugin `insert` payload. Returns the highest-severity hit, if any.
pub fn auditInsertPayload(payload: []const u8) ?PayloadHit {
    var best: ?PayloadHit = null;
    for (payload_rules) |rule| {
        const matched = if (rule.ignore_case)
            indexOfIgnoreCase(payload, rule.pattern) != null
        else
            std.mem.indexOf(u8, payload, rule.pattern) != null;
        if (!matched) continue;
        const hit = PayloadHit{
            .severity = rule.severity,
            .rule_id = rule.id,
            .message = rule.message,
        };
        if (best == null or hit.severity.rank() > best.?.severity.rank()) {
            best = hit;
        }
    }
    return best;
}

/// Collect every matching hit (for static scans that want full reporting).
pub fn auditInsertPayloadAll(payload: []const u8, out: *std.ArrayList(PayloadHit), allocator: std.mem.Allocator) !void {
    for (payload_rules) |rule| {
        const matched = if (rule.ignore_case)
            indexOfIgnoreCase(payload, rule.pattern) != null
        else
            std.mem.indexOf(u8, payload, rule.pattern) != null;
        if (!matched) continue;
        try out.append(allocator, .{
            .severity = rule.severity,
            .rule_id = rule.id,
            .message = rule.message,
        });
    }
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
