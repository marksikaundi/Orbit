//! Unit tests — JSONC settings upsert used by `orbit ide-setup`.

const std = @import("std");
const jsonc = @import("../../cli/jsonc.zig");

test "upsert into empty creates object" {
    const out = try jsonc.upsertString(std.testing.allocator, "", "terminal.external.osxExec", "Orbit.app");
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"terminal.external.osxExec\": \"Orbit.app\"") != null);
}

test "upsert replaces existing string" {
    const src =
        \\{
        \\    "terminal.external.osxExec": "Terminal.app",
        \\    "editor.fontSize": 14
        \\}
        \\
    ;
    const out = try jsonc.upsertString(std.testing.allocator, src, "terminal.external.osxExec", "Orbit.app");
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"terminal.external.osxExec\": \"Orbit.app\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Terminal.app") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "editor.fontSize") != null);
}

test "upsert inserts missing key and keeps comments" {
    const src =
        \\{
        \\    // keep me
        \\    "editor.tabSize": 4
        \\}
        \\
    ;
    const out = try jsonc.upsertString(std.testing.allocator, src, "terminal.explorerKind", "both");
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "// keep me") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"terminal.explorerKind\": \"both\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "editor.tabSize") != null);
}

test "upsertMany writes several keys" {
    const out = try jsonc.upsertMany(std.testing.allocator, "{}", &.{
        .{ .k = "terminal.external.osxExec", .v = "Orbit.app" },
        .{ .k = "terminal.external.linuxExec", .v = "orbit" },
        .{ .k = "terminal.explorerKind", .v = "both" },
    });
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "Orbit.app") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "linuxExec") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"both\"") != null);
}
