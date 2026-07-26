//! Curated monospace faces users can pick in Appearance.
//! Paths are platform-specific; missing files are skipped when cycling.

const std = @import("std");
const builtin = @import("builtin");
const paths = @import("../platform/paths.zig");

pub const Face = struct {
    id: []const u8,
    label: []const u8,
    path: [:0]const u8,
};

pub const catalog = if (builtin.os.tag == .windows) [_]Face{
    .{ .id = "consolas", .label = "Consolas", .path = "C:\\Windows\\Fonts\\consola.ttf" },
    .{ .id = "cascadia", .label = "Cascadia Mono", .path = "C:\\Windows\\Fonts\\CascadiaMono.ttf" },
    .{ .id = "cascadia-alt", .label = "Cascadia Mono", .path = "C:\\Windows\\Fonts\\cascadiamono.ttf" },
    .{ .id = "lucida", .label = "Lucida Console", .path = "C:\\Windows\\Fonts\\lucon.ttf" },
    .{ .id = "courier", .label = "Courier New", .path = "C:\\Windows\\Fonts\\cour.ttf" },
} else if (builtin.os.tag == .linux) [_]Face{
    .{ .id = "dejavu", .label = "DejaVu Sans Mono", .path = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf" },
    .{ .id = "dejavu-ttf", .label = "DejaVu Sans Mono", .path = "/usr/share/fonts/TTF/DejaVuSansMono.ttf" },
    .{ .id = "liberation", .label = "Liberation Mono", .path = "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf" },
    .{ .id = "ubuntu", .label = "Ubuntu Mono", .path = "/usr/share/fonts/truetype/ubuntu/UbuntuMono-R.ttf" },
    .{ .id = "jetbrains", .label = "JetBrains Mono", .path = "/usr/local/share/fonts/JetBrainsMono-Regular.ttf" },
    .{ .id = "jetbrains-share", .label = "JetBrains Mono", .path = "/usr/share/fonts/truetype/jetbrains/JetBrainsMono-Regular.ttf" },
} else [_]Face{
    .{ .id = "sf-mono", .label = "SF Mono", .path = "/System/Library/Fonts/SFNSMono.ttf" },
    .{ .id = "menlo", .label = "Menlo", .path = "/System/Library/Fonts/Menlo.ttc" },
    .{ .id = "andale", .label = "Andale Mono", .path = "/System/Library/Fonts/Supplemental/Andale Mono.ttf" },
    .{ .id = "jetbrains", .label = "JetBrains Mono", .path = "/Library/Fonts/JetBrainsMono-Regular.ttf" },
};

pub fn byId(id: []const u8) ?Face {
    for (catalog) |f| {
        if (std.mem.eql(u8, f.id, id)) return f;
    }
    return null;
}

pub fn labelForId(id: []const u8) []const u8 {
    if (byId(id)) |f| return f.label;
    return "System Mono";
}

pub fn pathForId(id: []const u8) ?[:0]const u8 {
    if (byId(id)) |f| {
        if (paths.pathExists(f.path)) return f.path;
    }
    return null;
}

/// First installed face (for defaults / fallback).
pub fn defaultId() []const u8 {
    for (catalog) |f| {
        if (paths.pathExists(f.path)) return f.id;
    }
    return catalog[0].id;
}

pub fn nextInstalledId(current: []const u8, delta: i32) []const u8 {
    var installed: [catalog.len]usize = undefined;
    var n: usize = 0;
    for (catalog, 0..) |f, i| {
        if (!paths.pathExists(f.path)) continue;
        // Prefer unique labels when cycling (skip duplicate path variants).
        var dup = false;
        for (installed[0..n]) |prev| {
            if (std.mem.eql(u8, catalog[prev].label, f.label)) {
                dup = true;
                break;
            }
        }
        if (dup) continue;
        installed[n] = i;
        n += 1;
    }
    if (n == 0) return defaultId();

    var idx: i32 = 0;
    for (installed[0..n], 0..) |ci, i| {
        if (std.mem.eql(u8, catalog[ci].id, current)) {
            idx = @intCast(i);
            break;
        }
    }
    const count: i32 = @intCast(n);
    idx = @mod(idx + delta, count);
    if (idx < 0) idx += count;
    return catalog[installed[@intCast(idx)]].id;
}
