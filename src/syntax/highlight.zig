//! Language-aware syntax highlighting for the file preview overlay.
//! Lightweight token scanner (not a full parser) — keywords, strings,
//! comments, numbers, types, and calls get distinct theme colors.

const std = @import("std");
const Color = @import("../terminal/cell.zig").Color;
const Theme = @import("../config/theme.zig").Theme;

pub const Language = enum {
    none,
    javascript,
    typescript,
    python,
    zig,
    rust,
    go,
    c,
    cpp,
    java,
    csharp,
    ruby,
    php,
    swift,
    kotlin,
    html,
    css,
    json,
    toml,
    yaml,
    markdown,
    shell,
    sql,
    lua,
};

pub const Kind = enum {
    text,
    comment,
    string,
    number,
    keyword,
    type_name,
    function_name,
    operator,
    punctuation,
    property,
};

pub const ScanState = enum {
    code,
    block_comment,
    html_comment,
    string_dquote,
    string_squote,
    string_backtick,
    string_triple_d,
    string_triple_s,
    md_fence,
};

pub const Span = struct {
    start: usize,
    end: usize,
    kind: Kind,
};

pub const max_spans: usize = 384;

pub fn detectLanguage(path: []const u8) Language {
    const base = basename(path);
    if (eqlIgnoreCase(base, "makefile") or eqlIgnoreCase(base, "gnumakefile")) return .shell;
    if (eqlIgnoreCase(base, "dockerfile")) return .shell;
    if (eqlIgnoreCase(base, "cmakelists.txt")) return .none;

    const ext = extension(base);
    if (ext.len == 0) return detectFromShebangName(base);

    if (eqlIgnoreCase(ext, "js") or eqlIgnoreCase(ext, "mjs") or eqlIgnoreCase(ext, "cjs") or eqlIgnoreCase(ext, "jsx")) return .javascript;
    if (eqlIgnoreCase(ext, "ts") or eqlIgnoreCase(ext, "mts") or eqlIgnoreCase(ext, "cts") or eqlIgnoreCase(ext, "tsx")) return .typescript;
    if (eqlIgnoreCase(ext, "py") or eqlIgnoreCase(ext, "pyw") or eqlIgnoreCase(ext, "pyi")) return .python;
    if (eqlIgnoreCase(ext, "zig")) return .zig;
    if (eqlIgnoreCase(ext, "rs")) return .rust;
    if (eqlIgnoreCase(ext, "go")) return .go;
    if (eqlIgnoreCase(ext, "c") or eqlIgnoreCase(ext, "h")) return .c;
    if (eqlIgnoreCase(ext, "cpp") or eqlIgnoreCase(ext, "cc") or eqlIgnoreCase(ext, "cxx") or
        eqlIgnoreCase(ext, "hpp") or eqlIgnoreCase(ext, "hh") or eqlIgnoreCase(ext, "hxx")) return .cpp;
    if (eqlIgnoreCase(ext, "java")) return .java;
    if (eqlIgnoreCase(ext, "cs")) return .csharp;
    if (eqlIgnoreCase(ext, "rb")) return .ruby;
    if (eqlIgnoreCase(ext, "php")) return .php;
    if (eqlIgnoreCase(ext, "swift")) return .swift;
    if (eqlIgnoreCase(ext, "kt") or eqlIgnoreCase(ext, "kts")) return .kotlin;
    if (eqlIgnoreCase(ext, "html") or eqlIgnoreCase(ext, "htm") or eqlIgnoreCase(ext, "xml") or
        eqlIgnoreCase(ext, "svg") or eqlIgnoreCase(ext, "vue") or eqlIgnoreCase(ext, "svelte")) return .html;
    if (eqlIgnoreCase(ext, "css") or eqlIgnoreCase(ext, "scss") or eqlIgnoreCase(ext, "less")) return .css;
    if (eqlIgnoreCase(ext, "json") or eqlIgnoreCase(ext, "jsonc") or eqlIgnoreCase(ext, "json5")) return .json;
    if (eqlIgnoreCase(ext, "toml")) return .toml;
    if (eqlIgnoreCase(ext, "yml") or eqlIgnoreCase(ext, "yaml")) return .yaml;
    if (eqlIgnoreCase(ext, "md") or eqlIgnoreCase(ext, "markdown") or eqlIgnoreCase(ext, "mdx")) return .markdown;
    if (eqlIgnoreCase(ext, "sh") or eqlIgnoreCase(ext, "bash") or eqlIgnoreCase(ext, "zsh") or
        eqlIgnoreCase(ext, "fish") or eqlIgnoreCase(ext, "ksh")) return .shell;
    if (eqlIgnoreCase(ext, "sql")) return .sql;
    if (eqlIgnoreCase(ext, "lua")) return .lua;
    return .none;
}

