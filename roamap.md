# Orbit Terminal
### A Fast, Lightweight, Project-Centric Terminal Emulator Built in Zig

---

# Vision

Orbit is a modern GPU-accelerated terminal emulator focused on one idea:

> **Keep developers in the flow by organizing everything around projects.**

Unlike traditional terminals that simply launch shells, Orbit remembers workspaces, restores sessions, provides intelligent project management, and remains incredibly fast.

Core values:

- Fast
- Lightweight
- Beautiful
- Project-centric
- Privacy-first
- Extensible
- Cross-platform

---

# Design Principles

1. Performance First
2. Minimal UI
3. No unnecessary features
4. GPU accelerated rendering
5. Native experience
6. Stable architecture
7. Memory safety through Zig
8. Project-aware workflows

---

# Why Zig?

- Tiny binaries
- Excellent C interoperability
- Explicit memory management
- Great performance
- Cross compilation
- Modern language
- Perfect for systems programming

---

# Technology Stack

Language:
- Zig

Graphics:
- OpenGL (initial)
- WebGPU (future)

Windowing:
- GLFW

Fonts:
- FreeType
- HarfBuzz (later)

Shell:
- POSIX PTY
- Windows ConPTY

Configuration:
- TOML
- Ghostty-compatible `keybind = trigger=action`

Testing:
- Zig Test

Build:
- Zig Build

---

# Repository Layout

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
docs/          user guide — how to use and configure every feature
               (start at docs/README.md)

build.zig

---

# High-Level Architecture

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

Every layer is isolated.

---

# Core Modules

## Window

Responsibilities

- create window
- resize
- clipboard
- dpi
- cursor
- monitor

---

## PTY

Linux
macOS
Windows

Responsibilities  for ot

- create shell
- send input
- receive output
- resize terminal

---

## ANSI Parser

Parses

- CSI
- OSC
- SGR
- DEC
- DCS
- UTF-8

Outputs

Screen operations

---

## Screen Buffer

Stores

Cell

Character

Foreground

Background

Bold

Italic

Underline

Blink

Reverse

Hyperlink

Dirty flag

---

## Renderer

Responsibilities

- glyph cache
- texture atlas
- vertex buffers
- cursor
- selection
- background

Only redraw dirty cells.

---

## Input

Keyboard

Mouse

Clipboard

Shortcuts

IME support

---

## Configuration

config.toml

Example

font="JetBrains Mono"

font_size=14

theme="Orbit Dark"

opacity=0.95

cursor="beam"

padding=10

---

# Development Phases

## Phase 1 ✅

Minimum Viable Terminal

Goals

- open window
- create PTY
- launch shell
- receive shell output
- render text
- keyboard input

No tabs

No plugins

No settings

---

## Phase 2 ✅

Terminal Features

- ANSI parser
- colors
- resizing
- scrolling
- cursor
- clipboard
- selection

---

## Phase 3 ✅

Modern Features

- tabs
- split panes
- search
- themes
- config
- transparency

---

## Phase 4 ✅

Orbit Workspaces

Projects become first-class citizens.

Each workspace remembers

- cwd
- tabs
- splits
- shell
- environment
- layout

Example

Backend

Frontend

Production

University

---

## Phase 5 ✅

Command Palette

CTRL+SHIFT+P

Commands

New Tab

Split Right

Open Workspace

SSH

Theme

Font

Settings

---

## Phase 6 ✅

Plugin System

Plugin API

Commands

Themes

Format / lint / AI tools (user-owned `[tool]`)

Renderer hooks

Workspace hooks

Lifecycle

---

## Phase 7 ✅

AI Assistant (plugin)

Optional

Your CLI (Ollama / `ORBIT_AI_BIN`)

Explain errors

Suggest commands

Never execute automatically

---

# GPU Renderer

Pipeline

Window

↓

Renderer

↓

Glyph Cache

↓

Vertex Buffer

↓

GPU

↓

Screen

---

# Performance Targets

Startup

<50ms

Idle Memory

<30MB

Input Latency

<5ms

FPS

144+

---

# Workspace Engine

Workspace

contains

tabs

splits

terminal sessions

environment

history

layout

restore state

Orbit's biggest feature.

---

# Plugin API

Plugin

↓

Orbit

↓

Commands

Renderer

Workspace

