//! Autocomplete + short docs for the file editor overlay.
//! Keyword / API catalog plus identifiers already in the buffer — not a full LSP.

const std = @import("std");
const highlight = @import("highlight.zig");

pub const Language = highlight.Language;

pub const Kind = enum { keyword, func, type_name, ident };

pub const max_results: usize = 10;

pub const Hit = struct {
    label_buf: [72]u8 = undefined,
    insert_buf: [80]u8 = undefined,
    label_len: u8 = 0,
    insert_len: u8 = 0,
    kind: Kind = .keyword,
    detail: []const u8 = "",
    doc: []const u8 = "",

    pub fn label(self: *const Hit) []const u8 {
        return self.label_buf[0..self.label_len];
    }

    pub fn insert(self: *const Hit) []const u8 {
        return self.insert_buf[0..self.insert_len];
    }

    pub fn kindTag(self: *const Hit) []const u8 {
        return switch (self.kind) {
            .keyword => "kw",
            .func => "fn",
            .type_name => "type",
            .ident => "id",
        };
    }
};

const Entry = struct {
    label: []const u8,
    kind: Kind,
    detail: []const u8,
    doc: []const u8,
};

pub fn suggest(lang: Language, prefix: []const u8, buffer: []const u8, out: *[max_results]Hit) usize {
    var n: usize = 0;
    const catalog = catalogFor(lang);
    for (catalog) |e| {
        if (!matches(e.label, prefix)) continue;
        n = push(out, n, e.label, insertFor(e.label, prefix), e.kind, e.detail, e.doc);
        if (n == max_results) return n;
    }
    n = harvestIdents(buffer, prefix, catalog, out, n);
    return n;
}

pub fn identPrefix(line: []const u8, col: usize) []const u8 {
    const end = @min(col, line.len);
    if (end == 0) return "";
    var i = end;
    while (i > 0) {
        const ch = line[i - 1];
        if (!isIdent(ch)) break;
        i -= 1;
    }
    return line[i..end];
}

fn matches(label: []const u8, prefix: []const u8) bool {
    if (prefix.len == 0) return true;
    if (startsIgnore(label, prefix)) return true;
    if (std.mem.lastIndexOfScalar(u8, label, '.')) |dot| {
        if (dot + 1 < label.len and startsIgnore(label[dot + 1 ..], prefix)) return true;
    }
    return false;
}

fn insertFor(label: []const u8, prefix: []const u8) []const u8 {
    const last = lastSeg(label);
    if (prefix.len == 0) return last;
    if (startsIgnore(label, prefix)) return label;
    return last;
}

fn lastSeg(label: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, label, '.')) |dot| {
        if (dot + 1 < label.len) return label[dot + 1 ..];
    }
    return label;
}

fn startsIgnore(s: []const u8, prefix: []const u8) bool {
    if (prefix.len > s.len) return false;
    return std.ascii.eqlIgnoreCase(s[0..prefix.len], prefix);
}

fn push(
    out: *[max_results]Hit,
    n: usize,
    label: []const u8,
    insert: []const u8,
    kind: Kind,
    detail: []const u8,
    doc: []const u8,
) usize {
    if (n >= max_results) return n;
    var hit: Hit = .{
        .kind = kind,
        .detail = detail,
        .doc = doc,
    };
    const ll = @min(label.len, hit.label_buf.len);
    @memcpy(hit.label_buf[0..ll], label[0..ll]);
    hit.label_len = @intCast(ll);
    const il = @min(insert.len, hit.insert_buf.len);
    @memcpy(hit.insert_buf[0..il], insert[0..il]);
    hit.insert_len = @intCast(il);
    out[n] = hit;
    return n + 1;
}

fn harvestIdents(buffer: []const u8, prefix: []const u8, catalog: []const Entry, out: *[max_results]Hit, start: usize) usize {
    var n = start;
    if (prefix.len == 0) return n;
    var i: usize = 0;
    while (i < buffer.len and n < max_results) {
        if (!isIdentStart(buffer[i])) {
            i += 1;
            continue;
        }
        const begin = i;
        i += 1;
        while (i < buffer.len and isIdent(buffer[i])) i += 1;
        const word = buffer[begin..i];
        if (word.len < 2 or !startsIgnore(word, prefix)) continue;
        if (alreadyHave(out, n, word) or inCatalog(catalog, word)) continue;
        n = push(out, n, word, word, .ident, "in this file", "Name already used in this file");
    }
    return n;
}

