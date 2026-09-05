//! Launch CLI — directory/command flags used by IDEs, plus help / version / ide-setup.

const std = @import("std");
const version = @import("../version.zig");

pub const Action = enum { run, help, version, ide_setup, update, sync };

pub const SyncMode = enum { status, pull, push, sync };

pub const ParseError = error{
    MissingValue,
    UnknownArgument,
    OutOfMemory,
};

pub const Launch = struct {
    action: Action = .run,
    /// Absolute or as-given working directory for the first shell.
    cwd: ?[]u8 = null,
    title: ?[]u8 = null,
    /// `-e` / `--command` argv (owned slices).
    execute: [][]u8 = &.{},
    wait_after_command: bool = false,
    skip_home: bool = false,
    /// `ide-setup --editor` value (null = all detected).
    editor: ?[]u8 = null,
    /// `orbit update --check` — report only.
    update_check: bool = false,
    /// `orbit update --force` — overwrite a dirty source tree.
    update_force: bool = false,
    /// Hidden Windows helper: finish rebuild from a copied binary.
    update_rebuild: bool = false,
    /// `orbit sync` / pull / push / status
    sync_mode: SyncMode = .sync,

    pub fn deinit(self: *Launch, allocator: std.mem.Allocator) void {
        if (self.cwd) |p| allocator.free(p);
        if (self.title) |t| allocator.free(t);
        if (self.editor) |e| allocator.free(e);
        for (self.execute) |a| allocator.free(a);
        if (self.execute.len > 0) allocator.free(self.execute);
        self.* = undefined;
    }
};

/// `args[0]` is argv0. Remaining tokens are flags / positionals.
pub fn parse(allocator: std.mem.Allocator, args: []const []const u8) ParseError!Launch {
    var out: Launch = .{};
    errdefer out.deinit(allocator);

    if (args.len <= 1) return out;

    var i: usize = 1;
    var execute_at: ?usize = null;

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (execute_at != null) break;

        if (i == 1 and isIdeSetup(arg)) {
            out.action = .ide_setup;
            continue;
        }
        if (i == 1 and isUpdateCommand(arg)) {
            out.action = .update;
            continue;
        }
        if (i == 1 and isSyncCommand(arg)) {
            out.action = .sync;
            continue;
        }
        if (i == 1 and isRebuildCommand(arg)) {
            out.action = .update;
            out.update_rebuild = true;
            continue;
        }
        if (out.action == .update) {
            if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                out.action = .help;
                return out;
            }
            if (std.mem.eql(u8, arg, "--check") or std.mem.eql(u8, arg, "-c")) {
                out.update_check = true;
                continue;
            }
            if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
                out.update_force = true;
                continue;
            }
            if (out.update_rebuild) {
                try setOwned(&out.cwd, allocator, arg);
                continue;
            }
            return error.UnknownArgument;
        }
        if (out.action == .sync) {
            if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                out.action = .help;
                return out;
            }
            if (std.mem.eql(u8, arg, "pull")) {
                out.sync_mode = .pull;
                continue;
            }
            if (std.mem.eql(u8, arg, "push")) {
                out.sync_mode = .push;
                continue;
            }
            if (std.mem.eql(u8, arg, "status")) {
                out.sync_mode = .status;
                continue;
            }
            if (std.mem.eql(u8, arg, "sync")) {
                out.sync_mode = .sync;
                continue;
            }
            return error.UnknownArgument;
        }
        if (i == 1 and isHelpCommand(arg)) {
            out.action = .help;
            return out;
        }
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            out.action = .help;
            return out;
        }
        if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--version")) {
            out.action = .version;
            return out;
        }
        if (std.mem.eql(u8, arg, "--wait-after-command") or std.mem.eql(u8, arg, "--wait-after-command=true")) {
            out.wait_after_command = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--wait-after-command=false")) {
            out.wait_after_command = false;
            continue;
        }
        if (takeEq(arg, "--working-directory")) |v| {
            try setCwd(&out, allocator, v);
            continue;
        }
        if (takeEq(arg, "--workdir")) |v| {
            try setCwd(&out, allocator, v);
            continue;
        }
        if (takeEq(arg, "--directory")) |v| {
            try setCwd(&out, allocator, v);
            continue;
        }
        if (takeEq(arg, "--cwd")) |v| {
            try setCwd(&out, allocator, v);
            continue;
        }
        if (takeEq(arg, "--title")) |v| {
            try setOwned(&out.title, allocator, v);
            continue;
        }
        if (takeEq(arg, "--editor")) |v| {
            try setOwned(&out.editor, allocator, v);
            continue;
        }

        if (isCwdFlag(arg) or std.mem.eql(u8, arg, "-d")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            try setCwd(&out, allocator, args[i]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--title") or std.mem.eql(u8, arg, "-t")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            try setOwned(&out.title, allocator, args[i]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--editor")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            try setOwned(&out.editor, allocator, args[i]);
            continue;
        }
        if (std.mem.eql(u8, arg, "-e") or std.mem.eql(u8, arg, "--command") or std.mem.eql(u8, arg, "--")) {
            execute_at = i + 1;
            break;
        }
        if (arg.len > 0 and arg[0] == '-') {
            return error.UnknownArgument;
        }

        // Positional path: folder to open (or a file — use its parent).
        try setCwd(&out, allocator, arg);
    }

    if (execute_at) |start| {
        if (start < args.len) {
            const n = args.len - start;
            const owned = try allocator.alloc([]u8, n);
            var filled: usize = 0;
            errdefer {
                for (owned[0..filled]) |a| allocator.free(a);
                allocator.free(owned);
            }
            for (args[start..], 0..) |a, k| {
                owned[k] = try allocator.dupe(u8, a);
                filled = k + 1;
            }
            out.execute = owned;
            out.skip_home = true;
        }
    }

    return out;
}