Config

Events

---

# Configuration

Orbit watches config changes.

Reload automatically.

No restart required.

---

# Logging

Levels

Debug

Info

Warn

Error

Trace

---

# Cross Platform

Linux

Native PTY

macOS

Native PTY

Windows

ConPTY

Shared interface

---

# Testing

Unit Tests

Parser

Renderer

PTY

Integration Tests

Performance Tests

Rendering Tests

---

# Benchmarks

Target

Launch

Memory

Frame Time

Parser Speed

Render Speed

PTY Latency

---

# Release Roadmap

v0.1 – v1.0 shipped the foundations (terminal → workspaces → plugins).

The next releases close daily-use gaps. Order is what users hit first, not what is most impressive.

---

## Phase 8 — Daily completeness (v2.2) — shipped

Table-stakes terminal behavior. Without these, Orbit fails in the first hour.

| Item | Status |
| --- | --- |
| Unicode glyph cache + fallback fonts | Shipped — on-demand atlas, fallbacks, box-drawing |
| UTF-8 selection copy | Shipped |
| Wide-character cells | Shipped — CJK / emoji occupy two columns |
| xterm mouse protocol (1000 / 1002 / 1006) | Shipped — Shift still selects |
| IME / composed input | Shipped — GLFW char callback + Unicode glyphs |
| Word / line / rectangular select | Shipped — double / triple / Alt-drag |
| OSC 8 hyperlinks + clickable URLs | Shipped — Cmd/Ctrl-click |
| OSC 0 / 2 window and tab titles | Shipped |

---

## Phase 9 — Project-centric restore (v2.3) — shipped

The product pitch: projects are first-class. Make that true on every launch.

| Item | Status |
| --- | --- |
| Recent workspaces on home | Shipped — Recent list, `R` / ↑↓ Enter |
| Restore last session on launch | Shipped — `__last__` + `restore_last_workspace` |
| Live cwd (OSC 7 + shell hook) | Shipped — `assets/shell/orbit.sh` |
| SSH host list from `~/.ssh/config` | Shipped — palette SSH picker |
| Split UX | Shipped — drag divider, close, prev, zoom, drag-reorder tabs |

---

## Phase 10 — Weekly power-user (v2.4)

| Item | Status |
| --- | --- |
| Regex + case-sensitive search | Shipped — F2 / F3 in terminal search |
| Desktop bell / notifications | Shipped — OS notify when unfocused |
| File drop | Shipped — path pasted into the shell |
| Close confirm | Shipped — quit / close tab / close pane |
| Inline images (iTerm OSC 1337) | Shipped — plus Kitty graphics protocol |

---

## Phase 11 — Distribution (v2.5)

| Item | Status |
| --- | --- |
| Prebuilt binaries per platform | Shipped — `zig build package` + CI uploads zip/tar/`Orbit.app` |
| Signed macOS `.app` / Linux archives / Windows zip | Shipped — `scripts/sign-macos.sh` when `ORBIT_SIGN_IDENTITY` is set; `orbit update` prefers the matching asset |

---

## Phase 12 — Later (first slice shipped)

| Item | Status |
| --- | --- |
| HarfBuzz ligatures and full shaping | Shipped — software ligature table always; `-Dharfbuzz` links system HarfBuzz |
| Kitty graphics protocol | Shipped — transmit+display + delete; PNG / RGB / RGBA |
| SSH keys, jump hosts, ControlMaster, reconnect | Shipped — `ssh.toml` + `~/.ssh/config`; palette Reconnect |
| Cloud sync | Shipped — git remote via `[sync] remote` and `orbit sync` |
| Workspace sharing, remote development | Later |
| Session recording, terminal replay, command timeline | Later |
| GPU effects, multi-cursor | Later |
| WebGPU renderer | Later |

---

# Future (deferred)

Cloud Sync

Workspace Sharing

Remote Development

Session Recording

GPU Effects

Multi Cursor

Terminal Replay

Command Timeline

---

# Philosophy

Ghostty focuses on speed.

Warp focuses on UX.

WezTerm focuses on configuration.

Orbit focuses on **projects**.

Everything revolves around the developer's workflow.

---

# Final Goal

Create the fastest, cleanest, most developer-friendly terminal that feels invisible while you work.

> Orbit — Stay in the flow.
