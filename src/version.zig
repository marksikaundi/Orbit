//! App version — single source of truth is `src/VERSION` (mirrored at repo-root `VERSION`).
//! Bump with `./scripts/bump-version.sh patch|minor|major`, then push to `2026-live`.

const std = @import("std");

const raw = @embedFile("VERSION");

/// Semver string, e.g. `"0.1.0"`.
pub const string: []const u8 = std.mem.trim(u8, raw, " \t\r\n");

/// Display form with leading `v`, e.g. `"v0.1.0"`.
pub const tagged: []const u8 = "v" ++ string;