pub fn languageLabel(lang: Language) []const u8 {
    return switch (lang) {
        .none => "text",
        .javascript => "JavaScript",
        .typescript => "TypeScript",
        .python => "Python",
        .zig => "Zig",
        .rust => "Rust",
        .go => "Go",
        .c => "C",
        .cpp => "C++",
        .java => "Java",
        .csharp => "C#",
        .ruby => "Ruby",
        .php => "PHP",
        .swift => "Swift",
        .kotlin => "Kotlin",
        .html => "HTML",
        .css => "CSS",
        .json => "JSON",
        .toml => "TOML",
        .yaml => "YAML",
        .markdown => "Markdown",
        .shell => "Shell",
        .sql => "SQL",
        .lua => "Lua",
    };
}

/// Map a token kind onto the active theme so languages share a palette
/// but keywords / strings / comments still read as distinct.
pub fn colorFor(kind: Kind, theme: Theme) Color {
    return switch (kind) {
        .text => theme.foreground,
        .comment => mix(theme.foreground, theme.background, 1, 2),
        .string => theme.ansi[2],
        .number => theme.ansi[3],
        .keyword => theme.ansi[5],
        .type_name => theme.ansi[6],
        .function_name => theme.ansi[4],
        .operator => mix(theme.foreground, theme.ansi[3], 2, 1),
        .punctuation => mix(theme.foreground, theme.background, 2, 1),
        .property => theme.ansi[3],
    };
}

/// Token kind covering byte offset `col` on a single line (starts in `.code`).
pub fn kindAt(line: []const u8, lang: Language, col: usize) Kind {
    var state: ScanState = .code;
    var spans: [max_spans]Span = undefined;
    const n = highlightLine(line, lang, &state, &spans);
    for (spans[0..n]) |s| {
        if (col >= s.start and col < s.end) return s.kind;
    }
    return .text;
}

pub fn highlightLine(line: []const u8, lang: Language, state: *ScanState, out: *[max_spans]Span) usize {
    return switch (lang) {
        .html => scanHtml(line, state, out),
        .markdown => scanMarkdown(line, state, out),
        else => scanCode(line, lang, state, out),
    };
}

