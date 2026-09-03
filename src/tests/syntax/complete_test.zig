//! Unit tests — keyword / API / buffer-word completion.

const std = @import("std");
const complete = @import("../../syntax/complete.zig");

test "java prefix matches println and keywords" {
    var hits: [complete.max_results]complete.Hit = undefined;
    const n = complete.suggest(.java, "pri", "", &hits);
    try std.testing.expect(n >= 2);

    var saw_println = false;
    var saw_private = false;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (std.mem.indexOf(u8, hits[i].label(), "println") != null) saw_println = true;
        if (std.mem.eql(u8, hits[i].label(), "private")) saw_private = true;
        try std.testing.expect(hits[i].doc.len > 0);
    }
    try std.testing.expect(saw_println);
    try std.testing.expect(saw_private);
}

test "javascript console.log from con prefix" {
    var hits: [complete.max_results]complete.Hit = undefined;
    const n = complete.suggest(.javascript, "con", "", &hits);
    try std.testing.expect(n >= 1);
    var saw = false;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (std.mem.indexOf(u8, hits[i].label(), "console") != null) saw = true;
    }
    try std.testing.expect(saw);
}

test "python print from pr prefix" {
    var hits: [complete.max_results]complete.Hit = undefined;
    const n = complete.suggest(.python, "pr", "", &hits);
    try std.testing.expect(n >= 1);
    try std.testing.expectEqualStrings("print", hits[0].label());
}

test "identPrefix walks back through letters" {
    try std.testing.expectEqualStrings("println", complete.identPrefix("System.out.println", 18));
    try std.testing.expectEqualStrings("Sys", complete.identPrefix("Sys", 3));
    try std.testing.expectEqualStrings("", complete.identPrefix("x = ", 4));
}

test "dotted insert keeps the qualifier" {
    var hits: [complete.max_results]complete.Hit = undefined;
    const n = complete.suggest(.java, "pri", "", &hits);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (std.mem.indexOf(u8, hits[i].label(), "println") != null) {
            try std.testing.expectEqualStrings("println", hits[i].insert());
            break;
        }
    } else return error.TestUnexpectedResult;
}

test "buffer identifiers are offered" {
    var hits: [complete.max_results]complete.Hit = undefined;
    const n = complete.suggest(.java, "gre", "void greet() {}\n", &hits);
    var saw = false;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (std.mem.eql(u8, hits[i].label(), "greet")) saw = true;
    }
    try std.testing.expect(saw);
}
