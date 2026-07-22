//! Static pattern rules for source, scripts, and config files.

const std = @import("std");
const finding = @import("finding.zig");

pub const Rule = struct {
    id: []const u8,
    severity: finding.Severity,
    /// Case-sensitive substring / token to search for (unless ignore_case).
    pattern: []const u8,
    message: []const u8,
    ignore_case: bool = false,
    /// Only apply to these extensions (empty = all scanned types).
    extensions: []const []const u8 = &.{},
};

/// Core vulnerability / injection heuristics for Orbit.
pub const source_rules = [_]Rule{
    .{
        .id = "secret.private-key",
        .severity = .critical,
        .pattern = "BEGIN RSA PRIVATE KEY",
        .message = "Embedded RSA private key material",
    },
    .{
        .id = "secret.private-key",
        .severity = .critical,
        .pattern = "BEGIN OPENSSH PRIVATE KEY",
        .message = "Embedded OpenSSH private key material",
    },
    .{
        .id = "secret.private-key",
        .severity = .critical,
        .pattern = "BEGIN EC PRIVATE KEY",
        .message = "Embedded EC private key material",
    },
    .{
        .id = "secret.aws-access-key",
        .severity = .critical,
        .pattern = "AKIA",
        .message = "Possible AWS access key id (AKIA…)",
    },
    .{
        .id = "secret.github-token",
        .severity = .critical,
        .pattern = "ghp_",
        .message = "Possible GitHub personal access token",
    },
    .{
        .id = "secret.github-token",
        .severity = .critical,
        .pattern = "github_pat_",
        .message = "Possible GitHub fine-grained token",
    },
    .{
        .id = "secret.stripe-live",
        .severity = .critical,
        .pattern = "sk_live_",
        .message = "Possible Stripe live secret key",
    },
    .{
        .id = "secret.generic-api-key",
        .severity = .high,
        .pattern = "api_key = \"",
        .message = "Hardcoded api_key assignment — prefer env / secrets",
        .ignore_case = true,
    },
    .{
        .id = "secret.generic-password",
        .severity = .high,
        .pattern = "password = \"",
        .message = "Hardcoded password assignment — prefer env / secrets",
        .ignore_case = true,
    },
    .{
        .id = "inject.shell-pipe",
        .severity = .critical,
        .pattern = "| sh",
        .message = "Pipe-to-shell pattern can execute remote / injected code",
        .ignore_case = true,
    },
    .{
        .id = "inject.shell-pipe",
        .severity = .critical,
        .pattern = "| bash",
        .message = "Pipe-to-shell pattern can execute remote / injected code",
        .ignore_case = true,
    },
    .{
        .id = "inject.shell-pipe",
        .severity = .critical,
        .pattern = "|zsh",
        .message = "Pipe-to-shell pattern can execute remote / injected code",
        .ignore_case = true,
    },
    .{
        .id = "inject.curl-pipe",
        .severity = .critical,
        .pattern = "curl ",
        .message = "curl usage — review for pipe-to-shell / silent remote execution",
        .ignore_case = true,
        .extensions = &.{ ".sh", ".toml", ".zig", ".m", ".c" },
    },
    .{
        .id = "inject.eval",
        .severity = .high,
        .pattern = "eval ",
        .message = "eval can execute attacker-controlled strings",
        .ignore_case = true,
        .extensions = &.{ ".sh", ".toml" },
    },
    .{
        .id = "inject.system-call",
        .severity = .high,
        .pattern = "system(",
        .message = "system() executes a shell command — validate all inputs",
        .extensions = &.{ ".c", ".m", ".h" },
    },
    .{
        .id = "inject.popen",
        .severity = .high,
        .pattern = "popen(",
        .message = "popen() runs a shell — validate all inputs",
        .extensions = &.{ ".c", ".m", ".h" },
    },
    .{
        .id = "danger.rm-rf-root",
        .severity = .critical,
        .pattern = "rm -rf /",
        .message = "Destructive recursive delete targeting /",
        .ignore_case = true,
    },
    .{
        .id = "danger.fork-bomb",
        .severity = .critical,
        .pattern = ":(){",
        .message = "Possible fork bomb payload",
    },
    .{
        .id = "danger.mkfs",
        .severity = .critical,
        .pattern = "mkfs.",
        .message = "Filesystem format command — destructive",
        .ignore_case = true,
    },
    .{
        .id = "danger.dd-device",
        .severity = .high,
        .pattern = "dd if=",
        .message = "dd raw device write — review carefully",
        .ignore_case = true,
    },
    .{
        .id = "danger.chmod-777-root",
        .severity = .high,
        .pattern = "chmod -R 777 /",
        .message = "World-writable permissions on /",
        .ignore_case = true,
    },
    .{
        .id = "inject.reverse-shell",
        .severity = .critical,
        .pattern = "nc -e",
        .message = "netcat -e reverse-shell pattern",
        .ignore_case = true,
    },
    .{
        .id = "inject.reverse-shell",
        .severity = .critical,
        .pattern = "/dev/tcp/",
        .message = "Bash /dev/tcp reverse-shell pattern",
        .ignore_case = true,
    },
};

pub fn ruleApplies(rule: Rule, path: []const u8) bool {
    if (rule.extensions.len == 0) return true;
    for (rule.extensions) |ext| {
        if (std.mem.endsWith(u8, path, ext)) return true;
    }
    return false;
}

pub fn lineMatches(rule: Rule, line: []const u8) bool {
    if (rule.ignore_case) {
        return indexOfIgnoreCase(line, rule.pattern) != null;
    }
    return std.mem.indexOf(u8, line, rule.pattern) != null;
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

/// Extra check: AWS keys need AKIA + 16 alnum (avoid false hits on comments saying "AKIA").
pub fn looksLikeAwsKey(line: []const u8) bool {
    const idx = std.mem.indexOf(u8, line, "AKIA") orelse return false;
    const rest = line[idx..];
    if (rest.len < 20) return false;
    const candidate = rest[0..20];
    for (candidate) |c| {
        if (!std.ascii.isAlphanumeric(c)) return false;
    }
    return true;
}