fn scanCode(line: []const u8, lang: Language, state: *ScanState, out: *[max_spans]Span) usize {
    var n: usize = 0;
    var i: usize = 0;
    const style = styleOf(lang);

    while (i < line.len) {
        switch (state.*) {
            .block_comment => {
                const close = style.block_close;
                if (indexOf(line[i..], close)) |rel| {
                    n = emit(out, n, i, i + rel + close.len, .comment);
                    i = i + rel + close.len;
                    state.* = .code;
                } else {
                    n = emit(out, n, i, line.len, .comment);
                    return n;
                }
                continue;
            },
            .html_comment => {
                if (indexOf(line[i..], "-->")) |rel| {
                    n = emit(out, n, i, i + rel + 3, .comment);
                    i = i + rel + 3;
                    state.* = .code;
                } else {
                    n = emit(out, n, i, line.len, .comment);
                    return n;
                }
                continue;
            },
            .string_dquote => {
                const end = scanStringEnd(line, i, '"', style.escapes) orelse {
                    n = emit(out, n, i, line.len, .string);
                    return n;
                };
                n = emit(out, n, i, end, .string);
                i = end;
                state.* = .code;
                continue;
            },
            .string_squote => {
                const end = scanStringEnd(line, i, '\'', style.escapes) orelse {
                    n = emit(out, n, i, line.len, .string);
                    return n;
                };
                n = emit(out, n, i, end, .string);
                i = end;
                state.* = .code;
                continue;
            },
            .string_backtick => {
                const end = scanStringEnd(line, i, '`', style.escapes) orelse {
                    n = emit(out, n, i, line.len, .string);
                    return n;
                };
                n = emit(out, n, i, end, .string);
                i = end;
                state.* = .code;
                continue;
            },
            .string_triple_d => {
                if (indexOf(line[i..], "\"\"\"")) |rel| {
                    n = emit(out, n, i, i + rel + 3, .string);
                    i = i + rel + 3;
                    state.* = .code;
                } else {
                    n = emit(out, n, i, line.len, .string);
                    return n;
                }
                continue;
            },
            .string_triple_s => {
                if (indexOf(line[i..], "'''")) |rel| {
                    n = emit(out, n, i, i + rel + 3, .string);
                    i = i + rel + 3;
                    state.* = .code;
                } else {
                    n = emit(out, n, i, line.len, .string);
                    return n;
                }
                continue;
            },
            .md_fence => {
                n = emit(out, n, i, line.len, .string);
                return n;
            },
            .code => {},
        }

        const ch = line[i];

        if (isSpace(ch)) {
            const start = i;
            i += 1;
            while (i < line.len and isSpace(line[i])) i += 1;
            n = emit(out, n, start, i, .text);
            continue;
        }

        if (style.triple and i + 2 < line.len) {
            if (line[i] == '"' and line[i + 1] == '"' and line[i + 2] == '"') {
                if (indexOf(line[i + 3 ..], "\"\"\"")) |rel| {
                    n = emit(out, n, i, i + 3 + rel + 3, .string);
                    i = i + 3 + rel + 3;
                } else {
                    n = emit(out, n, i, line.len, .string);
                    state.* = .string_triple_d;
                    return n;
                }
                continue;
            }
            if (line[i] == '\'' and line[i + 1] == '\'' and line[i + 2] == '\'') {
                if (indexOf(line[i + 3 ..], "'''")) |rel| {
                    n = emit(out, n, i, i + 3 + rel + 3, .string);
                    i = i + 3 + rel + 3;
                } else {
                    n = emit(out, n, i, line.len, .string);
                    state.* = .string_triple_s;
                    return n;
                }
                continue;
            }
        }

        if (style.line_comment.len > 0 and startsWith(line[i..], style.line_comment)) {
            n = emit(out, n, i, line.len, .comment);
            return n;
        }
        if (style.line_comment2.len > 0 and startsWith(line[i..], style.line_comment2)) {
            n = emit(out, n, i, line.len, .comment);
            return n;
        }
        if (style.block_open.len > 0 and startsWith(line[i..], style.block_open)) {
            const close = style.block_close;
            if (indexOf(line[i + style.block_open.len ..], close)) |rel| {
                n = emit(out, n, i, i + style.block_open.len + rel + close.len, .comment);
                i = i + style.block_open.len + rel + close.len;
            } else {
                n = emit(out, n, i, line.len, .comment);
                state.* = .block_comment;
                return n;
            }
            continue;
        }

        if (ch == '"' and style.dquote) {
            const end = scanStringEnd(line, i + 1, '"', style.escapes) orelse {
                n = emit(out, n, i, line.len, .string);
                state.* = .string_dquote;
                return n;
            };
            var kind: Kind = .string;
            if (looksLikeKey(line, end)) kind = .property;
            n = emit(out, n, i, end, kind);
            i = end;
            continue;
        }
        if (ch == '\'' and style.squote) {
            const end = scanStringEnd(line, i + 1, '\'', style.escapes) orelse {
                n = emit(out, n, i, line.len, .string);
                state.* = .string_squote;
                return n;
            };
            n = emit(out, n, i, end, .string);
            i = end;
            continue;
        }
        if (ch == '`' and style.backtick) {
            const end = scanStringEnd(line, i + 1, '`', style.escapes) orelse {
                n = emit(out, n, i, line.len, .string);
                state.* = .string_backtick;
                return n;
            };
            n = emit(out, n, i, end, .string);
            i = end;
            continue;
        }

        if (isDigit(ch) or (ch == '.' and i + 1 < line.len and isDigit(line[i + 1]))) {
            const start = i;
            i = scanNumber(line, i);
            n = emit(out, n, start, i, .number);
            continue;
        }

        if (isIdentStart(ch, lang)) {
            const start = i;
            i += 1;
            while (i < line.len and isIdentCont(line[i], lang)) i += 1;
            const word = line[start..i];
            const kind = classifyIdent(word, lang, line, i);
            n = emit(out, n, start, i, kind);
            continue;
        }

        if (ch == '.' and i + 1 < line.len and isIdentStart(line[i + 1], lang)) {
            n = emit(out, n, i, i + 1, .punctuation);
            i += 1;
            const start = i;
            i += 1;
            while (i < line.len and isIdentCont(line[i], lang)) i += 1;
            const after = skipSpace(line, i);
            const kind: Kind = if (after < line.len and line[after] == '(') .function_name else .property;
            n = emit(out, n, start, i, kind);
            continue;
        }

        if (isPunct(ch)) {
            n = emit(out, n, i, i + 1, .punctuation);
            i += 1;
            continue;
        }
        if (isOper(ch)) {
            const start = i;
            i += 1;
            while (i < line.len and isOper(line[i])) i += 1;
            n = emit(out, n, start, i, .operator);
            continue;
        }

        n = emit(out, n, i, i + 1, .text);
        i += 1;
    }
    return n;
}

