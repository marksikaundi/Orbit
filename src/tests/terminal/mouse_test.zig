const std = @import("std");
const mouse = @import("../../terminal/mouse.zig");

test "SGR press and release" {
    var buf: [32]u8 = undefined;
    const n = mouse.encode(.button, true, .{
        .button = 0,
        .col = 4,
        .row = 2,
        .press = true,
        .motion = false,
    }, &buf);
    try std.testing.expectEqualStrings("\x1b[<0;5;3M", buf[0..n]);

    const n2 = mouse.encode(.button, true, .{
        .button = 0,
        .col = 4,
        .row = 2,
        .press = false,
        .motion = false,
    }, &buf);
    try std.testing.expectEqualStrings("\x1b[<0;5;3m", buf[0..n2]);
}

test "off tracking writes nothing" {
    var buf: [32]u8 = undefined;
    const n = mouse.encode(.off, true, .{
        .button = 0,
        .col = 0,
        .row = 0,
        .press = true,
        .motion = false,
    }, &buf);
    try std.testing.expectEqual(@as(usize, 0), n);
}
