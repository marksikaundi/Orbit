//! Unit tests — language detection and syntax highlighting.

const std = @import("std");
const hl = @import("../../syntax/highlight.zig");

test "detectLanguage from common extensions" {
    try std.testing.expectEqual(hl.Language.javascript, hl.detectLanguage("app.js"));
    try std.testing.expectEqual(hl.Language.javascript, hl.detectLanguage("src/index.jsx"));
    try std.testing.expectEqual(hl.Language.typescript, hl.detectLanguage("main.ts"));
    try std.testing.expectEqual(hl.Language.python, hl.detectLanguage("train.py"));
    try std.testing.expectEqual(hl.Language.zig, hl.detectLanguage("src/app.zig"));
    try std.testing.expectEqual(hl.Language.rust, hl.detectLanguage("lib.rs"));
    try std.testing.expectEqual(hl.Language.go, hl.detectLanguage("main.go"));
    try std.testing.expectEqual(hl.Language.json, hl.detectLanguage("package.json"));
    try std.testing.expectEqual(hl.Language.html, hl.detectLanguage("index.html"));
    try std.testing.expectEqual(hl.Language.shell, hl.detectLanguage("Makefile"));
    try std.testing.expectEqual(hl.Language.none, hl.detectLanguage("README"));
}

test "javascript keywords strings and comments" {
    const line = "const name = \"Orbit\"; // hi";
    try std.testing.expectEqual(hl.Kind.keyword, hl.kindAt(line, .javascript, 0));
    try std.testing.expectEqual(hl.Kind.string, hl.kindAt(line, .javascript, 14));
    try std.testing.expectEqual(hl.Kind.comment, hl.kindAt(line, .javascript, 24));
}

test "javascript function call is distinct from keyword" {
    const line = "function greet() { greet(); }";
    try std.testing.expectEqual(hl.Kind.keyword, hl.kindAt(line, .javascript, 0));
    try std.testing.expectEqual(hl.Kind.function_name, hl.kindAt(line, .javascript, 9));
}

test "python def comment and string" {
    const line = "def greet():  # hello";
    try std.testing.expectEqual(hl.Kind.keyword, hl.kindAt(line, .python, 0));
    try std.testing.expectEqual(hl.Kind.function_name, hl.kindAt(line, .python, 4));
    try std.testing.expectEqual(hl.Kind.comment, hl.kindAt(line, .python, 14));

    try std.testing.expectEqual(hl.Kind.string, hl.kindAt("x = 'hi'", .python, 5));
}

test "json keys differ from string values" {
    const line = "{\"name\": \"ada\"}";
    try std.testing.expectEqual(hl.Kind.property, hl.kindAt(line, .json, 2));
    try std.testing.expectEqual(hl.Kind.string, hl.kindAt(line, .json, 11));
}

test "block comments carry across lines" {
    var state: hl.ScanState = .code;
    var spans: [hl.max_spans]hl.Span = undefined;
    _ = hl.highlightLine("foo /* start", .c, &state, &spans);
    try std.testing.expectEqual(hl.ScanState.block_comment, state);
    const n = hl.highlightLine(" still comment */ bar", .c, &state, &spans);
    try std.testing.expectEqual(hl.ScanState.code, state);
    try std.testing.expect(n >= 2);
    try std.testing.expectEqual(hl.Kind.comment, spans[0].kind);
}

test "languages have distinct labels" {
    try std.testing.expect(!std.mem.eql(u8, hl.languageLabel(.javascript), hl.languageLabel(.python)));
    try std.testing.expectEqualStrings("JavaScript", hl.languageLabel(.javascript));
    try std.testing.expectEqualStrings("Python", hl.languageLabel(.python));
}

test "zig keywords" {
    try std.testing.expectEqual(hl.Kind.keyword, hl.kindAt("pub fn main() void {}", .zig, 0));
    try std.testing.expectEqual(hl.Kind.keyword, hl.kindAt("pub fn main() void {}", .zig, 4));
    try std.testing.expectEqual(hl.Kind.function_name, hl.kindAt("pub fn main() void {}", .zig, 7));
}

test "html tags and attributes" {
    const line = "<div class=\"card\">";
    try std.testing.expectEqual(hl.Kind.keyword, hl.kindAt(line, .html, 1));
    try std.testing.expectEqual(hl.Kind.property, hl.kindAt(line, .html, 5));
    try std.testing.expectEqual(hl.Kind.string, hl.kindAt(line, .html, 12));
}