fn scanHtml(line: []const u8, state: *ScanState, out: *[max_spans]Span) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < line.len) {
        if (state.* == .html_comment) {
            if (indexOf(line[i..], "-->")) |rel| {
                n = emit(out, n, i, i + rel + 3, .comment);
                i = i + rel + 3;
                state.* = .code;
            } else {
                n = emit(out, n, i, line.len, .comment);
                return n;
            }
            continue;
        }
        if (state.* == .string_dquote) {
            const end = scanStringEnd(line, i, '"', true) orelse {
                n = emit(out, n, i, line.len, .string);
                return n;
            };
            n = emit(out, n, i, end, .string);
            i = end;
            state.* = .code;
            continue;
        }
        if (state.* == .string_squote) {
            const end = scanStringEnd(line, i, '\'', true) orelse {
                n = emit(out, n, i, line.len, .string);
                return n;
            };
            n = emit(out, n, i, end, .string);
            i = end;
            state.* = .code;
            continue;
        }

        if (startsWith(line[i..], "<!--")) {
            if (indexOf(line[i + 4 ..], "-->")) |rel| {
                n = emit(out, n, i, i + 4 + rel + 3, .comment);
                i = i + 4 + rel + 3;
            } else {
                n = emit(out, n, i, line.len, .comment);
                state.* = .html_comment;
                return n;
            }
            continue;
        }
        if (line[i] == '<') {
            n = emit(out, n, i, i + 1, .punctuation);
            i += 1;
            if (i < line.len and (line[i] == '/' or line[i] == '!')) {
                n = emit(out, n, i, i + 1, .punctuation);
                i += 1;
            }
            const start = i;
            while (i < line.len and isIdentCont(line[i], .html)) i += 1;
            if (i > start) n = emit(out, n, start, i, .keyword);
            continue;
        }
        if (line[i] == '>') {
            n = emit(out, n, i, i + 1, .punctuation);
            i += 1;
            continue;
        }
        if (line[i] == '"' or line[i] == '\'') {
            const quote = line[i];
            const end = scanStringEnd(line, i + 1, quote, true) orelse {
                n = emit(out, n, i, line.len, .string);
                state.* = if (quote == '"') .string_dquote else .string_squote;
                return n;
            };
            n = emit(out, n, i, end, .string);
            i = end;
            continue;
        }
        if (isIdentStart(line[i], .html)) {
            const start = i;
            i += 1;
            while (i < line.len and isIdentCont(line[i], .html)) i += 1;
            const after = skipSpace(line, i);
            const kind: Kind = if (after < line.len and line[after] == '=') .property else .text;
            n = emit(out, n, start, i, kind);
            continue;
        }
        if (isSpace(line[i]) or isPunct(line[i]) or isOper(line[i])) {
            const kind: Kind = if (isSpace(line[i])) .text else if (isPunct(line[i])) .punctuation else .operator;
            n = emit(out, n, i, i + 1, kind);
            i += 1;
            continue;
        }
        n = emit(out, n, i, i + 1, .text);
        i += 1;
    }
    return n;
}

fn scanMarkdown(line: []const u8, state: *ScanState, out: *[max_spans]Span) usize {
    if (state.* == .md_fence) {
        if (startsWith(line[skipSpace(line, 0)..], "```")) {
            state.* = .code;
            return emit(out, 0, 0, line.len, .keyword);
        }
        return emit(out, 0, 0, line.len, .string);
    }

    const trimmed_i = skipSpace(line, 0);
    if (startsWith(line[trimmed_i..], "```")) {
        state.* = .md_fence;
        return emit(out, 0, 0, line.len, .keyword);
    }
    if (trimmed_i < line.len and line[trimmed_i] == '#') {
        return emit(out, 0, 0, line.len, .keyword);
    }

    var n: usize = 0;
    var i: usize = 0;
    while (i < line.len) {
        if (line[i] == '`') {
            if (indexOf(line[i + 1 ..], "`")) |rel| {
                n = emit(out, n, i, i + 1 + rel + 1, .string);
                i = i + 1 + rel + 1;
                continue;
            }
        }
        if (startsWith(line[i..], "**") or startsWith(line[i..], "__")) {
            n = emit(out, n, i, i + 2, .operator);
            i += 2;
            continue;
        }
        n = emit(out, n, i, i + 1, .text);
        i += 1;
    }
    return n;
}

