//! Verbose simple test runner — prints per-test status to the terminal.
//! Used by `zig build test` (mode: simple, no zig_test server protocol).

const std = @import("std");
const builtin = @import("builtin");

pub fn main() void {
    const test_fns = builtin.test_functions;
    var passed: usize = 0;
    var skipped: usize = 0;
    var failed: usize = 0;
    var leaks: usize = 0;

    std.debug.print("\nOrbit unit tests ({d})\n", .{test_fns.len});
    std.debug.print("────────────────────────────────────────\n", .{});

    for (test_fns, 0..) |t, i| {
        std.testing.allocator_instance = .{};
        defer {
            if (std.testing.allocator_instance.deinit() == .leak) {
                leaks += 1;
                std.debug.print("  ! memory leak\n", .{});
            }
        }

        const idx = i + 1;
        std.debug.print("[{d:>3}/{d}] {s} ... ", .{ idx, test_fns.len, t.name });

        if (t.func()) |_| {
            passed += 1;
            std.debug.print("ok\n", .{});
        } else |err| switch (err) {
            error.SkipZigTest => {
                skipped += 1;
                std.debug.print("skip\n", .{});
            },
            else => {
                failed += 1;
                std.debug.print("FAIL ({s})\n", .{@errorName(err)});
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpErrorReturnTrace(trace);
                }
            },
        }
    }

    std.debug.print("────────────────────────────────────────\n", .{});
    if (failed == 0 and leaks == 0) {
        std.debug.print("All {d} passed", .{passed});
        if (skipped > 0) std.debug.print(", {d} skipped", .{skipped});
        std.debug.print(".\n\n", .{});
    } else {
        std.debug.print("{d} passed, {d} skipped, {d} failed", .{ passed, skipped, failed });
        if (leaks > 0) std.debug.print(", {d} leaked", .{leaks});
        std.debug.print(".\n\n", .{});
        std.process.exit(1);
    }
}
