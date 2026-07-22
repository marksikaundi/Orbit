# Contributing to Orbit

Thank you for your interest in Orbit. This guide explains how to contribute in a way that keeps the project fast, focused, and maintainable.

Orbit is a project-centric terminal emulator written in Zig. Contributions that improve performance, clarity, correctness, or the project-aware workflow are especially welcome.

---

## Table of contents

1. [Ways to contribute](#ways-to-contribute)
2. [Before you start](#before-you-start)
3. [Development setup](#development-setup)
4. [Find something to work on](#find-something-to-work-on)
5. [Branch and workflow](#branch-and-workflow)
6. [Coding standards](#coding-standards)
7. [Testing](#testing)
8. [Commit messages](#commit-messages)
9. [Pull requests](#pull-requests)
10. [Changelog](#changelog)
11. [Plugins and assets](#plugins-and-assets)
12. [Reporting bugs](#reporting-bugs)
13. [Feature requests](#feature-requests)
14. [Security](#security)
15. [License](#license)
16. [Getting help](#getting-help)

---

## Ways to contribute

You do not need to write core terminal code to help. Useful contributions include:

| Area | Examples |
| ---- | -------- |
| Code | Bug fixes, features, refactors aligned with the roadmap |
| Tests | Unit tests under `src/tests/`, edge cases, regressions |
| Docs | README, how-to-use, plugin guides, comments that clarify intent |
| Plugins | Bundled plugins under `assets/plugins/` (commands, themes, shortcuts) |
| Issues | Clear bug reports, reproductions, triage comments |
| Design / UX | Feedback on home, palette, workspaces — keep it minimal |

Please read [roamap.md](roamap.md) before proposing large features so work stays aligned with Orbit’s phases and design principles.

---

## Before you start

1. **Read the product intent** — Orbit prioritizes *projects*, performance, and a minimal UI. Avoid features that bloat the default experience or break the shell’s normal keybindings without a clear need.
2. **Check existing issues and PRs** — search GitHub before opening a duplicate.
3. **Prefer small, focused changes** — one concern per pull request is easier to review and safer to land.
4. **Ask early for large work** — open an issue or discussion for architectural changes, new dependencies, or Phase 7+ scope before investing a lot of time.

---

## Development setup

### Requirements

| Tool | Notes |
| ---- | ----- |
| [Zig](https://ziglang.org/) | **0.16+** (`build.zig.zon` sets `minimum_zig_version`) |
| [GLFW](https://www.glfw.org/) 3.x | e.g. `brew install glfw` on macOS |
| Git | For cloning and pull requests |

Platform notes:

- **macOS** — Homebrew GLFW; OpenGL + Cocoa frameworks linked via `build.zig`
- **Linux** — system GLFW, OpenGL, X11, `util` (for `openpty`)
- **Windows** — ConPTY path (see `src/pty/`)

### Clone and build

```bash
git clone https://github.com/marksikaundi/Orbit.git
cd Orbit
zig build          # produces zig-out/bin/orbit
zig build test     # run the unit test suite
zig build security-scan  # secrets + injection heuristics
zig build run-fg   # launch in the foreground (logs in this terminal)
```

Optional one-time global setup (so `orbit` / `zig build run` work from any directory):

```bash
zig build setup
```

See [how-to-use.md](how-to-use.md) for detached launch, config paths, and day-to-day usage.

### Useful build steps

| Command | Purpose |
| ------- | ------- |
| `zig build` | Build the `orbit` binary |
| `zig build run` | Build and launch (detached) |
| `zig build run-fg` | Build and launch in the foreground |
| `zig build test` | Run unit tests under `src/tests/` |
| `zig build security-scan` | Scan for secrets and injection risks |
| `zig build setup` | Install shell integration / global launcher |

Config for local testing: copy `assets/config.example.toml` to `~/.config/orbit/config.toml`.

---

## Find something to work on

Good starting points:

1. Issues labeled **good first issue** or **help wanted** (when present)
2. Bugs with a clear reproduction
3. Gaps called out in [CHANGELOG.md](CHANGELOG.md) under `[Unreleased]` or in [roamap.md](roamap.md)
4. Missing tests for existing modules in `src/tests/`
5. Plugin polish in `assets/plugins/` (see that folder’s README)

If nothing fits, open an issue describing what you want to improve and wait for maintainer feedback before a large PR.

---

## Branch and workflow

Orbit’s release branch is **`2026-live`**. Day-to-day contribution flow:

```text
1. Fork the repository (or create a branch if you have write access)
2. Create a topic branch from an up-to-date base (prefer 2026-live or main as used by the project)
3. Implement the change with tests
4. Push and open a pull request against the project’s default contribution target
5. Address review feedback
6. Maintainers merge when ready
```

Suggested branch naming:

```text
fix/short-description
feat/short-description
docs/short-description
test/short-description
refactor/short-description
```

Examples: `fix/pty-teardown-hang`, `feat/search-file-filter`, `docs/contributing-guide`.

Do **not** bump `VERSION` / release tags in ordinary contribution PRs unless a maintainer asked you to. Releases are handled via `scripts/bump-version.sh` and the `2026-live` release workflow.

---

## Coding standards

### Architecture

Keep layers isolated. Prefer changing the smallest correct module:

```text
Application → Window → Input → PTY → ANSI Parser → Screen Buffer → Renderer → GPU
```

| Area | Typical paths |
| ---- | ------------- |
| App / lifecycle | `src/app/` |
| Window / GLFW | `src/window/` |
| Terminal / ANSI / screen | `src/terminal/` |
| PTY | `src/pty/` |
| Renderer / fonts | `src/renderer/`, `src/font/` |
| UI (home, palette, search, bindings) | `src/ui/` |
| Config / themes | `src/config/` |
| Workspaces | `src/workspace/` |
| Plugins | `src/plugins/`, `assets/plugins/` |
| Platform extras | `src/platform/` |
| Tests | `src/tests/` (wired from `src/tests.zig`) |

### Style guidelines

- Match the style of neighboring Zig code (naming, indentation, error handling).
- Prefer explicit ownership and clear error paths over clever abstractions.
- Do not add dependencies without discussion; Orbit aims to stay lightweight.
- Avoid breaking shell semantics: chords like plain `Ctrl+W` / `Ctrl+C` belong to the shell unless documented otherwise. Shared app shortcuts live in `src/ui/bindings.zig` — keep palette hints and real key dispatch in sync.
- Keep the default UI minimal. Prefer palette commands and config over permanent chrome.
- Comment *why*, not *what*, when intent is non-obvious.
- Performance matters: avoid unnecessary allocations on hot paths (input, parse, render).

### Design principles (do not violate casually)

1. Performance first  
2. Minimal UI  
3. No unnecessary features  
4. GPU-accelerated rendering  
5. Native experience  
6. Stable, layered architecture  
7. Memory safety through Zig  
8. Project-aware workflows  

---

## Testing

All non-trivial changes should include or update tests.

```bash
zig build test
zig build security-scan
```

`zig build security-scan` walks `src/`, `scripts/`, and `assets/plugins/` for hardcoded secrets, shell-injection patterns, and dangerous plugin `insert` payloads. Findings are printed as warnings; the step exits non-zero on **HIGH** / **CRITICAL** (override with `--fail-on warning`).

CI runs the same check on every push and pull request (`.github/workflows/security-scan.yml`).

### Where tests live

Feature suites live under `src/tests/` and are registered in `src/tests.zig`:

```text
src/tests/
  terminal/     # cell, screen, parser, selection
  config/       # config, theme
  ui/           # palette, bindings, home, search
  pty/
  plugins/
  security/     # scanner rules + plugin payload audit
  font/
  workspace/
```

### Adding a new test file

1. Create `src/tests/<area>/<name>_test.zig`.
2. Add a `comptime { _ = @import("tests/..."); }` line in `src/tests.zig`.
3. Run `zig build test` and ensure your suite shows `ok`.

### What to test

- Parser / screen / selection edge cases
- Config and theme parsing
- Keybinding match tables (`bindings.zig`)
- Plugin manifest parsing
- Workspace TOML round-trips
- Regressions that previously broke users

UI and GPU paths may be hard to unit-test fully; still prefer extracting pure logic so it can be tested without a window.

Manual check before opening a PR (when relevant):

```bash
zig build run-fg
```

Verify home screen, new terminal, workspace open, palette, and that your change behaves as expected on your platform.

---

## Commit messages

Write clear, focused commits. Prefer the imperative mood and a short subject:

```text
fix: stop UI hang when closing a tab during PTY teardown
feat: add text color presets in Appearance
docs: add step-by-step contributing guide
test: cover plugin shortcut chord parsing
refactor: share shortcut table between palette and input
```

Guidelines:

- One logical change per commit when practical
- Explain *why* in the body if the subject is not enough
- Do not mix unrelated refactors with feature work
- Do not commit secrets, local paths unique to your machine, or large generated binaries unless they are intentional project assets

---

## Pull requests

### Checklist before you open a PR

- [ ] Branch is up to date with the target base branch
- [ ] `zig build` succeeds on your machine
- [ ] `zig build test` passes
- [ ] `zig build security-scan` passes (no HIGH/CRITICAL findings)
- [ ] New behavior has tests (or a clear reason why not)
- [ ] Docs updated if user-facing behavior changed (`README.md`, `how-to-use.md`, plugin README)
- [ ] `[Unreleased]` section in `CHANGELOG.md` updated for user-visible changes
- [ ] No unrelated formatting or drive-by edits
- [ ] PR description explains motivation, approach, and how to verify

### PR description template

Use something like:

```markdown
## Summary
- What problem does this solve?
- What approach did you take?

## Test plan
- [ ] `zig build test`
- [ ] `zig build security-scan`
- [ ] Manual: steps a reviewer can follow

## Notes
- Breaking changes, follow-ups, or screenshots if UI-related
```

### Review expectations

- Maintainers may request changes for architecture fit, performance, or scope.
- Keep discussion technical and respectful.
- Smaller PRs get faster reviews. Prefer splitting mega-changes when possible.

---

## Changelog

Orbit follows [Keep a Changelog](https://keepachangelog.com/) and [Semantic Versioning](https://semver.org/).

For user-visible changes, add a bullet under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md):

- **Added** — new capabilities  
- **Changed** — behavior changes  
- **Fixed** — bug fixes  
- **Removed** — removed features  

Internal-only refactors usually do not need a changelog entry.

Do not create a dated release section or bump `VERSION` / `src/VERSION` unless you are coordinating a release with maintainers.

---

## Plugins and assets

Plugins are a supported extension path (Phase 6).

- Bundled examples: `assets/plugins/`
- Authoring guide: [`assets/plugins/README.md`](assets/plugins/README.md)
- Manifest format: `plugin.toml` (commands, themes, `shortcut` / `[[bindings]]`)

When contributing a plugin:

1. Keep it small and purposeful.
2. Document commands and shortcuts in the plugin README or comments.
3. Prefer optional behavior — do not change core defaults unexpectedly.
4. Add or update manifest-related tests if you change parser behavior in `src/plugins/`.

---

## Reporting bugs

Open a GitHub issue with:

1. **Orbit version** — from the home screen or `VERSION`
2. **OS and architecture** — e.g. macOS 15 arm64, Ubuntu 24.04 x86_64
3. **Zig version** — `zig version`
4. **Steps to reproduce** — minimal and numbered
5. **Expected vs actual** behavior
6. **Logs** — if useful: `~/.config/orbit/logs/orbit.log` or output from `zig build run-fg`
7. **Config** — relevant snippets from `~/.config/orbit/config.toml` (redact personal paths if needed)

---

## Feature requests

Open an issue that covers:

- The problem you are trying to solve (not only the solution)
- How it fits Orbit’s project-centric, minimal, performance-first goals
- Whether it belongs in core vs a plugin
- Any alternatives you considered

Large ideas should map to a phase in [roamap.md](roamap.md) or be discussed before implementation.

---

## Security

### Reporting vulnerabilities

If you believe you found a security vulnerability:

1. **Do not** open a public issue with exploit details.
2. Contact the maintainer privately via GitHub security advisories (if enabled) or another private channel listed on the repository.
3. Allow reasonable time for a fix before public disclosure.

### Automated scans

Orbit includes a core security scanner (`src/security/`) that reviews new and existing code for:

- Hardcoded secrets (private keys, cloud tokens)
- Shell injection patterns (`curl | sh`, `eval`, `system(` / `popen(`)
- Destructive or reverse-shell payloads
- Dangerous plugin `insert` commands

Run locally:

```bash
zig build security-scan
# optional: zig build security-scan -- --fail-on warning
```

Risky plugin inserts also surface as load-time log warnings and a status toast when executed.

---

## License

By contributing to Orbit, you agree that your contributions are licensed under the same [Apache License, Version 2.0](LICENSE) that covers the project, unless explicitly stated otherwise.

See [NOTICE](NOTICE) for attribution. Do not add code you are not entitled to contribute under Apache-2.0-compatible terms.

---

## Getting help

- Product and phase context: [roamap.md](roamap.md)
- End-user usage: [how-to-use.md](how-to-use.md)
- Build and overview: [README.md](README.md)
- Plugin authoring: [assets/plugins/README.md](assets/plugins/README.md)

Questions about contributing are welcome on GitHub Issues. Thank you for helping keep developers in the flow.

**Orbit — Stay in the flow.**
