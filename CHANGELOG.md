# Changelog

All notable changes to **Orbit** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

Releases are published automatically when `VERSION` is bumped and pushed to the
**`2026-live`** branch (see `.github/workflows/release-2026-live.yml`).

## [Unreleased]

### Added
- Appearance settings (themes, cursor, shell)
- Full Help & Shortcuts reference
- Quit / close tab / shell-exit handling
- **Open Workspace** opens a native folder picker and starts a shell in that directory
- **Text color** presets in Appearance (independent of theme)
- **Search** finds text in the terminal (incl. scrollback) and file names in the opened folder (`Cmd/Ctrl+Shift+F`)
- **Plugins** home panel — browse, toggle, reload, and install bundled pack (hello, git, devtools, themes, workflow, keys)
- **Plugin shortcuts** — define `shortcut = "ctrl+shift+g"` or `[[bindings]]` in `plugin.toml` to run commands with your own key chords
- Bundled **keys** plugin as a starter for custom shortcuts / colors / themes (see `assets/plugins/README.md`)
- **macOS app icon** — `zig build run` packages `Orbit.app` with a Dock icon (no more generic "exec")
- **Global launch** — `zig build setup` installs shell integration so `zig build run` / `orbit` work from any directory
- **Detached launch** — `orbit` / `zig build run` open Orbit in the background and print `Orbit terminal opened successfully`

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