fn classifyIdent(word: []const u8, lang: Language, line: []const u8, after_word: usize) Kind {
    if (isKeyword(word, lang)) return .keyword;
    if (isTypeWord(word, lang)) return .type_name;
    const after = skipSpace(line, after_word);
    if (after < line.len and line[after] == '(') return .function_name;
    if (looksLikeKey(line, after_word) and (lang == .json or lang == .toml or lang == .yaml)) return .property;
    if (word.len > 0 and word[0] >= 'A' and word[0] <= 'Z') {
        switch (lang) {
            .javascript, .typescript, .java, .csharp, .kotlin, .swift, .go, .rust, .zig, .c, .cpp => return .type_name,
            else => {},
        }
    }
    return .text;
}

fn isKeyword(word: []const u8, lang: Language) bool {
    return switch (lang) {
        .javascript => inList(word, &js_kw),
        .typescript => inList(word, &js_kw) or inList(word, &ts_kw),
        .python => inList(word, &py_kw),
        .zig => inList(word, &zig_kw),
        .rust => inList(word, &rust_kw),
        .go => inList(word, &go_kw),
        .c => inList(word, &c_kw),
        .cpp => inList(word, &c_kw) or inList(word, &cpp_kw),
        .java => inList(word, &java_kw),
        .csharp => inList(word, &cs_kw),
        .ruby => inList(word, &rb_kw),
        .php => inList(word, &php_kw),
        .swift => inList(word, &swift_kw),
        .kotlin => inList(word, &kt_kw),
        .css => inList(word, &css_kw),
        .json => inList(word, &json_kw),
        .toml => inList(word, &json_kw),
        .yaml => inList(word, &json_kw),
        .shell => inList(word, &sh_kw),
        .sql => inList(word, &sql_kw),
        .lua => inList(word, &lua_kw),
        else => false,
    };
}

fn isTypeWord(word: []const u8, lang: Language) bool {
    return switch (lang) {
        .c, .cpp, .java, .csharp, .kotlin, .swift, .go, .rust, .zig, .typescript => inList(word, &common_types),
        .python => inList(word, &py_types),
        else => false,
    };
}

const Style = struct {
    line_comment: []const u8 = "",
    line_comment2: []const u8 = "",
    block_open: []const u8 = "",
    block_close: []const u8 = "",
    dquote: bool = true,
    squote: bool = true,
    backtick: bool = false,
    triple: bool = false,
    escapes: bool = true,
};

fn styleOf(lang: Language) Style {
    return switch (lang) {
        .javascript, .typescript, .java, .csharp, .kotlin, .swift, .go, .css => .{
            .line_comment = "//",
            .block_open = "/*",
            .block_close = "*/",
            .backtick = true,
        },
        .c, .cpp, .rust => .{
            .line_comment = "//",
            .block_open = "/*",
            .block_close = "*/",
        },
        .zig => .{ .line_comment = "//", .squote = false },
        .php => .{
            .line_comment = "//",
            .line_comment2 = "#",
            .block_open = "/*",
            .block_close = "*/",
        },
        .python => .{ .line_comment = "#", .triple = true },
        .ruby, .shell, .toml, .yaml => .{ .line_comment = "#" },
        .sql => .{ .line_comment = "--", .block_open = "/*", .block_close = "*/" },
        .lua => .{ .line_comment = "--", .block_open = "--[[", .block_close = "]]" },
        .json => .{ .squote = false, .line_comment = "//", .block_open = "/*", .block_close = "*/" },
        .html, .markdown, .none => .{},
    };
}

fn scanStringEnd(line: []const u8, from: usize, quote: u8, escapes: bool) ?usize {
    var i = from;
    while (i < line.len) : (i += 1) {
        if (escapes and line[i] == '\\' and i + 1 < line.len) {
            i += 1;
            continue;
        }
        if (line[i] == quote) return i + 1;
    }
    return null;
}

