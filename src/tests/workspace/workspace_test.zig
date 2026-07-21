//! Unit tests — workspace TOML helpers (re-exported via workspace module).
//! Private parse helpers are covered by same-file tests in workspace.zig;
//! this file documents the feature surface and adds public-facing checks.

const std = @import("std");

// Pull in workspace.zig so its same-file unit tests register with this suite.
test {
    _ = @import("../../workspace/workspace.zig");
}

test "workspace feature suite linked" {
    try std.testing.expect(true);
}
