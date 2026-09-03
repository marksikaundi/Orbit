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

Responsibilities

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

v0.1

Basic terminal

v0.2

ANSI support

v0.3

Themes

v0.4

Tabs

v0.5

Splits

v0.6

Workspaces

v0.7

Plugins

v0.8

Search

v0.9

Performance

v1.0

Stable Release

---

# Future

SSH Manager

Cloud Sync

Workspace Sharing

Remote Development

Session Recording

Image Protocol

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