fn alreadyHave(out: *[max_results]Hit, n: usize, label: []const u8) bool {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(out[i].label(), label)) return true;
    }
    return false;
}

fn inCatalog(catalog: []const Entry, word: []const u8) bool {
    for (catalog) |e| {
        if (std.mem.eql(u8, e.label, word)) return true;
        if (std.mem.lastIndexOfScalar(u8, e.label, '.')) |dot| {
            if (std.mem.eql(u8, e.label[dot + 1 ..], word)) return true;
        }
    }
    return false;
}

fn isIdentStart(ch: u8) bool {
    return (ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z') or ch == '_';
}

fn isIdent(ch: u8) bool {
    return isIdentStart(ch) or (ch >= '0' and ch <= '9') or ch == '$';
}

fn catalogFor(lang: Language) []const Entry {
    return switch (lang) {
        .java => &java_cat,
        .javascript, .typescript => &js_cat,
        .python => &py_cat,
        .zig => &zig_cat,
        .rust => &rust_cat,
        .go => &go_cat,
        .c, .cpp => &c_cat,
        .csharp => &cs_cat,
        .ruby => &rb_cat,
        .php => &php_cat,
        .swift => &swift_cat,
        .kotlin => &kt_cat,
        .html => &html_cat,
        .css => &css_cat,
        .shell => &sh_cat,
        .sql => &sql_cat,
        .lua => &lua_cat,
        .json, .toml, .yaml, .markdown, .none => &generic_cat,
    };
}

const java_cat = [_]Entry{
    .{ .label = "public", .kind = .keyword, .detail = "keyword", .doc = "Makes a class, method, or field visible everywhere" },
    .{ .label = "private", .kind = .keyword, .detail = "keyword", .doc = "Visible only inside the enclosing class" },
    .{ .label = "protected", .kind = .keyword, .detail = "keyword", .doc = "Visible to subclasses and the same package" },
    .{ .label = "static", .kind = .keyword, .detail = "keyword", .doc = "Belongs to the class, not an instance" },
    .{ .label = "void", .kind = .type_name, .detail = "type", .doc = "Method returns no value" },
    .{ .label = "class", .kind = .keyword, .detail = "keyword", .doc = "Declares a class" },
    .{ .label = "interface", .kind = .keyword, .detail = "keyword", .doc = "Declares a contract of methods" },
    .{ .label = "extends", .kind = .keyword, .detail = "keyword", .doc = "Subclass another class" },
    .{ .label = "implements", .kind = .keyword, .detail = "keyword", .doc = "Adopt an interface" },
    .{ .label = "new", .kind = .keyword, .detail = "keyword", .doc = "Construct an object" },
    .{ .label = "return", .kind = .keyword, .detail = "keyword", .doc = "Exit a method with a value" },
    .{ .label = "if", .kind = .keyword, .detail = "keyword", .doc = "Run a block when a condition is true" },
    .{ .label = "else", .kind = .keyword, .detail = "keyword", .doc = "Run when the if condition is false" },
    .{ .label = "for", .kind = .keyword, .detail = "keyword", .doc = "Loop with initializer, test, and step" },
    .{ .label = "while", .kind = .keyword, .detail = "keyword", .doc = "Loop while a condition stays true" },
    .{ .label = "try", .kind = .keyword, .detail = "keyword", .doc = "Start a block that may throw" },
    .{ .label = "catch", .kind = .keyword, .detail = "keyword", .doc = "Handle an exception" },
    .{ .label = "throw", .kind = .keyword, .detail = "keyword", .doc = "Raise an exception" },
    .{ .label = "import", .kind = .keyword, .detail = "keyword", .doc = "Bring a package or type into scope" },
    .{ .label = "package", .kind = .keyword, .detail = "keyword", .doc = "Declare this file's package" },
    .{ .label = "String", .kind = .type_name, .detail = "java.lang.String", .doc = "Immutable sequence of characters" },
    .{ .label = "int", .kind = .type_name, .detail = "primitive", .doc = "32-bit integer" },
    .{ .label = "boolean", .kind = .type_name, .detail = "primitive", .doc = "true or false" },
    .{ .label = "System.out.println", .kind = .func, .detail = "void println(Object)", .doc = "Print a line to standard output, then a newline" },
    .{ .label = "System.out.print", .kind = .func, .detail = "void print(Object)", .doc = "Print to standard output without a newline" },
    .{ .label = "System.out.printf", .kind = .func, .detail = "void printf(String, Object...)", .doc = "Print a formatted string to standard output" },
    .{ .label = "length", .kind = .func, .detail = "int length()", .doc = "Number of characters (String) or elements (array)" },
    .{ .label = "equals", .kind = .func, .detail = "boolean equals(Object)", .doc = "True when this object equals the argument" },
    .{ .label = "toString", .kind = .func, .detail = "String toString()", .doc = "Readable string form of this object" },
    .{ .label = "charAt", .kind = .func, .detail = "char charAt(int)", .doc = "Character at an index in a String" },
    .{ .label = "substring", .kind = .func, .detail = "String substring(int, int)", .doc = "Slice of this String from start (inclusive) to end" },
    .{ .label = "ArrayList", .kind = .type_name, .detail = "java.util.ArrayList", .doc = "Resizable array list" },
    .{ .label = "HashMap", .kind = .type_name, .detail = "java.util.HashMap", .doc = "Hash table of keys to values" },
    .{ .label = "add", .kind = .func, .detail = "boolean add(E)", .doc = "Append an element to a collection" },
    .{ .label = "get", .kind = .func, .detail = "E get(int) / V get(K)", .doc = "Read a list index or map key" },
    .{ .label = "put", .kind = .func, .detail = "V put(K, V)", .doc = "Insert or replace a map entry" },
    .{ .label = "size", .kind = .func, .detail = "int size()", .doc = "Number of elements in a collection" },
    .{ .label = "Math.max", .kind = .func, .detail = "int max(int, int)", .doc = "Larger of two numbers" },
    .{ .label = "Math.min", .kind = .func, .detail = "int min(int, int)", .doc = "Smaller of two numbers" },
    .{ .label = "Math.abs", .kind = .func, .detail = "int abs(int)", .doc = "Absolute value" },
    .{ .label = "main", .kind = .func, .detail = "public static void main(String[] args)", .doc = "Program entry point" },
};

const js_cat = [_]Entry{
    .{ .label = "const", .kind = .keyword, .detail = "keyword", .doc = "Declare a binding that cannot be reassigned" },
    .{ .label = "let", .kind = .keyword, .detail = "keyword", .doc = "Declare a block-scoped variable" },
    .{ .label = "function", .kind = .keyword, .detail = "keyword", .doc = "Declare a function" },
    .{ .label = "return", .kind = .keyword, .detail = "keyword", .doc = "Exit with a value" },
    .{ .label = "async", .kind = .keyword, .detail = "keyword", .doc = "Function may await Promises" },
    .{ .label = "await", .kind = .keyword, .detail = "keyword", .doc = "Pause until a Promise settles" },
    .{ .label = "import", .kind = .keyword, .detail = "keyword", .doc = "Load a module" },
    .{ .label = "export", .kind = .keyword, .detail = "keyword", .doc = "Expose a name from this module" },
    .{ .label = "class", .kind = .keyword, .detail = "keyword", .doc = "Declare a class" },
    .{ .label = "if", .kind = .keyword, .detail = "keyword", .doc = "Run a block when a condition is true" },
    .{ .label = "else", .kind = .keyword, .detail = "keyword", .doc = "Run when the if condition is false" },
    .{ .label = "for", .kind = .keyword, .detail = "keyword", .doc = "Loop" },
    .{ .label = "console.log", .kind = .func, .detail = "log(...args)", .doc = "Print values to the developer console" },
    .{ .label = "console.error", .kind = .func, .detail = "error(...args)", .doc = "Print an error to the console" },
    .{ .label = "JSON.parse", .kind = .func, .detail = "parse(text)", .doc = "Parse a JSON string into a value" },
    .{ .label = "JSON.stringify", .kind = .func, .detail = "stringify(value)", .doc = "Turn a value into a JSON string" },
    .{ .label = "fetch", .kind = .func, .detail = "fetch(url, init?)", .doc = "HTTP request; returns a Promise<Response>" },
    .{ .label = "map", .kind = .func, .detail = "array.map(fn)", .doc = "Build a new array by transforming each item" },
    .{ .label = "filter", .kind = .func, .detail = "array.filter(fn)", .doc = "Keep items where the callback is true" },
    .{ .label = "reduce", .kind = .func, .detail = "array.reduce(fn, init)", .doc = "Fold the array down to a single value" },
    .{ .label = "forEach", .kind = .func, .detail = "array.forEach(fn)", .doc = "Call a function for every item" },
    .{ .label = "push", .kind = .func, .detail = "array.push(...items)", .doc = "Append items to the end of an array" },
    .{ .label = "Promise", .kind = .type_name, .detail = "Promise", .doc = "Eventually-available async value" },
    .{ .label = "setTimeout", .kind = .func, .detail = "setTimeout(fn, ms)", .doc = "Run a function after a delay" },
    .{ .label = "document.querySelector", .kind = .func, .detail = "querySelector(sel)", .doc = "First DOM node matching a CSS selector" },
    .{ .label = "addEventListener", .kind = .func, .detail = "addEventListener(type, fn)", .doc = "Listen for a DOM event" },
    .{ .label = "parseInt", .kind = .func, .detail = "parseInt(text, radix?)", .doc = "Parse a string as an integer" },
};

const py_cat = [_]Entry{
    .{ .label = "def", .kind = .keyword, .detail = "keyword", .doc = "Define a function" },
    .{ .label = "class", .kind = .keyword, .detail = "keyword", .doc = "Define a class" },
    .{ .label = "return", .kind = .keyword, .detail = "keyword", .doc = "Exit with a value" },
    .{ .label = "import", .kind = .keyword, .detail = "keyword", .doc = "Load a module" },
    .{ .label = "from", .kind = .keyword, .detail = "keyword", .doc = "Import names from a module" },
    .{ .label = "if", .kind = .keyword, .detail = "keyword", .doc = "Run a block when a condition is true" },
    .{ .label = "elif", .kind = .keyword, .detail = "keyword", .doc = "Else-if branch" },
    .{ .label = "else", .kind = .keyword, .detail = "keyword", .doc = "Run when previous tests fail" },
    .{ .label = "for", .kind = .keyword, .detail = "keyword", .doc = "Iterate over a sequence" },
    .{ .label = "while", .kind = .keyword, .detail = "keyword", .doc = "Loop while a condition is true" },
    .{ .label = "try", .kind = .keyword, .detail = "keyword", .doc = "Start a block that may raise" },
    .{ .label = "except", .kind = .keyword, .detail = "keyword", .doc = "Handle an exception" },
    .{ .label = "with", .kind = .keyword, .detail = "keyword", .doc = "Context manager (files, locks)" },
    .{ .label = "lambda", .kind = .keyword, .detail = "keyword", .doc = "Anonymous function" },
    .{ .label = "print", .kind = .func, .detail = "print(*args)", .doc = "Write values to standard output" },
    .{ .label = "len", .kind = .func, .detail = "len(obj)", .doc = "Number of items in a collection" },
    .{ .label = "range", .kind = .func, .detail = "range(stop) / range(start, stop)", .doc = "Sequence of integers for loops" },
    .{ .label = "open", .kind = .func, .detail = "open(path, mode='r')", .doc = "Open a file; use in a with-block" },
    .{ .label = "str", .kind = .type_name, .detail = "str(x)", .doc = "Text type / convert to string" },
    .{ .label = "list", .kind = .type_name, .detail = "list", .doc = "Mutable sequence" },
    .{ .label = "dict", .kind = .type_name, .detail = "dict", .doc = "Key-value map" },
    .{ .label = "append", .kind = .func, .detail = "list.append(x)", .doc = "Add an item at the end of a list" },
    .{ .label = "join", .kind = .func, .detail = "str.join(iterable)", .doc = "Concatenate strings with this separator" },
    .{ .label = "split", .kind = .func, .detail = "str.split(sep=None)", .doc = "Break a string into a list" },
    .{ .label = "format", .kind = .func, .detail = "str.format(*args)", .doc = "Fill {} placeholders in a string" },
};

const zig_cat = [_]Entry{
    .{ .label = "pub", .kind = .keyword, .detail = "keyword", .doc = "Export this declaration" },
    .{ .label = "fn", .kind = .keyword, .detail = "keyword", .doc = "Declare a function" },
    .{ .label = "const", .kind = .keyword, .detail = "keyword", .doc = "Immutable binding" },
    .{ .label = "var", .kind = .keyword, .detail = "keyword", .doc = "Mutable binding" },
    .{ .label = "try", .kind = .keyword, .detail = "keyword", .doc = "Return early on error" },
    .{ .label = "catch", .kind = .keyword, .detail = "keyword", .doc = "Handle an error union" },
    .{ .label = "defer", .kind = .keyword, .detail = "keyword", .doc = "Run at the end of this scope" },
    .{ .label = "struct", .kind = .keyword, .detail = "keyword", .doc = "Declare a struct type" },
    .{ .label = "enum", .kind = .keyword, .detail = "keyword", .doc = "Declare an enum type" },
    .{ .label = "if", .kind = .keyword, .detail = "keyword", .doc = "Conditional" },
    .{ .label = "while", .kind = .keyword, .detail = "keyword", .doc = "Loop" },
    .{ .label = "for", .kind = .keyword, .detail = "keyword", .doc = "Iterate a range or collection" },
    .{ .label = "return", .kind = .keyword, .detail = "keyword", .doc = "Exit with a value" },
    .{ .label = "std", .kind = .ident, .detail = "module", .doc = "Zig standard library" },
    .{ .label = "std.debug.print", .kind = .func, .detail = "print(fmt, args)", .doc = "Print to stderr (debug)" },
    .{ .label = "std.mem.eql", .kind = .func, .detail = "eql(T, a, b)", .doc = "True when two slices are equal" },
};

const rust_cat = [_]Entry{
    .{ .label = "fn", .kind = .keyword, .detail = "keyword", .doc = "Declare a function" },
    .{ .label = "let", .kind = .keyword, .detail = "keyword", .doc = "Bind a variable" },
    .{ .label = "mut", .kind = .keyword, .detail = "keyword", .doc = "Allow mutation" },
    .{ .label = "pub", .kind = .keyword, .detail = "keyword", .doc = "Public item" },
    .{ .label = "struct", .kind = .keyword, .detail = "keyword", .doc = "Declare a struct" },
    .{ .label = "enum", .kind = .keyword, .detail = "keyword", .doc = "Declare an enum" },
    .{ .label = "impl", .kind = .keyword, .detail = "keyword", .doc = "Implement methods for a type" },
    .{ .label = "match", .kind = .keyword, .detail = "keyword", .doc = "Pattern match" },
    .{ .label = "if", .kind = .keyword, .detail = "keyword", .doc = "Conditional" },
    .{ .label = "return", .kind = .keyword, .detail = "keyword", .doc = "Exit with a value" },
    .{ .label = "println!", .kind = .func, .detail = "println!(fmt, ...)", .doc = "Print a line to stdout" },
    .{ .label = "vec!", .kind = .func, .detail = "vec![...]", .doc = "Create a Vec from elements" },
    .{ .label = "Some", .kind = .func, .detail = "Option::Some", .doc = "Option with a value" },
    .{ .label = "None", .kind = .keyword, .detail = "Option::None", .doc = "Empty Option" },
    .{ .label = "Ok", .kind = .func, .detail = "Result::Ok", .doc = "Successful Result" },
    .{ .label = "Err", .kind = .func, .detail = "Result::Err", .doc = "Failed Result" },
};

const go_cat = [_]Entry{
    .{ .label = "func", .kind = .keyword, .detail = "keyword", .doc = "Declare a function" },
    .{ .label = "package", .kind = .keyword, .detail = "keyword", .doc = "Package name (first line)" },
    .{ .label = "import", .kind = .keyword, .detail = "keyword", .doc = "Import a package" },
    .{ .label = "var", .kind = .keyword, .detail = "keyword", .doc = "Declare a variable" },
    .{ .label = "const", .kind = .keyword, .detail = "keyword", .doc = "Declare a constant" },
    .{ .label = "type", .kind = .keyword, .detail = "keyword", .doc = "Declare a named type" },
    .{ .label = "struct", .kind = .keyword, .detail = "keyword", .doc = "Struct type" },
    .{ .label = "interface", .kind = .keyword, .detail = "keyword", .doc = "Interface type" },
    .{ .label = "if", .kind = .keyword, .detail = "keyword", .doc = "Conditional" },
    .{ .label = "for", .kind = .keyword, .detail = "keyword", .doc = "The only loop keyword in Go" },
    .{ .label = "return", .kind = .keyword, .detail = "keyword", .doc = "Exit with values" },
    .{ .label = "defer", .kind = .keyword, .detail = "keyword", .doc = "Run at the end of this function" },
    .{ .label = "go", .kind = .keyword, .detail = "keyword", .doc = "Start a goroutine" },
    .{ .label = "fmt.Println", .kind = .func, .detail = "Println(a ...any)", .doc = "Print values plus a newline" },
    .{ .label = "fmt.Printf", .kind = .func, .detail = "Printf(format, a ...any)", .doc = "Print a formatted string" },
    .{ .label = "len", .kind = .func, .detail = "len(v)", .doc = "Length of a string, slice, or map" },
    .{ .label = "append", .kind = .func, .detail = "append(slice, elems...)", .doc = "Append elements to a slice" },
    .{ .label = "make", .kind = .func, .detail = "make(T, size)", .doc = "Allocate a slice, map, or channel" },
};

const c_cat = [_]Entry{
    .{ .label = "int", .kind = .type_name, .detail = "type", .doc = "Integer type" },
    .{ .label = "char", .kind = .type_name, .detail = "type", .doc = "Character / byte type" },
    .{ .label = "void", .kind = .type_name, .detail = "type", .doc = "No value / generic pointer" },
    .{ .label = "struct", .kind = .keyword, .detail = "keyword", .doc = "Declare a struct" },
    .{ .label = "return", .kind = .keyword, .detail = "keyword", .doc = "Exit with a value" },
    .{ .label = "if", .kind = .keyword, .detail = "keyword", .doc = "Conditional" },
    .{ .label = "else", .kind = .keyword, .detail = "keyword", .doc = "Else branch" },
    .{ .label = "for", .kind = .keyword, .detail = "keyword", .doc = "Loop" },
    .{ .label = "while", .kind = .keyword, .detail = "keyword", .doc = "Loop while true" },
    .{ .label = "sizeof", .kind = .keyword, .detail = "keyword", .doc = "Size of a type or value in bytes" },
    .{ .label = "printf", .kind = .func, .detail = "int printf(const char *, ...)", .doc = "Print formatted text to stdout" },
    .{ .label = "scanf", .kind = .func, .detail = "int scanf(const char *, ...)", .doc = "Read formatted input from stdin" },
    .{ .label = "malloc", .kind = .func, .detail = "void *malloc(size_t)", .doc = "Allocate heap memory" },
    .{ .label = "free", .kind = .func, .detail = "void free(void *)", .doc = "Release heap memory" },
    .{ .label = "strlen", .kind = .func, .detail = "size_t strlen(const char *)", .doc = "Length of a C string" },
    .{ .label = "memcpy", .kind = .func, .detail = "void *memcpy(dst, src, n)", .doc = "Copy n bytes" },
};

const cs_cat = [_]Entry{
    .{ .label = "public", .kind = .keyword, .detail = "keyword", .doc = "Visible everywhere" },
    .{ .label = "class", .kind = .keyword, .detail = "keyword", .doc = "Declare a class" },
    .{ .label = "void", .kind = .type_name, .detail = "type", .doc = "No return value" },
    .{ .label = "string", .kind = .type_name, .detail = "type", .doc = "Text" },
    .{ .label = "int", .kind = .type_name, .detail = "type", .doc = "32-bit integer" },
    .{ .label = "var", .kind = .keyword, .detail = "keyword", .doc = "Infer the type" },
    .{ .label = "new", .kind = .keyword, .detail = "keyword", .doc = "Construct an object" },
    .{ .label = "return", .kind = .keyword, .detail = "keyword", .doc = "Exit with a value" },
    .{ .label = "if", .kind = .keyword, .detail = "keyword", .doc = "Conditional" },
    .{ .label = "Console.WriteLine", .kind = .func, .detail = "WriteLine(value)", .doc = "Print a line to the console" },
    .{ .label = "Console.Write", .kind = .func, .detail = "Write(value)", .doc = "Print without a newline" },
    .{ .label = "ToString", .kind = .func, .detail = "ToString()", .doc = "String form of this object" },
    .{ .label = "Length", .kind = .func, .detail = "int Length", .doc = "Number of characters or elements" },
};

const rb_cat = [_]Entry{
    .{ .label = "def", .kind = .keyword, .detail = "keyword", .doc = "Define a method" },
    .{ .label = "class", .kind = .keyword, .detail = "keyword", .doc = "Define a class" },
    .{ .label = "end", .kind = .keyword, .detail = "keyword", .doc = "Close a block" },
    .{ .label = "if", .kind = .keyword, .detail = "keyword", .doc = "Conditional" },
    .{ .label = "puts", .kind = .func, .detail = "puts(obj)", .doc = "Print with a newline" },
    .{ .label = "print", .kind = .func, .detail = "print(obj)", .doc = "Print without a newline" },
    .{ .label = "each", .kind = .func, .detail = "each { |x| ... }", .doc = "Iterate a collection" },
    .{ .label = "map", .kind = .func, .detail = "map { |x| ... }", .doc = "Transform each item" },
    .{ .label = "require", .kind = .func, .detail = "require(path)", .doc = "Load a library" },
};

const php_cat = [_]Entry{
    .{ .label = "function", .kind = .keyword, .detail = "keyword", .doc = "Declare a function" },
    .{ .label = "class", .kind = .keyword, .detail = "keyword", .doc = "Declare a class" },
    .{ .label = "echo", .kind = .keyword, .detail = "keyword", .doc = "Print a string" },
    .{ .label = "return", .kind = .keyword, .detail = "keyword", .doc = "Exit with a value" },
    .{ .label = "if", .kind = .keyword, .detail = "keyword", .doc = "Conditional" },
    .{ .label = "foreach", .kind = .keyword, .detail = "keyword", .doc = "Iterate an array" },
    .{ .label = "array", .kind = .func, .detail = "array(...)", .doc = "Create an array" },
    .{ .label = "strlen", .kind = .func, .detail = "strlen(string)", .doc = "Length of a string" },
    .{ .label = "count", .kind = .func, .detail = "count(array)", .doc = "Number of elements" },
};

const swift_cat = [_]Entry{
    .{ .label = "func", .kind = .keyword, .detail = "keyword", .doc = "Declare a function" },
    .{ .label = "let", .kind = .keyword, .detail = "keyword", .doc = "Immutable binding" },
    .{ .label = "var", .kind = .keyword, .detail = "keyword", .doc = "Mutable binding" },
    .{ .label = "class", .kind = .keyword, .detail = "keyword", .doc = "Reference type" },
    .{ .label = "struct", .kind = .keyword, .detail = "keyword", .doc = "Value type" },
    .{ .label = "if", .kind = .keyword, .detail = "keyword", .doc = "Conditional" },
    .{ .label = "guard", .kind = .keyword, .detail = "keyword", .doc = "Early-exit condition" },
    .{ .label = "print", .kind = .func, .detail = "print(_:)", .doc = "Print to standard output" },
    .{ .label = "String", .kind = .type_name, .detail = "type", .doc = "Text type" },
};

const kt_cat = [_]Entry{
    .{ .label = "fun", .kind = .keyword, .detail = "keyword", .doc = "Declare a function" },
    .{ .label = "val", .kind = .keyword, .detail = "keyword", .doc = "Read-only property" },
    .{ .label = "var", .kind = .keyword, .detail = "keyword", .doc = "Mutable property" },
    .{ .label = "class", .kind = .keyword, .detail = "keyword", .doc = "Declare a class" },
    .{ .label = "if", .kind = .keyword, .detail = "keyword", .doc = "Conditional (also an expression)" },
    .{ .label = "when", .kind = .keyword, .detail = "keyword", .doc = "Multi-way branch" },
    .{ .label = "println", .kind = .func, .detail = "println(message)", .doc = "Print a line" },
    .{ .label = "listOf", .kind = .func, .detail = "listOf(...)", .doc = "Create an immutable list" },
};

const html_cat = [_]Entry{
    .{ .label = "div", .kind = .keyword, .detail = "<div>", .doc = "Generic block container" },
    .{ .label = "span", .kind = .keyword, .detail = "<span>", .doc = "Generic inline container" },
    .{ .label = "button", .kind = .keyword, .detail = "<button>", .doc = "Clickable button" },
    .{ .label = "input", .kind = .keyword, .detail = "<input>", .doc = "Form field" },
    .{ .label = "class", .kind = .ident, .detail = "attr", .doc = "CSS class names" },
    .{ .label = "id", .kind = .ident, .detail = "attr", .doc = "Unique element id" },
    .{ .label = "href", .kind = .ident, .detail = "attr", .doc = "Link URL" },
    .{ .label = "src", .kind = .ident, .detail = "attr", .doc = "Image or script URL" },
};

const css_cat = [_]Entry{
    .{ .label = "color", .kind = .ident, .detail = "property", .doc = "Foreground color" },
    .{ .label = "background", .kind = .ident, .detail = "property", .doc = "Background color or image" },
    .{ .label = "display", .kind = .ident, .detail = "property", .doc = "Layout mode (flex, grid, none, …)" },
    .{ .label = "flex", .kind = .ident, .detail = "value", .doc = "Flexible box layout" },
    .{ .label = "margin", .kind = .ident, .detail = "property", .doc = "Outer spacing" },
    .{ .label = "padding", .kind = .ident, .detail = "property", .doc = "Inner spacing" },
    .{ .label = "font-size", .kind = .ident, .detail = "property", .doc = "Text size" },
    .{ .label = "width", .kind = .ident, .detail = "property", .doc = "Used width" },
    .{ .label = "height", .kind = .ident, .detail = "property", .doc = "Used height" },
};

const sh_cat = [_]Entry{
    .{ .label = "if", .kind = .keyword, .detail = "keyword", .doc = "Conditional; ends with fi" },
    .{ .label = "then", .kind = .keyword, .detail = "keyword", .doc = "Start of an if body" },
    .{ .label = "fi", .kind = .keyword, .detail = "keyword", .doc = "End of an if" },
    .{ .label = "for", .kind = .keyword, .detail = "keyword", .doc = "Loop; ends with done" },
    .{ .label = "echo", .kind = .func, .detail = "echo args", .doc = "Print arguments" },
    .{ .label = "export", .kind = .keyword, .detail = "keyword", .doc = "Mark a variable for child processes" },
    .{ .label = "cd", .kind = .func, .detail = "cd dir", .doc = "Change directory" },
};

const sql_cat = [_]Entry{
    .{ .label = "SELECT", .kind = .keyword, .detail = "keyword", .doc = "Read rows" },
    .{ .label = "FROM", .kind = .keyword, .detail = "keyword", .doc = "Source table" },
    .{ .label = "WHERE", .kind = .keyword, .detail = "keyword", .doc = "Row filter" },
    .{ .label = "INSERT", .kind = .keyword, .detail = "keyword", .doc = "Add rows" },
    .{ .label = "UPDATE", .kind = .keyword, .detail = "keyword", .doc = "Change rows" },
    .{ .label = "DELETE", .kind = .keyword, .detail = "keyword", .doc = "Remove rows" },
    .{ .label = "JOIN", .kind = .keyword, .detail = "keyword", .doc = "Combine tables" },
    .{ .label = "ORDER BY", .kind = .keyword, .detail = "keyword", .doc = "Sort the result" },
};

const lua_cat = [_]Entry{
    .{ .label = "function", .kind = .keyword, .detail = "keyword", .doc = "Declare a function" },
    .{ .label = "local", .kind = .keyword, .detail = "keyword", .doc = "Local binding" },
    .{ .label = "end", .kind = .keyword, .detail = "keyword", .doc = "Close a block" },
    .{ .label = "if", .kind = .keyword, .detail = "keyword", .doc = "Conditional" },
    .{ .label = "then", .kind = .keyword, .detail = "keyword", .doc = "Start of an if body" },
    .{ .label = "print", .kind = .func, .detail = "print(...)", .doc = "Print values" },
    .{ .label = "pairs", .kind = .func, .detail = "pairs(t)", .doc = "Iterate a table" },
    .{ .label = "ipairs", .kind = .func, .detail = "ipairs(t)", .doc = "Iterate an array part" },
};

const generic_cat = [_]Entry{
    .{ .label = "true", .kind = .keyword, .detail = "value", .doc = "Boolean true" },
    .{ .label = "false", .kind = .keyword, .detail = "value", .doc = "Boolean false" },
    .{ .label = "null", .kind = .keyword, .detail = "value", .doc = "Null / empty value" },
};
