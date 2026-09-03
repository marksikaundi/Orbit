//! Bundled plugin pack — copy from the repo when available, else embed tools.

const std = @import("std");
const builtin = @import("builtin");
const paths = @import("../platform/paths.zig");
const dev_root = @import("../dev_root.zig");

pub fn install(allocator: std.mem.Allocator, io: std.Io, dest_dir: []const u8) usize {
    if (copyFromSource(allocator, io, dest_dir)) |n| {
        if (n > 0) return n;
    } else |_| {}
    return writeEmbeddedTools(io, dest_dir);
}

fn copyFromSource(allocator: std.mem.Allocator, io: std.Io, dest_dir: []const u8) !usize {
    const root = dev_root.resolve(allocator, io) orelse return error.NoSource;
    defer allocator.free(root);
    const src = try std.fmt.allocPrint(allocator, "{s}{c}assets{c}plugins", .{ root, std.fs.path.sep, std.fs.path.sep });
    defer allocator.free(src);
    if (!paths.pathExists(src)) return error.NoSource;
    return try copyTree(allocator, io, src, dest_dir);
}

fn copyTree(allocator: std.mem.Allocator, io: std.Io, src: []const u8, dest: []const u8) !usize {
    paths.ensureDir(dest);
    var dir = std.Io.Dir.openDirAbsolute(io, src, .{ .iterate = true }) catch return 0;
    defer dir.close(io);
    var n: usize = 0;
    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.name.len == 0 or entry.name[0] == '.') continue;
        if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) continue;
        const child_src = try std.fmt.allocPrint(allocator, "{s}{c}{s}", .{ src, std.fs.path.sep, entry.name });
        defer allocator.free(child_src);
        const child_dest = try std.fmt.allocPrint(allocator, "{s}{c}{s}", .{ dest, std.fs.path.sep, entry.name });
        defer allocator.free(child_dest);
        if (entry.kind == .directory) {
            n += try copyTree(allocator, io, child_src, child_dest);
        } else if (entry.kind == .file) {
            if (copyOneFile(io, child_src, child_dest)) {
                n += 1;
                chmodScript(child_dest);
            }
        }
    }
    return n;
}

fn copyOneFile(io: std.Io, src: []const u8, dest: []const u8) bool {
    if (std.fs.path.dirname(dest)) |dir| paths.ensureDir(dir);
    const in_file = std.Io.Dir.openFileAbsolute(io, src, .{}) catch return false;
    defer in_file.close(io);
    var buf: [4096]u8 = undefined;
    var reader = in_file.reader(io, &buf);
    const data = reader.interface.allocRemaining(std.heap.page_allocator, .limited(256 * 1024)) catch return false;
    defer std.heap.page_allocator.free(data);
    const out_file = std.Io.Dir.createFileAbsolute(io, dest, .{}) catch return false;
    defer out_file.close(io);
    out_file.writeStreamingAll(io, data) catch return false;
    return true;
}

fn writeEmbeddedTools(io: std.Io, dest_dir: []const u8) usize {
    const Item = struct { dir: []const u8, name: []const u8, body: []const u8 };
    const items = [_]Item{
        .{ .dir = "format", .name = "plugin.toml", .body = format_toml },
        .{ .dir = "format", .name = "run.sh", .body = format_sh },
        .{ .dir = "lint", .name = "plugin.toml", .body = lint_toml },
        .{ .dir = "lint", .name = "run.sh", .body = lint_sh },
        .{ .dir = "ai", .name = "plugin.toml", .body = ai_toml },
        .{ .dir = "ai", .name = "ask.sh", .body = ai_sh },
    };
    var n: usize = 0;
    for (items) |item| {
        if (writeDestFile(io, dest_dir, item.dir, item.name, item.body)) n += 1;
    }
    return n;
}

fn writeDestFile(io: std.Io, dest_dir: []const u8, plugin: []const u8, name: []const u8, body: []const u8) bool {
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const plugin_dir = std.fmt.bufPrint(&dir_buf, "{s}{c}{s}", .{ dest_dir, std.fs.path.sep, plugin }) catch return false;
    paths.ensureDir(plugin_dir);
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}{c}{s}", .{ plugin_dir, std.fs.path.sep, name }) catch return false;
    const file = std.Io.Dir.createFileAbsolute(io, path, .{}) catch return false;
    defer file.close(io);
    file.writeStreamingAll(io, body) catch return false;
    chmodScript(path);
    return true;
}

fn chmodScript(path: []const u8) void {
    if (builtin.os.tag == .windows) return;
    if (!std.mem.endsWith(u8, path, ".sh")) return;
    var buf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= buf.len) return;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    _ = std.c.chmod(buf[0..path.len :0], 0o755);
}

const format_toml =
    \\name = "format"
    \\version = "0.1.0"
    \\kind = "format"
    \\description = "Format the open file with your own tool — Prettier, zig fmt, or a fallback"
    \\
    \\[[commands]]
    \\id = "format.document"
    \\label = "Format: Document"
    \\hint = "ctrl+shift+i"
    \\action = "run"
    \\payload = "format"
    \\shortcut = "ctrl+shift+i"
    \\
    \\[tool]
    \\command = "sh"
    \\script = "run.sh"
    \\args = "{file}"
    \\stdin = "buffer"
    \\stdout = "replace"
    \\languages = "javascript,typescript,json,css,html,markdown,python,zig,go,rust,toml,yaml,shell,c,cpp"
    \\timeout_ms = 15000
    \\
    \\[hooks]
    \\on_load = "status:format plugin — edit run.sh to use your formatter"
    \\
