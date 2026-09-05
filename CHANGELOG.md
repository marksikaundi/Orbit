# Changelog

All notable changes to **Orbit** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

Releases are published automatically when `VERSION` is bumped and pushed to the
**`2026-live`** branch (see `.github/workflows/release-2026-live.yml`).

## [Unreleased]

### Added
- **Prebuilt / signed installers** — `zig build package` writes `orbit-VERSION-os-arch` zip/tar (macOS `Orbit.app`). Release CI uploads archives. `scripts/sign-macos.sh` codesigns (and optionally notarizes) when `ORBIT_SIGN_IDENTITY` is set. `orbit update` prefers the matching GitHub asset, then falls back to a source rebuild
- **Ligatures** — programming sequences (`=>`, `!=`, `->`, `...`, …) cluster in the GPU renderer. `font_ligatures` in config. Optional `zig build -Dharfbuzz` for OpenType GSUB
- **Inline images** — Kitty graphics (`APC G`) and iTerm `OSC 1337;File=inline=1` (PNG / RGB / RGBA)
- **SSH manager** — `~/.ssh/config` plus `ssh.toml`: user, host, port, identity, jump, ControlMaster. Palette **SSH Reconnect** repeats the last command
- **Cloud sync** — `[sync] remote` and `orbit sync` / `pull` / `push` / `status` for `~/.config/orbit` (logs stay local). Palette Sync Config Now / Push / Pull

- **Unicode text** — on-demand glyph cache with fallback fonts, wide cells (CJK / emoji), synthesized box-drawing for TUI apps, and UTF-8 clipboard copy
- **xterm mouse** — DECSET 1000 / 1002 / 1003 / 1006 so vim, less, tmux, htop, and lazygit receive clicks and wheel events (Shift still selects)
- **Selection** — double-click word, triple-click line, Alt-drag rectangle
- **Clickable URLs** — OSC 8 hyperlinks plus Cmd/Ctrl-click on `http(s)://` text
- **OSC 0/2 titles** — tab and window titles follow the shell
- **Live cwd** — OSC 7 plus an `orbit.sh` hook so Save Workspace records `cd`
- **Restore last session** — auto-saves `__last__` on quit; `restore_last_workspace` reopens it on launch; recents in `session.toml`
- **SSH host list** — palette SSH reads `~/.ssh/config` Host entries
- **Split UX** — drag the divider, close pane (`Ctrl+Shift+K`), focus previous (`Ctrl+PageUp`), zoom pane (`Ctrl+Shift+Z`)
- **Search** — F2 case-sensitive, F3 regex-lite
- **File drop** — drag a path from Finder / Explorer into the shell
- **Close confirm** — quit / close tab / close pane asks before killing sessions
- **Desktop notifications** — OSC 9/99 and BEL notify the OS when Orbit is unfocused
- **IME** — composed Unicode already goes to the PTY; glyphs now render so CJK / dead keys are visible

- **`orbit update`** — people on an older install can upgrade from the terminal: checks GitHub Releases, fetches the latest `vX.Y.Z` tag, rebuilds, and refreshes the launcher (`orbit update --check` to only report). Palette: **Check for Updates** / **Update Orbit**
- **`--help` catalog** — `orbit --help`, `orbit help`, and (after setup) a bare `--help` in a new terminal list every launch flag, `zig build` step, environment variable, shortcut, plugin command, and developer shell command
- **User docs hub** — `docs/` covers how to use and configure every feature (home, config, appearance, keybindings, palette, tabs, workspaces, search/editor, plugins, CLI/IDEs)
- **Custom keybindings** — Ghostty-compatible `keybind = trigger=action` in `config.toml` (unbind, clear, sequences, `text:` / `csi:` / `esc:`, `performable:`, chained actions). Defaults match the previous built-in chords.
- **IDE connect** — `orbit ide-setup` registers Orbit as the external terminal in Cursor, VS Code, VSCodium, and Windsurf, and installs an **Open in Orbit Terminal** explorer command
- CLI flags editors already send: `--working-directory`, `-e` / `--command`, positional folder (Ghostty / Alacritty / Kitty compatible)
- macOS `open -a Orbit.app /folder` opens a shell in that folder
- Appearance settings (themes, cursor, shell)
- **Ghostty-style look** — compact / comfortable / airy / glass (padding, line spacing, opacity) plus prompt styles (ghostty ❯, minimal, starship) in Appearance
- Catppuccin Mocha and Tokyo Night themes
- Full Help & Shortcuts reference
- Quit / close tab / shell-exit handling
- **Open Workspace** opens a native folder picker and starts a shell in that directory
- **Text color** presets in Appearance (independent of theme)
- **Search** finds text in the terminal, file names, or **code inside files** (`Cmd/Ctrl+Shift+F`; Tab switches Terminal / Files / Code). **⌘/Ctrl+F** in the editor finds in the open file.
- **In-file editor with autocomplete** — open a file and type; keywords, common APIs, and names already in the file show a popup with signature and a short meaning (Java, JavaScript, Python, and the other highlighted languages)
- **Plugins you own** — kinds (`format`, `lint`, `ai`, `commands`, `theme`, `keys`) plus a `[tool]` that runs *your* command/script. Format the open file, lint with unix diagnostics, or ask a local model. Enablement is persisted. Bundled **format**, **lint**, and **ai** plugins (edit `run.sh` / `ask.sh`)

### Fixed
- Full-screen apps (`vi` / `vim`, `less`, `htop`) restore the shell when they quit (alternate screen buffer)
- Shells now advertise `TERM=xterm-256color` so editors can use syntax colors
- **macOS app icon** — `zig build run` packages `Orbit.app` with a Dock icon (no more generic "exec")
- **Global launch** — `zig build setup` installs shell integration so `zig build run` / `orbit` work from any directory
- **Detached launch** — `orbit` / `zig build run` open Orbit in the background and print `Orbit terminal opened successfully`
- **Security scan** — `zig build security-scan` checks `src/`, `scripts/`, and plugins for secrets and injection risks; CI runs on every push/PR; risky plugin inserts warn at load and run time
- **UI freeze under load** — PTY output is drained a bounded amount per frame; scrollback eviction is O(1); CSI scroll/insert repeats are clamped; tab close never blocks on `waitpid`

### Changed
- Saved layout restore moved to palette command **Load Saved Workspace**
- Command palette & Appearance panels given more breathing room
- Status toast raised above the window edge (bottom-left)
- Status toast is ephemeral: shows only on events (save, theme, errors, terminal notices) and auto-hides after a few seconds
- Terminal output can surface toasts for file create/edit/save/delete lines and `error:` / `failed` messages; OSC 9 / OSC 99 also drive the toast
- Shared shortcut table so Command Palette hints match real keybindings (`Ctrl+W` closes tab, etc.)
- Ctrl+A–Z (except app chords) are forwarded to the shell again — interrupt, EOF, and readline work
- Closing a tab no longer blocks the UI (bounded PTY teardown); folder picker pumps events while open

## [2.1.0] — 2026-07-21

### Added
- Initial Orbit terminal: home screen, tabs, splits, workspaces
- GPU rendering, themes, plugins, command palette
- Config at `~/.config/orbit/config.toml`
