# CLI and IDEs

The `orbit` binary launches the app, opens a folder or file, runs a command, or registers itself as an **external** terminal in editors.

After `zig build setup`, open a **new** terminal and run:

```bash
--help              # shell helper — full catalog
orbit --help        # same
orbit help          # same
orbit --version
```

That catalog lists every launch flag, `zig build` step, environment variable, in-app shortcut, plugin command, and developer shell command.

---

## Launch flags

```text
orbit [path] [options]
orbit help | --help | -h
orbit ide-setup [--editor cursor|code|codium|windsurf|all]
```

| Flag | Meaning |
| --- | --- |
| `path` | Folder → shell there. File → editor + shell in that file’s folder. Skips the home screen |
| `-d`, `--working-directory DIR` | Working directory (Alacritty / Ghostty / VS Code) |
| `--workdir DIR` | Same (Konsole) |
| `--directory DIR` | Same (Kitty) |
| `--cwd DIR` | Same |
| `-e`, `--command CMD [args…]` | Run this command instead of a login shell |
| `--` | Rest of argv is the command |
| `--wait-after-command` | Keep a shell open after `-e` exits |
| `-t`, `--title TITLE` | First tab title |
| `help`, `-h`, `--help` | Full command catalog |
| `-V`, `--version` | Version |

`=` form works: `--working-directory=/tmp`.

Examples:

```bash
orbit ~/code/api
orbit --working-directory=/tmp
orbit -e git status
orbit app.js
```

macOS: `open -a Orbit.app /folder` opens a shell in that folder (`zig build` / `zig build setup` must leave `Orbit.app` resolvable; copy to `~/Applications` if needed).

Detached vs foreground: [Getting started](getting-started.md#launch).

---

## Developer commands

These work from the Orbit repo, and from **any folder** after `zig build setup` (the shell helper forwards `zig build …` to the Orbit tree unless the current directory has its own `build.zig`).

| Command | What it does |
| --- | --- |
| `zig build` | Compile `zig-out/bin/orbit` |
| `zig build run` | Build and launch detached |
| `zig build run-fg` | Build and launch in the foreground (logs here) |
| `zig build setup` | Install global `orbit` + `--help` shell helper |
| `zig build test` | Unit tests |
| `zig build security-scan` | Scan `src/`, `scripts/`, plugins for secrets / injection |
| `zig build -Doptimize=ReleaseSafe` | Optimized build |
| `./scripts/bump-version.sh patch` | Bump `VERSION` (`minor` / `major` also) |

Useful **inside a shell tab** (also on the command palette if the bundled plugins are installed):

```bash
git status
git diff
git log --oneline -20
git branch -vv
git pull
git push
pwd
ls -la
```

Palette: **Git: Status**, **Dev: Tree**, **Format: Document** (`Ctrl+Shift+I`), **Lint: File** (`Ctrl+Shift+;`), **AI: Explain** (`Ctrl+Shift+A`). AI never auto-runs.

Environment: `ORBIT_FOREGROUND=1` (live logs), `ORBIT_SOURCE_ROOT`, `ORBIT_AI_BIN`, `ORBIT_AI_MODEL`. Full list: `orbit --help`.

---

## Connect to Cursor, VS Code, and other IDEs

Editors have **two** terminals. Orbit only hooks the second one.

| | What it is | What to do |
| --- | --- | --- |
| **Integrated** | Panel inside the editor (`Ctrl+`` ` / `Cmd+`` `) | Leave it alone |
| **External** | A separate app window | Point this at Orbit |

Do **not** add Orbit as an integrated profile or default shell. That would try to run the Orbit GUI *inside* the editor panel.

### Automatic

```bash
orbit ide-setup                 # Cursor, VS Code, VSCodium, Windsurf, … if found
orbit ide-setup --editor cursor # Cursor only
```

This writes **external** settings and sets `terminal.explorerKind` to `"both"`, so the built-in panel stays. It also installs the **Open in Orbit Terminal** explorer command when it can. Reload the editor window after.

Then:

- `` Ctrl+` `` / `` Cmd+` `` — still the built-in terminal
- Explorer → right-click a folder → **Open in External Terminal** — Orbit
- Explorer → right-click → **Open in Orbit Terminal** — Orbit
- Command Palette → **Open in Orbit Terminal** — Orbit

### Manual

1. Command Palette → **Preferences: Open User Settings (JSON)**
2. Add **only** these keys (keep everything else):

```json
"terminal.external.osxExec": "Orbit.app",
"terminal.external.linuxExec": "orbit-ide",
"terminal.external.windowsExec": "orbit-ide.cmd",
"terminal.explorerKind": "both"
```

3. Save, then reload the window.

`"both"` keeps **Open in Integrated Terminal** *and* **Open in External Terminal** in the explorer menu. `"external"` hides the integrated explorer item (the panel itself still works).

Leave these **unchanged**:

- `terminal.integrated.defaultProfile.*`
- `terminal.integrated.profiles.*`
- `terminal.integrated.shell.*`

### Other IDEs (JetBrains, etc.)

Point the **external / standalone terminal** at Orbit. Do not replace the embedded terminal.

```bash
orbit --working-directory /path/to/project
```

---

## Related

- Day-to-day launch: [Getting started](getting-started.md)
- Opening a project folder from inside Orbit: [Workspaces](workspaces.md)
- OS install: [INSTALL.md](../INSTALL.md)

Back to the [docs index](README.md).