;

const format_sh =
    \\#!/bin/sh
    \\set -eu
    \\FILE="${1:-untitled.txt}"
    \\BODY=$(cat)
    \\have() { command -v "$1" >/dev/null 2>&1; }
    \\ext="${FILE##*.}"
    \\if have prettier; then
    \\  case "$ext" in
    \\    js|mjs|cjs|jsx|ts|mts|cts|tsx|json|jsonc|css|scss|html|md|markdown|yml|yaml)
    \\      printf '%s' "$BODY" | prettier --stdin-filepath "$FILE" 2>/dev/null && exit 0
    \\      ;;
    \\  esac
    \\fi
    \\if have zig && [ "$ext" = "zig" ]; then
    \\  printf '%s' "$BODY" | zig fmt --stdin && exit 0
    \\fi
    \\if have rustfmt && [ "$ext" = "rs" ]; then
    \\  printf '%s' "$BODY" | rustfmt --emit stdout && exit 0
    \\fi
    \\if have gofmt && [ "$ext" = "go" ]; then
    \\  printf '%s' "$BODY" | gofmt && exit 0
    \\fi
    \\printf '%s' "$BODY" | sed 's/[[:space:]]*$//' | awk 'BEGIN{p=0} { if (NR>1) print ""; printf "%s", $0; p=1 } END { if (p) print "" }'
    \\
;

const lint_toml =
    \\name = "lint"
    \\version = "0.1.0"
    \\kind = "lint"
    \\description = "Lint the open file with your own tool — ESLint, ruff, or a built-in scan"
    \\
    \\[[commands]]
    \\id = "lint.file"
    \\label = "Lint: File"
    \\hint = "ctrl+shift+;"
    \\action = "run"
    \\payload = "lint"
    \\shortcut = "ctrl+shift+;"
    \\
    \\[tool]
    \\command = "sh"
    \\script = "run.sh"
    \\args = "{file}"
    \\stdin = "none"
    \\stdout = "overlay"
    \\parse = "unix"
    \\languages = "javascript,typescript,python,zig,go,rust,json,toml,shell"
    \\timeout_ms = 20000
    \\
    \\[hooks]
    \\on_load = "status:lint plugin — edit run.sh to use your linter"
    \\
;

const lint_sh =
    \\#!/bin/sh
    \\set -eu
    \\FILE="${1:-}"
    \\if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
    \\  echo "untitled:1:1: open a file in Orbit (Search → Files) then run Lint"
    \\  exit 0
    \\fi
    \\awk -v f="$FILE" '
    \\{
    \\  line = $0
    \\  if (match(line, /[ \t]+$/)) { printf "%s:%d:%d: trailing whitespace\n", f, NR, RSTART; n++ }
    \\  if (length(line) > 120) { printf "%s:%d:1: line longer than 120 characters (%d)\n", f, NR, length(line); n++ }
    \\  if (match(line, /TODO|FIXME|XXX/)) { printf "%s:%d:%d: leftover marker\n", f, NR, RSTART; n++ }
    \\}
    \\END { if (n == 0) printf "%s:1:1: no issues found\n", f }
    \\' "$FILE"
    \\
;

const ai_toml =
    \\name = "ai"
    \\version = "0.1.0"
    \\kind = "ai"
    \\description = "Ask a local model you own — Ollama by default, or edit ask.sh"
    \\
    \\[[commands]]
    \\id = "ai.explain"
    \\label = "AI: Explain"
    \\hint = "ctrl+shift+a"
    \\action = "run"
    \\payload = "explain"
    \\shortcut = "ctrl+shift+a"
    \\
    \\[[commands]]
    \\id = "ai.suggest"
    \\label = "AI: Suggest command"
    \\hint = "suggest"
    \\action = "run"
    \\payload = "suggest"
    \\
    \\[tool]
    \\command = "sh"
    \\script = "ask.sh"
    \\args = "{action}"
    \\stdin = "selection"
    \\stdout = "overlay"
    \\timeout_ms = 60000
    \\
    \\[hooks]
    \\on_load = "status:ai plugin — install ollama or edit ask.sh; never auto-runs"
    \\
;

const ai_sh =
    \\#!/bin/sh
    \\set -eu
    \\ACTION="${1:-explain}"
    \\BODY=$(cat)
    \\have() { command -v "$1" >/dev/null 2>&1; }
    \\if [ -z "$BODY" ]; then
    \\  echo "Select text in the terminal (or open a file) then run AI: Explain."
    \\  exit 0
    \\fi
    \\case "$ACTION" in
    \\  suggest) TASK="Suggest a safe shell command. One command, then one line of why. Do not execute anything." ;;
    \\  *) TASK="Explain this terminal output. What failed, and what to try next? Do not execute anything." ;;
    \\esac
    \\PROMPT="$TASK
    \\
    \\---
    \\$BODY
    \\---"
    \\if [ -n "${ORBIT_AI_BIN:-}" ]; then
    \\  printf '%s\n' "$PROMPT" | "$ORBIT_AI_BIN"
    \\  exit 0
    \\fi
    \\if have ollama; then
    \\  MODEL="${ORBIT_AI_MODEL:-llama3.2}"
    \\  printf '%s\n' "$PROMPT" | ollama run "$MODEL"
    \\  exit 0
    \\fi
    \\echo "No AI backend configured."
    \\echo "Install Ollama, set ORBIT_AI_BIN, or edit ~/.config/orbit/plugins/ai/ask.sh"
    \\
;
