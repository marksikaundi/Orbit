const std = @import("std");
const App = @import("app/app.zig").App;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const app = try App.create(gpa);
    defer app.destroy();

    std.log.info("Orbit Phase 1 — window, PTY, render, input", .{});
    try app.run();
}

test {
    _ = @import("terminal/screen.zig");
    _ = @import("terminal/parser.zig");
}
