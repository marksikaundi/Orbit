const std = @import("std");
const App = @import("app/app.zig").App;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const app = try App.create(gpa, init.io);
    defer app.destroy();

    std.log.info("Orbit — Phase 6: plugins (commands, themes, hooks)", .{});
    try app.run();
}
