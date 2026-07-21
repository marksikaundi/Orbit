const std = @import("std");
const App = @import("app/app.zig").App;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const app = try App.create(gpa, init.io);
    defer app.destroy();

    std.log.info("Orbit — Phase 5: command palette (Ctrl+Shift+P)", .{});
    try app.run();
}

test {
    _ = @import("terminal/cell.zig");
    _ = @import("terminal/screen.zig");
    _ = @import("terminal/parser.zig");
    _ = @import("terminal/selection.zig");
    _ = @import("config/config.zig");
    _ = @import("workspace/workspace.zig");
    _ = @import("ui/palette.zig");
}