fn scanNumber(line: []const u8, start: usize) usize {
    var i = start;
    if (i + 1 < line.len and line[i] == '0' and (line[i + 1] == 'x' or line[i + 1] == 'X' or
        line[i + 1] == 'b' or line[i + 1] == 'B' or line[i + 1] == 'o' or line[i + 1] == 'O'))
    {
        i += 2;
    }
    while (i < line.len) {
        const ch = line[i];
        if (isDigit(ch) or (ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F') or
            ch == '_' or ch == '.' or ch == 'x' or ch == 'X' or ch == 'b' or ch == 'B')
        {
            i += 1;
            continue;
        }
        if ((ch == 'e' or ch == 'E') and i + 1 < line.len) {
            i += 1;
            if (i < line.len and (line[i] == '+' or line[i] == '-')) i += 1;
            continue;
        }
        break;
    }
    return i;
}

fn looksLikeKey(line: []const u8, after: usize) bool {
    const i = skipSpace(line, after);
    return i < line.len and line[i] == ':';
}

fn emit(out: *[max_spans]Span, n: usize, start: usize, end: usize, kind: Kind) usize {
    if (end <= start) return n;
    if (n >= out.len) return n;
    if (n > 0 and out[n - 1].kind == kind and out[n - 1].end == start) {
        out[n - 1].end = end;
        return n;
    }
    out[n] = .{ .start = start, .end = end, .kind = kind };
    return n + 1;
}

fn skipSpace(line: []const u8, start: usize) usize {
    var i = start;
    while (i < line.len and isSpace(line[i])) i += 1;
    return i;
}

fn isSpace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\r';
}

fn isDigit(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}

