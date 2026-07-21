# Orbit

[![Version](https://img.shields.io/github/v/release/marksikaundi/Orbit?style=for-the-badge&label=VERSION&color=1a1b1e&labelColor=0b0c0f)](https://github.com/marksikaundi/Orbit/releases/latest)
[![2026-live](https://img.shields.io/badge/branch-2026--live-3d8bfd?style=for-the-badge&labelColor=0b0c0f)](https://github.com/marksikaundi/Orbit/tree/2026-live)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg?style=for-the-badge&labelColor=0b0c0f)](LICENSE)

**A fast, lightweight, project-centric terminal emulator built in Zig.**

> Stay in the flow.

Orbit is a GPU-accelerated terminal inspired by Ghostty’s performance focus, with one core idea: keep developers in the flow by organizing everything around projects. Unlike traditional terminals that only launch shells, Orbit remembers workspaces, restores sessions, and stays out of your way.

---

## About

> Keep developers in the flow by organizing everything around projects.

### Core values

- Fast
- Lightweight
- Beautiful
- Project-centric
- Privacy-first
- Extensible
- Cross-platform

### Design principles

1. Performance first
2. Minimal UI
3. No unnecessary features
4. GPU-accelerated rendering
5. Native experience
6. Stable architecture
7. Memory safety through Zig
8. Project-aware workflows

---

## Philosophy

| Terminal | Focus |
| -------- | ----- |
| Ghostty | Speed |
| Warp | UX |
| WezTerm | Configuration |
| **Orbit** | **Projects** |

Everything revolves around the developer’s workflow.

---

## Features

### Terminal foundations

- Startup home screen (welcome, logo, version, quick actions)
- GPU-rendered text with dirty-cell redraws
- POSIX PTY (Linux/macOS) and ConPTY (Windows)
- Full ANSI parsing (CSI, OSC, SGR, DEC, DCS, UTF-8)
- Colors, cursor, scrolling, selection, and clipboard
- Tabs, split panes, search, themes, and transparency
- TOML configuration with live reload (no restart)

### Orbit Workspaces

Projects are first-class. Each workspace can remember:

- Working directory
- Tabs and splits
- Shell and environment
- Layout and restore state

Example workspaces: Backend, Frontend, Production, University.

### Later

- **Optional AI assistant** — offline or cloud; explain errors and suggest commands; never executes automatically

---

## Status

**Phases 1–6 are implemented.** Terminal foundations through the command palette, plus a manifest-based plugin system (commands, themes, hooks). Optional AI assistant is next (Phase 7). See [roamap.md](roamap.md).

---

## Tech stack

| Layer | Choice |
| ----- | ------ |
| Language | Zig |
| Graphics | OpenGL (initial), WebGPU (future) |
| Windowing | GLFW |
| Fonts | SF Mono via stb_truetype (FreeType/HarfBuzz later) |
| Shell I/O | POSIX PTY, Windows ConPTY |
| Configuration | TOML |
| Testing | Zig Test (`zig build test`, suites in `src/tests/`) |
| Build | Zig Build |

### Why Zig?

- Tiny binaries
- Excellent C interoperability
- Explicit memory management
- Strong performance and cross-compilation
- Well suited to systems programming

---

## Architecture

Every layer is isolated:

```text
Application
    ↓
Window
    ↓
Input
    ↓
PTY
    ↓
ANSI Parser
    ↓
Screen Buffer
    ↓
Renderer
    ↓
GPU
```

### Core modules

| Module | Responsibilities |
| ------ | ---------------- |
| **Window** | Create/resize window, clipboard, DPI, cursor, monitor |
| **PTY** | Create shell, send input, receive output, resize (Linux, macOS, Windows) |
| **ANSI Parser** | CSI, OSC, SGR, DEC, DCS, UTF-8 → screen operations |
| **Screen Buffer** | Cells: character, fg/bg, bold/italic/underline/blink/reverse, hyperlink, dirty flag |
| **Renderer** | Glyph cache, texture atlas, vertex buffers, cursor, selection, background; redraw dirty cells only |
| **Input** | Keyboard, mouse, clipboard, shortcuts, IME |
| **Configuration** | `config.toml` with automatic reload |

### GPU renderer pipeline

```text
Window → Renderer → Glyph Cache → Vertex Buffer → GPU → Screen
```

---

## Performance targets

| Metric | Target |
| ------ | ------ |
| Startup | &lt; 50ms |
| Idle memory | &lt; 30MB |
| Input latency | &lt; 5ms |
| Frame rate | 144+ FPS |

Benchmarks will cover launch, memory, frame time, parser speed, render speed, and PTY latency.

---

## Repository layout

Planned structure:

```text
src/
    main.zig
    app/
    renderer/
    parser/
    terminal/
    workspace/
    config/
    platform/
    window/
    pty/
    font/
    clipboard/
    ui/
    plugins/
    utils/
    tests/
assets/
docs/
build.zig
```

---

## Configuration

Orbit watches config changes and reloads automatically — no restart required.

Example `config.toml`:

```toml
font = "JetBrains Mono"
font_size = 14
theme = "Orbit Dark"
opacity = 0.95
cursor = "beam"
padding = 10
```

---

## Platforms

| Platform | Shell backend |
| -------- | ------------- |
| Linux | Native PTY |
| macOS | Native PTY |
| Windows | ConPTY |

All platforms share one PTY interface.

---

## Development phases

| Phase | Focus |
| ----- | ----- |
| 1 | MVP — window, PTY, shell I/O, text render, keyboard (no tabs/plugins/settings) |
| 2 | ANSI, colors, resize, scroll, cursor, clipboard, selection |
| 3 | Tabs, splits, search, themes, config, transparency |
| 4 | Orbit Workspaces |
| 5 | Command palette |
| 6 | Plugin system |
| 7 | Optional AI assistant |

---

## Release roadmap

| Version | Milestone |
| ------- | --------- |
| v0.1 | Basic terminal |
| v0.2 | ANSI support |
| v0.3 | Themes |
| v0.4 | Tabs |
| v0.5 | Splits |
| v0.6 | Workspaces |
| v0.7 | Plugins |
| v0.8 | Search |
| v0.9 | Performance |
| v1.0 | Stable release |

### Future ideas

SSH manager, cloud sync, workspace sharing, remote development, session recording, image protocol, GPU effects, multi-cursor, terminal replay, command timeline.

See [roamap.md](roamap.md) for full phase detail.

---

## Testing

- Unit tests — parser, renderer, PTY
- Integration tests
- Performance and rendering tests

---

## Getting started

Requirements:

- [Zig](https://ziglang.org/) **0.16+**
- [GLFW](https://www.glfw.org/) 3.x (e.g. `brew install glfw` on macOS)

```bash
zig build          # produces zig-out/bin/orbit
zig build run      # build and launch
zig build test     # unit tests (screen + parser)
```

Optional config: copy `assets/config.example.toml` to `~/.config/orbit/config.toml`.

### Shortcuts (Phases 2–5)

| Shortcut | Action |
| -------- | ------ |
| `Ctrl+Shift+H` | Go to home screen |
| `Ctrl+Shift+P` | Command palette |
| `Ctrl+Shift+T` | New tab |
| `Ctrl+Shift+W` | Close tab |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Next / previous tab |
| `Ctrl+Shift+]` / `[` | Next / previous tab |
| `Ctrl+Shift+D` | Split horizontal |
| `Ctrl+Shift+E` | Split vertical |
| `Ctrl+PageDown` | Focus next pane |
| `Ctrl+Shift+F` | Search |
| `Ctrl/Cmd+Shift+C` | Copy selection |
| `Ctrl/Cmd+Shift+V` | Paste |
| `Ctrl/Cmd+=` | Font larger |
| `Ctrl/Cmd+-` | Font smaller |
| `Ctrl/Cmd+0` | Font reset (2.0) |
| `Ctrl+Shift+O` | Open folder as workspace (native picker) |
| `Ctrl+Shift+S` | Save current layout as workspace |
| Drag + release | Select text (copies on release) |
| Scroll / PageUp/Down | Scrollback |

Workspaces are stored in `~/.config/orbit/workspaces/<name>.toml`.

Palette commands include New Tab, Split Right/Down, Open Workspace (folder), Load Saved Workspace, Save Workspace, SSH, Theme, Font size, Settings, Reload Config/Plugins, and any commands contributed by plugins.

### Plugins (Phase 6)

Install a plugin by copying a folder with `plugin.toml` into `~/.config/orbit/plugins/<name>/`:

```bash
mkdir -p ~/.config/orbit/plugins/hello
cp assets/plugins/hello/plugin.toml ~/.config/orbit/plugins/hello/
```

Then **Ctrl+Shift+P** → “Reload Plugins” (or restart Orbit). Plugin commands and themes appear in the palette.

Logging levels planned: Debug, Info, Warn, Error, Trace.

---

## Contributing

The project is early. Feedback on architecture and the roadmap in [roamap.md](roamap.md) is welcome. Contribution guidelines will land with the first buildable release.

---

## License

Orbit is licensed under the [Apache License, Version 2.0](LICENSE).

Copyright 2026 Mark Sikaundi

You may use, modify, and distribute Orbit for open source or commercial
purposes, subject to the terms of the Apache License 2.0. Contributions
submitted to this project are licensed under the same terms unless
explicitly stated otherwise. See [NOTICE](NOTICE) for attribution details.

---

**Orbit — Stay in the flow.**
