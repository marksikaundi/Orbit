const std = @import("std");
const App = @import("app/app.zig").App;
const version = @import("version.zig");
const cli = @import("cli/args.zig");
const ide_setup = @import("cli/ide_setup.zig");
const updater = @import("cli/update.zig");
const macos_open = @import("platform/macos_open.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer it.deinit();
    var arg_list: std.ArrayList([]const u8) = .empty;
    defer arg_list.deinit(gpa);
    while (it.next()) |a| {
        try arg_list.append(gpa, a);
    }

    var launch = cli.parse(gpa, arg_list.items) catch |err| {
        switch (err) {
            error.MissingValue => std.debug.print("error: flag requires a value (try --help)\n", .{}),
            error.UnknownArgument => std.debug.print("error: unknown argument (try --help)\n", .{}),
            error.OutOfMemory => return err,
        }
        std.process.exit(2);
    };
    defer launch.deinit(gpa);

    switch (launch.action) {
        .help => {
            cli.printHelp();
            return;
        },
        .version => {
            std.debug.print("{s}\n", .{version.tagged});
            return;
        },
        .ide_setup => {
            try ide_setup.run(gpa, init.io, launch.editor);
            return;
        },
        .update => {
            try updater.run(gpa, init.io, .{
                .check_only = launch.update_check,
                .force = launch.update_force,
                .rebuild_only = launch.update_rebuild,
                .rebuild_root = launch.cwd,
            });
            return;
        },
        .run => {},
    }

    if (std.c.getenv("ORBIT_IDE")) |v| {
        if (v[0] != 0 and launch.cwd == null) {
            if (processCwd(gpa, init.io)) |cwd| {
                launch.cwd = cwd;
                launch.skip_home = true;
            }
        }
    }

    macos_open.install();
    var pending: [std.fs.max_path_bytes]u8 = undefined;
    if (launch.cwd == null) {
        if (macos_open.take(&pending)) |p| {
            launch.cwd = try gpa.dupe(u8, p);
            launch.skip_home = true;
        }
    }

    var exec_buf: [][]const u8 = &.{};
    defer if (exec_buf.len > 0) gpa.free(exec_buf);
    if (launch.execute.len > 0) {
        exec_buf = try gpa.alloc([]const u8, launch.execute.len);
        for (launch.execute, 0..) |a, i| exec_buf[i] = a;
    }

    const app = try App.create(gpa, init.io, .{
        .cwd = launch.cwd,
        .title = launch.title,
        .execute = exec_buf,
        .wait_after_command = launch.wait_after_command,
        .skip_home = launch.skip_home,
    });
    defer app.destroy();

    std.log.info("Orbit {s} — stay in the flow", .{version.tagged});
    try app.run();
}

fn processCwd(allocator: std.mem.Allocator, io: std.Io) ?[]u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = std.Io.Dir.cwd().realPath(io, &buf) catch return null;
    return allocator.dupe(u8, buf[0..n]) catch null;
}
