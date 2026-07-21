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
- **Plugins** home panel — browse, toggle, reload, and install bundled pack (hello, git, devtools, themes, workflow)

### Changed
- Saved layout restore moved to palette command **Load Saved Workspace**
- Command palette & Appearance panels given more breathing room
- Status toast raised above the window edge (bottom-left)

## [2.1.0] — 2026-07-21

### Added
- Initial Orbit terminal: home screen, tabs, splits, workspaces
- GPU rendering, themes, plugins, command palette
- Config at `~/.config/orbit/config.toml`