/// Full command catalog printed by `orbit --help`, `orbit -h`, and `orbit help`.
/// After `zig build setup`, a new terminal can also run `--help` (shell helper).
pub const help_text =
    \\Usage:
    \\  orbit [path] [options]
    \\  orbit help | --help | -h
    \\  orbit --version | -V
    \\  orbit update [--check] [--force]
    \\  orbit sync [pull|push|status]
    \\  orbit ide-setup [--editor cursor|code|codium|windsurf|all]
    \\
    \\After `zig build setup`, open a new terminal and run `--help` or `orbit --help`.
    \\
    \\Commands:
    \\  (none)                       Open the home screen
    \\  path                         Folder → shell there. File → editor + shell in that folder
    \\  help, -h, --help             Show this catalog
    \\  -V, --version                Print version
    \\  update                       Install the latest GitHub release (git pull + rebuild)
    \\  update --check               Report whether a newer release exists
    \\  update --force               Overwrite local source changes, then update
    \\  sync                         Git pull --rebase then push ~/.config/orbit
    \\  sync pull|push|status        One-way or status only
    \\  ide-setup                    Register Orbit as the external terminal in IDEs
    \\
    \\Launch options:
    \\  -d, --working-directory DIR  Working directory (Alacritty / Ghostty / VS Code)
    \\      --workdir DIR            Same (Konsole)
    \\      --directory DIR          Same (Kitty)
    \\      --cwd DIR                Same
    \\  -e, --command CMD [args…]    Run this command instead of a login shell
    \\  --                           Rest of argv is the command
    \\      --wait-after-command     Keep a shell open after -e exits
    \\  -t, --title TITLE            First tab title
    \\
    \\  `=` form works: --working-directory=/tmp
    \\
    \\Examples:
    \\  orbit                        Home screen
    \\  orbit ~/code/api             Shell in that folder
    \\  orbit app.js                 Editor + shell in that file’s folder
    \\  orbit --working-directory=/tmp
    \\  orbit -e git status
    \\  orbit --wait-after-command -e make test
    \\  orbit update                 Fetch the latest release (prebuilt, else rebuild)
    \\  orbit update --check         Only print current vs latest
    \\  orbit sync                   Push/pull config, workspaces, ssh.toml
    \\  orbit ide-setup              Cursor, VS Code, VSCodium, Windsurf if found
    \\  orbit ide-setup --editor cursor
    \\
    \\IDEs (Cursor, VS Code, VSCodium, Windsurf, …):
    \\  orbit ide-setup              Set Orbit as the *external* terminal and install
    \\                               “Open in Orbit Terminal”. The editor’s built-in
    \\                               panel (Ctrl/Cmd+`) is left alone.
    \\
    \\Developer — zig build (from the Orbit repo, or any folder after setup):
    \\  zig build                    Compile → zig-out/bin/orbit  (orbit.exe on Windows)
    \\  zig build run                Build and launch detached
    \\  zig build run-fg             Build and launch in the foreground (logs here)
    \\  zig build setup              Install global `orbit` + shell helper (`--help`)
    \\  zig build test               Run unit tests
    \\  zig build package            Release archive (zip / tar / Orbit.app)
    \\  zig build -Dharfbuzz         Link system HarfBuzz for OpenType ligatures
    \\  zig build security-scan      Scan src/, scripts/, plugins for secrets / injection
    \\  zig build -Doptimize=ReleaseSafe
    \\                               Optimized build
    \\  zig build --help             Zig’s own list of build steps
    \\
    \\  ./scripts/bump-version.sh patch|minor|major
    \\                               Bump VERSION for a 2026-live release
    \\
    \\Environment:
    \\  ORBIT_FOREGROUND=1           Keep Orbit attached to this terminal (live logs)
    \\  ORBIT_SOURCE_ROOT            Override the Orbit source tree
    \\  ORBIT_TERMINAL=1             Set automatically inside Orbit shells
    \\  ORBIT_PROMPT                 ghostty | minimal | starship | default
    \\  ORBIT_AI_BIN                 Your AI CLI (prompt on stdin); never auto-runs
    \\  ORBIT_AI_MODEL               Ollama model name (default llama3.2)
    \\  ORBIT_IDE                    Set by editors when they launch Orbit
    \\
    \\In the Orbit window:
    \\  Home  Enter / 1              New terminal
    \\        O / 2                  Open folder as workspace
    \\        P / 3                  Command palette
    \\        S / 4                  Settings / appearance
    \\        L / 5                  Plugins
    \\        H / 6                  Help & shortcuts overlay
    \\        Q / 7                  Quit
    \\  Ctrl+Shift+P                 Command palette (type to filter)
    \\  Ctrl+Shift+T / W             New tab / close tab
    \\  Ctrl+Tab / Ctrl+Shift+Tab    Next / previous tab
    \\  Ctrl+Shift+D / E             Split right / down
    \\  Ctrl+PageDown                Focus next pane
    \\  Ctrl/Cmd+Shift+F             Search terminal, file names, or code
    \\  Ctrl/Cmd+Shift+C / V         Copy / paste
    \\  Ctrl/Cmd+= / - / 0           Font larger / smaller / reset
    \\  Ctrl+Shift+O / S             Open folder / save workspace
    \\  Ctrl+Shift+H                 Return to home
    \\  Ctrl+Q / Cmd+Q               Quit
    \\  Palette → Open File          Syntax-highlighted editor (then ⌘/Ctrl+S to save)
    \\  Palette → Reload Config      Re-read ~/.config/orbit/config.toml
    \\  Palette → Reload Plugins     Re-read ~/.config/orbit/plugins/
    \\  Palette → Check for Updates  Compare this build to GitHub Releases
    \\  Palette → Update Orbit       Same as `orbit update` (run from a shell)
    \\  Palette → SSH… / Reconnect   ~/.ssh/config + ssh.toml (keys, jump, mux)
    \\  Palette → Sync Config        `orbit sync` (needs [sync] remote)
    \\
    \\Developer commands in a shell tab (also on the palette if plugins are installed):
    \\  git status                   Working tree
    \\  git diff                     Unstaged changes
    \\  git log --oneline -20        Recent commits
    \\  git branch -vv               Local branches
    \\  git pull / git push          Sync with remote
    \\  git stash push -u            Stash including untracked
    \\  pwd                          Current directory
    \\  ls -la                       List files
    \\  find . -maxdepth 2 | head    Shallow tree
    \\  du -sh ./*                   Disk use in this folder
    \\  lsof -nP -iTCP -sTCP:LISTEN  Listening ports
    \\  ssh host                     Remote shell (palette → SSH… prompts for host)
    \\
    \\Plugins (home → L, then I to install the bundled pack; Ctrl+Shift+P to run):
    \\  Git: Status, Diff, Log, Branches, Pull, Push, Stash
    \\  Dev: Print cwd, List files, Tree, Clear, Disk, Ports, Path & shell
    \\  Workflow: New Tab, Split Right, Open/Save Workspace, Search
    \\  Format: Document             Ctrl+Shift+I  (needs a file open)
    \\  Lint: File                   Ctrl+Shift+;  (needs a file open)
    \\  AI: Explain                  Ctrl+Shift+A  (selection; never auto-runs)
    \\  AI: Suggest command          palette
    \\
    \\Config (Unix → Windows):
    \\  ~/.config/orbit/config.toml            %APPDATA%\orbit\config.toml
    \\  ~/.config/orbit/plugins/<name>/        %APPDATA%\orbit\plugins\<name>\
    \\  ~/.config/orbit/workspaces/<name>.toml %APPDATA%\orbit\workspaces\
    \\  ~/.config/orbit/logs/orbit.log         %APPDATA%\orbit\logs\orbit.log
    \\
    \\Docs:
    \\  docs/           User guide (every feature)
    \\  INSTALL.md      Build and install
    \\  CONTRIBUTING.md How to contribute
    \\  how-to-use.md   Short index into docs/
    \\
;

pub fn printHelp() void {
    std.debug.print("Orbit {s} — stay in the flow\n\n", .{version.tagged});
    std.debug.print("{s}", .{help_text});
}

fn isHelpCommand(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "help");
}

fn isIdeSetup(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "ide-setup") or std.mem.eql(u8, arg, "--ide-setup");
}

fn isUpdateCommand(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "update") or std.mem.eql(u8, arg, "--update");
}

fn isSyncCommand(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "sync") or std.mem.eql(u8, arg, "--sync");
}

fn isRebuildCommand(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "--orbit-rebuild");
}

fn isCwdFlag(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "--working-directory") or
        std.mem.eql(u8, arg, "--workdir") or
        std.mem.eql(u8, arg, "--directory") or
        std.mem.eql(u8, arg, "--cwd");
}

fn takeEq(arg: []const u8, flag: []const u8) ?[]const u8 {
    if (arg.len <= flag.len + 1) return null;
    if (!std.mem.startsWith(u8, arg, flag)) return null;
    if (arg[flag.len] != '=') return null;
    return arg[flag.len + 1 ..];
}

fn setCwd(out: *Launch, allocator: std.mem.Allocator, path: []const u8) !void {
    try setOwned(&out.cwd, allocator, path);
    out.skip_home = true;
}

fn setOwned(slot: *?[]u8, allocator: std.mem.Allocator, value: []const u8) !void {
    if (slot.*) |old| allocator.free(old);
    slot.* = try allocator.dupe(u8, value);
}
