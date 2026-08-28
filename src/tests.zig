//! Orbit unit test entry — feature suites under `src/tests/`.
//!
//! Run:  zig build test

const std = @import("std");

comptime {
    _ = @import("tests/terminal/cell_test.zig");
    _ = @import("tests/terminal/screen_test.zig");
    _ = @import("tests/terminal/parser_test.zig");
    _ = @import("tests/terminal/selection_test.zig");

    _ = @import("tests/config/config_test.zig");
    _ = @import("tests/config/theme_test.zig");
    _ = @import("config/look.zig");

    _ = @import("tests/ui/palette_test.zig");
    _ = @import("tests/ui/bindings_test.zig");
    _ = @import("tests/ui/home_test.zig");
    _ = @import("tests/ui/search_test.zig");
    _ = @import("tests/ui/viewer_test.zig");

    _ = @import("tests/syntax/highlight_test.zig");
    _ = @import("tests/syntax/complete_test.zig");

    _ = @import("tests/pty/pty_test.zig");

    _ = @import("tests/plugins/manifest_test.zig");
    _ = @import("tests/plugins/types_test.zig");

    _ = @import("tests/security/scan_test.zig");

    _ = @import("tests/font/bitmap_test.zig");
    _ = @import("tests/font/atlas_test.zig");

    _ = @import("tests/workspace/workspace_test.zig");

    _ = @import("tests/cli/args_test.zig");
    _ = @import("tests/cli/jsonc_test.zig");

    _ = @import("tests/version_test.zig");

    // Same-file unit tests
    _ = @import("cli/ide_setup.zig");
    _ = @import("workspace/workspace.zig");
    _ = @import("platform/folder_picker.zig");
    _ = @import("platform/shell.zig");
    _ = @import("platform/paths.zig");
    _ = @import("ui/home.zig");
    _ = @import("ui/scale.zig");
    _ = @import("ui/chrome.zig");
    _ = @import("font/faces.zig");
}

test "suite boots" {
    try std.testing.expect(true);
}