fn isIdentStart(ch: u8, lang: Language) bool {
    if (ch == '_' or (ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z')) return true;
    if (ch == '$' and (lang == .javascript or lang == .typescript or lang == .php)) return true;
    if (ch == '@' and (lang == .zig or lang == .java or lang == .csharp or lang == .kotlin)) return true;
    return false;
}

fn isIdentCont(ch: u8, lang: Language) bool {
    if (isIdentStart(ch, lang) or isDigit(ch)) return true;
    if (ch == '-' and (lang == .html or lang == .css or lang == .yaml or lang == .toml)) return true;
    return false;
}

fn isPunct(ch: u8) bool {
    return switch (ch) {
        '(', ')', '[', ']', '{', '}', ',', ';', ':' => true,
        else => false,
    };
}

fn isOper(ch: u8) bool {
    return switch (ch) {
        '+', '-', '*', '/', '%', '=', '<', '>', '!', '&', '|', '^', '~', '?', '.', '\\' => true,
        else => false,
    };
}

fn inList(word: []const u8, list: []const []const u8) bool {
    for (list) |k| {
        if (std.mem.eql(u8, word, k)) return true;
    }
    return false;
}

fn basename(path: []const u8) []const u8 {
    const slash = std.mem.lastIndexOfAny(u8, path, "/\\") orelse return path;
    return path[slash + 1 ..];
}

fn extension(name: []const u8) []const u8 {
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return "";
    if (dot == 0 or dot + 1 >= name.len) return "";
    return name[dot + 1 ..];
}

fn detectFromShebangName(name: []const u8) Language {
    _ = name;
    return .none;
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn startsWith(s: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, s, prefix);
}

fn indexOf(hay: []const u8, needle: []const u8) ?usize {
    return std.mem.indexOf(u8, hay, needle);
}

fn mix(a: Color, b: Color, wa: i32, wb: i32) Color {
    const den = wa + wb;
    return Color.rgb(
        @intCast(@divTrunc(@as(i32, a.r) * wa + @as(i32, b.r) * wb, den)),
        @intCast(@divTrunc(@as(i32, a.g) * wa + @as(i32, b.g) * wb, den)),
        @intCast(@divTrunc(@as(i32, a.b) * wa + @as(i32, b.b) * wb, den)),
    );
}

const js_kw = [_][]const u8{
    "async",    "await",      "break",    "case",     "catch",     "class",    "const",     "continue",
    "debugger", "default",    "delete",   "do",       "else",      "export",   "extends",   "false",
    "finally",  "for",        "function", "if",       "import",    "in",       "instanceof","let",
    "new",      "null",       "of",       "return",   "static",    "super",    "switch",    "this",
    "throw",    "true",       "try",      "typeof",   "var",       "void",     "while",     "with",
    "yield",    "from",       "as",
};

const ts_kw = [_][]const u8{
    "abstract", "declare", "enum",     "implements", "infer",    "interface", "keyof",
    "namespace","never",   "private",  "protected",  "public",   "readonly",  "satisfies",
    "type",     "unique",  "unknown",  "override",
};

const py_kw = [_][]const u8{
    "False",  "None",   "True",    "and",    "as",     "assert", "async", "await",
    "break",  "class",  "continue","def",    "del",    "elif",   "else",  "except",
    "finally","for",    "from",    "global", "if",     "import", "in",    "is",
    "lambda", "nonlocal","not",    "or",     "pass",   "raise",  "return","try",
    "while",  "with",   "yield",   "match",  "case",
};

const zig_kw = [_][]const u8{
    "addrspace", "align",     "allowzero", "and",      "anyframe",  "anytype",   "asm",
    "async",     "await",     "break",     "callconv", "catch",     "comptime",  "const",
    "continue",  "defer",     "else",      "enum",     "errdefer",  "error",     "export",
    "extern",    "fn",        "for",       "if",       "inline",    "noalias",   "noinline",
    "nosuspend", "opaque",    "or",        "orelse",   "packed",    "pub",       "resume",
    "return",    "linksection","struct",   "suspend",  "switch",    "test",      "threadlocal",
    "try",       "union",     "unreachable","usingnamespace","var", "volatile",  "while",
};

const rust_kw = [_][]const u8{
    "as",       "async",  "await",   "break",    "const",   "continue", "crate",  "dyn",
    "else",     "enum",   "extern",  "false",    "fn",      "for",      "if",     "impl",
    "in",       "let",    "loop",    "match",    "mod",     "move",     "mut",    "pub",
    "ref",      "return", "self",    "Self",     "static",  "struct",   "super",  "trait",
    "true",     "type",   "unsafe",  "use",      "where",   "while",
};

const go_kw = [_][]const u8{
    "break", "case", "chan", "const", "continue", "default", "defer", "else",
    "fallthrough", "for", "func", "go", "goto", "if", "import", "interface",
    "map", "package", "range", "return", "select", "struct", "switch", "type",
    "var",
};

const c_kw = [_][]const u8{
    "auto",   "break",  "case",    "const",   "continue", "default", "do",     "else",
    "enum",   "extern", "for",     "goto",    "if",       "inline",  "register","restrict",
    "return", "sizeof", "static",  "struct",  "switch",   "typedef", "union",  "volatile",
    "while",  "NULL",
};

const cpp_kw = [_][]const u8{
    "class",     "namespace", "template", "typename", "using",    "public",  "private",
    "protected", "virtual",   "override", "final",    "new",      "delete",  "this",
    "try",       "catch",     "throw",    "true",     "false",    "nullptr", "constexpr",
    "consteval", "concept",   "requires", "co_await", "co_yield", "co_return",
};

const java_kw = [_][]const u8{
    "abstract", "assert",  "break",     "case",     "catch",    "class",    "const",
    "continue", "default", "do",        "else",     "enum",     "extends",  "final",
    "finally",  "for",     "goto",      "if",       "implements","import",  "instanceof",
    "interface","native",  "new",       "package",  "private",  "protected","public",
    "return",   "static",  "strictfp",  "super",    "switch",   "synchronized","this",
    "throw",    "throws",  "transient", "try",      "void",     "volatile", "while",
    "true",     "false",   "null",      "var",      "record",   "sealed",   "yield",
};

const cs_kw = [_][]const u8{
    "abstract", "as",       "base",     "break",    "case",     "catch",    "checked",
    "class",    "const",    "continue", "default",  "delegate", "do",       "else",
    "enum",     "event",    "explicit", "extern",   "false",    "finally",  "fixed",
    "for",      "foreach",  "goto",     "if",       "implicit", "in",       "interface",
    "internal", "is",       "lock",     "namespace","new",      "null",     "operator",
    "out",      "override", "params",   "private",  "protected","public",   "readonly",
    "ref",      "return",   "sealed",   "sizeof",   "stackalloc","static",  "struct",
    "switch",   "this",     "throw",    "true",     "try",      "typeof",   "unchecked",
    "unsafe",   "using",    "virtual",  "volatile", "while",    "async",    "await",
    "var",      "dynamic",  "record",
};

const rb_kw = [_][]const u8{
    "BEGIN", "END",  "alias",  "and",    "begin", "break", "case",  "class",
    "def",   "do",   "else",   "elsif",  "end",   "ensure","false", "for",
    "if",    "in",   "module", "next",   "nil",   "not",   "or",    "redo",
    "rescue","retry","return", "self",   "super", "then",  "true",  "undef",
    "unless","until","when",   "while",  "yield",
};

const php_kw = [_][]const u8{
    "abstract", "and",    "array",    "as",       "break",    "callable", "case",
    "catch",    "class",  "clone",    "const",    "continue", "declare",  "default",
    "do",       "echo",   "else",     "elseif",   "empty",    "enddeclare","endfor",
    "endforeach","endif", "endswitch","endwhile", "extends",  "final",    "finally",
    "fn",       "for",    "foreach",  "function", "global",   "goto",     "if",
    "implements","include","include_once","instanceof","insteadof","interface","isset",
    "list",     "match",  "namespace","new",      "or",       "print",    "private",
    "protected","public", "readonly", "require",  "require_once","return","static",
    "switch",   "throw",  "trait",    "try",      "unset",    "use",      "var",
    "while",    "xor",    "yield",    "true",     "false",    "null",
};

const swift_kw = [_][]const u8{
    "associatedtype", "class",  "deinit", "enum",    "extension", "fileprivate", "func",
    "import",         "init",   "inout",  "internal","let",       "open",        "operator",
    "private",        "protocol","public","rethrows","static",    "struct",      "subscript",
    "typealias",      "var",    "break",  "case",    "continue",  "default",     "defer",
    "do",             "else",   "fallthrough","for","guard",     "if",          "in",
    "repeat",         "return", "switch", "where",   "while",     "as",          "Any",
    "catch",          "false",  "is",     "nil",     "super",     "self",        "Self",
    "throw",          "throws", "true",   "try",     "async",     "await",
};

const kt_kw = [_][]const u8{
    "as",      "break",    "class",   "continue", "do",      "else",    "false",
    "for",     "fun",      "if",      "in",       "interface","is",     "null",
    "object",  "package",  "return",  "super",    "this",    "throw",   "true",
    "try",     "typealias","typeof",  "val",      "var",     "when",    "while",
    "by",      "catch",    "constructor","delegate","dynamic","field",  "file",
    "finally", "get",      "import",  "init",     "param",   "property","receiver",
    "set",     "setparam", "where",   "actual",   "abstract","annotation","companion",
    "const",   "crossinline","data",  "enum",     "expect",  "external","final",
    "infix",   "inline",   "inner",   "internal", "lateinit","noinline","open",
    "operator","out",      "override","private",  "protected","public", "reified",
    "sealed",  "suspend",  "tailrec", "vararg",
};

const css_kw = [_][]const u8{
    "important", "from", "to", "and", "not", "only", "or", "screen", "media",
};

const json_kw = [_][]const u8{ "true", "false", "null" };

const sh_kw = [_][]const u8{
    "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
    "case", "esac", "in", "function", "select", "time", "coproc", "return",
    "break", "continue", "export", "local", "readonly", "declare", "unset",
};

const sql_kw = [_][]const u8{
    "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
    "DELETE", "CREATE", "TABLE", "DROP", "ALTER", "JOIN", "LEFT", "RIGHT",
    "INNER", "OUTER", "ON", "AS", "AND", "OR", "NOT", "NULL", "TRUE", "FALSE",
    "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "OFFSET", "DISTINCT", "UNION",
    "select", "from", "where", "insert", "into", "values", "update", "set",
    "delete", "create", "table", "drop", "alter", "join", "left", "right",
    "inner", "outer", "on", "as", "and", "or", "not", "null", "true", "false",
    "order", "by", "group", "having", "limit", "offset", "distinct", "union",
};

const lua_kw = [_][]const u8{
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function",
    "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then",
    "true", "until", "while",
};

const common_types = [_][]const u8{
    "int",     "uint",    "i8",      "i16",     "i32",     "i64",     "i128",
    "u8",      "u16",     "u32",     "u64",     "u128",    "f32",     "f64",
    "isize",   "usize",   "bool",    "char",    "void",    "string",  "String",
    "float",   "double",  "long",    "short",   "unsigned","signed",  "size_t",
    "int8_t",  "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t","uint32_t",
    "uint64_t","any",     "unknown", "never",   "number",  "boolean", "object",
    "byte",    "rune",    "error",   "type",    "Self",
};

const py_types = [_][]const u8{
    "int", "str", "float", "bool", "list", "dict", "tuple", "set", "bytes",
    "None", "Optional", "List", "Dict", "Tuple", "Set", "Any", "Union",
};
