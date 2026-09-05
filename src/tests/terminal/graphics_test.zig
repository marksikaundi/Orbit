const std = @import("std");
const gfx = @import("../../terminal/graphics.zig");
const Screen = @import("../../terminal/screen.zig").Screen;
const Parser = @import("../../terminal/parser.zig").Parser;

test "parse kitty keys" {
    const k = gfx.parseKittyKeys("a=T,f=32,s=8,v=4,m=0,i=3,c=2,r=1");
    try std.testing.expectEqual(@as(u8, 'T'), k.action);
    try std.testing.expectEqual(@as(u16, 32), k.format);
    try std.testing.expectEqual(@as(u32, 8), k.width);
    try std.testing.expectEqual(@as(u32, 4), k.height);
    try std.testing.expect(!k.more);
    try std.testing.expectEqual(@as(u32, 3), k.id);
    try std.testing.expectEqual(@as(u16, 2), k.cols);
    try std.testing.expectEqual(@as(u16, 1), k.rows);
}

test "decode base64" {
    const out = try gfx.decodeBase64(std.testing.allocator, "QQ==");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("A", out);
}

test "iterm payload and inline flag" {
    const osc = "1337;File=name=x.png;inline=1:QQ==";
    try std.testing.expect(gfx.isInlineIterm(osc));
    try std.testing.expectEqualStrings("QQ==", gfx.itermPayload(osc).?);
    try std.testing.expect(!gfx.isInlineIterm("1337;File=name=x.png:QQ=="));
}

test "kitty APC places a raw RGBA pixel" {
    var screen = try Screen.init(std.testing.allocator, 20, 5);
    defer screen.deinit();
    var parser = Parser.init();
    parser.feed(&screen, "\x1b_Ga=T,f=32,s=1,v=1;/wAA/w==\x1b\\");
    try std.testing.expectEqual(@as(usize, 1), screen.images.items.len);
    try std.testing.expectEqual(@as(u32, 1), screen.images.items[0].px_w);
    try std.testing.expectEqual(@as(u32, 1), screen.images.items[0].px_h);
    try std.testing.expectEqual(@as(u8, 255), screen.images.items[0].rgba[0]);
    try std.testing.expectEqual(@as(u8, 0), screen.images.items[0].rgba[1]);
}

test "kitty delete clears images" {
    var screen = try Screen.init(std.testing.allocator, 8, 4);
    defer screen.deinit();
    var parser = Parser.init();
    parser.feed(&screen, "\x1b_Ga=T,f=32,s=1,v=1;/wAA/w==\x1b\\");
    try std.testing.expectEqual(@as(usize, 1), screen.images.items.len);
    parser.feed(&screen, "\x1b_Ga=d\x1b\\");
    try std.testing.expectEqual(@as(usize, 0), screen.images.items.len);
}
