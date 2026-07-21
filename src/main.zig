const std = @import("std");
const App = @import("app/app.zig").App;
const version = @import("version.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const app = try App.create(gpa, init.io);
    defer app.destroy();

    std.log.info("Orbit {s} — stay in the flow", .{version.tagged});
    try app.run();
}
