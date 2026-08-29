# How to use Orbit

## First-time setup (run once from the Orbit repo)

```bash
zig build setup
```

This records the Orbit source tree, installs the `orbit` command to `~/.local/bin`, and hooks your shell so **`zig build run` works from any directory**.

Then open a new terminal tab (or `source ~/.config/orbit/shell/orbit.sh`).

```bash
zig build run   # from anywhere — builds & launches Orbit (detached)
orbit           # launch Orbit (detached); shell returns immediately
```

Your shell prints `Orbit terminal opened successfully` and stays usable. Logs go to `~/.config/orbit/logs/orbit.log`.

For foreground debugging (logs in this terminal):

```bash
zig build run-fg
# or:
ORBIT_FOREGROUND=1 orbit
```

If the current directory has its own `build.zig`, that project wins (Orbit is not redirected).

## Connect to Cursor, VS Code, and other IDEs

The editor keeps **two** terminals. Orbit only hooks the second one.

| | What it is | What to do |
| --- | --- | --- |
| **Integrated** | Panel inside the editor (`Ctrl+`` ` / `Cmd+`` `) | Leave it alone |
| **External** | A separate app window | Point this at Orbit |

Do **not** add Orbit as an integrated profile or default shell. That would try to run the Orbit GUI *inside* the editor panel.

### Automatic (safe)

```bash
orbit ide-setup                 # Cursor, VS Code, and others it finds
orbit ide-setup --editor cursor # Cursor only
```

This only writes **external** settings and sets `terminal.explorerKind` to `"both"`, so the built-in panel stays. Reload the editor window after.

Then:

- `` Ctrl+` `` / `` Cmd+` `` — still the built-in terminal
- Explorer → right-click a folder → **Open in External Terminal** — Orbit
- Explorer → right-click → **Open in Orbit Terminal** — Orbit
- Command Palette → **Open in Orbit Terminal** — Orbit

### Manual (same result, you paste the keys)

1. Command Palette → **Preferences: Open User Settings (JSON)**
2. Add **only** these keys (keep everything else you already have):

```json
"terminal.external.osxExec": "Orbit.app",
"terminal.external.linuxExec": "orbit-ide",
"terminal.external.windowsExec": "orbit-ide.cmd",
"terminal.explorerKind": "both"
```

3. Save, then reload the window.

`"both"` is the important line: Explorer offers **Open in Integrated Terminal** *and* **Open in External Terminal**. If you set `"external"` instead, the integrated option disappears from the explorer menu (the panel itself still works).

Leave these **unchanged**:

- `terminal.integrated.defaultProfile.*`
- `terminal.integrated.profiles.*`
- `terminal.integrated.shell.*`

### Other IDEs (JetBrains, etc.)

Point the **external / standalone terminal** at Orbit. Do not replace the embedded terminal.

```bash
orbit --working-directory /path/to/project
```

## From the Orbit repo

```bash
zig build run
```

## Tests

Feature unit tests live under `src/tests/` (terminal, config, UI, plugins, font, workspace).

```bash
zig build test
```

You’ll see live status for each test (`ok` / `FAIL` / `skip`) and a final summary.

## Versioning & releases (`2026-live`)

Orbit uses [SemVer](https://semver.org/) in the root `VERSION` file (shown on the home screen).

When you’re happy with features:

```bash
./scripts/bump-version.sh patch   # or minor / major
# edit CHANGELOG.md for the new section
git add VERSION src/VERSION CHANGELOG.md
git commit -m "release: v$(tr -d '[:space:]' < VERSION)"
git checkout -B 2026-live
git push -u origin 2026-live
```

Pushing to **`2026-live`** runs GitHub Actions which:

1. Creates tag `vX.Y.Z` from `VERSION`
2. Publishes a GitHub Release (notes from `CHANGELOG.md`)
3. Updates floating tags `latest` and `2026-live-latest` (for badges)

Keep `VERSION` and `src/VERSION` in sync (the bump script updates both).

See [CHANGELOG.md](CHANGELOG.md) and [Releases](https://github.com/marksikaundi/Orbit/releases).

## Home screen

Orbit opens on a welcome home (logo, version, quick actions) — no shell until you pick one:

| Key | Action |
| --- | ------ |
| `Enter` / `1` | New Terminal |
| `O` / `2` | Open Workspace (pick a folder) |
| `P` / `3` | Command Palette |
| `S` / `4` | Settings / Config |
| `L` / `5` | Plugins |
| `H` / `6` | Help & Shortcuts (full reference; ↑↓ to scroll) |
| `Q` / `7` | Quit Orbit |
| `Ctrl+Shift+H` | Return to home anytime |
| `Cmd+W` / `Ctrl+Shift+W` | Close tab (from home → quit) |
| `Cmd+Q` / `Ctrl+Q` | Quit Orbit (anywhere) |
| `exit` / Ctrl+D | Close the shell tab (last tab → home) |

## Appearance

Open **Settings** (`S` on home) and use **↑↓** + **←→** to change:

| Option | Choices |
| ------ | ------- |
| Theme | orbit-dark, orbit-light, nord, dracula, gruvbox-dark, solarized-dark, catppuccin-mocha, tokyo-night |
| Text | theme (default), soft white, bright, mint, amber, sky, … |
| Font / Face | size in points; SF Mono, Menlo, JetBrains Mono, … |
| Look | compact, comfortable, airy, glass — Ghostty-style padding, line spacing, and opacity |
| Opacity | 100% … 70% (glass look starts at 86%) |
| Padding | interior margin around the grid |
| Spacing | tight → loose (Ghostty `adjust-cell-height`) |
| Cursor | block, underline, bar |
| Blink | on / off |
| Prompt | default (your `.zshrc`), ghostty (dim path + ❯), minimal, starship |
| Shell | `$SHELL`, zsh, bash, sh, fish… (applies to **new** tabs) |

**Look** is the fast path: pick `comfortable` or `glass` and the terminal immediately feels like a custom Ghostty window. Fine-tune Opacity / Padding / Spacing after if you want.

**Prompt** restyles the shell prompt in **new** tabs (your `.zshrc` prompt stays as `default`). Ghostty-style:

```
~/Projects/Orbit ❯
```

Starship uses the `starship` binary if it is on `PATH`, otherwise falls back to the ghostty prompt. Re-run `zig build setup` so `~/.config/orbit/shell/orbit.sh` has the prompt helper.

Press **S** in Settings to save to `~/.config/orbit/config.toml`.

Or edit the file directly (see `assets/config.example.toml`). With Prompt set to `default`, the text still comes from `.zshrc` / `.bashrc`.

## Font size

| Shortcut | Action |
| -------- | ------ |
| `Ctrl+=` / `Cmd+=` | Larger (+1pt) |
| `Ctrl+-` / `Cmd+-` | Smaller (−1pt) |
| `Ctrl+0` / `Cmd+0` | Reset to 14pt |

Default is **14pt** SF Mono (Retina-aware), Ghostty-style. Or set in `~/.config/orbit/config.toml`:

```toml
[terminal]
font_size = 15
padding_x = 16
padding_y = 10
line_height = 1.12
prompt = "ghostty"
```

Ghostty-compatible keys also work: `background-opacity`, `window-padding-x`, `adjust-cell-height`.

## Plugins

On home press **L** (or **5**) to open the Plugins panel:

- List installed plugins and **Space/Enter** to enable/disable (remembered)
- **R** reload from disk after you edit a `plugin.toml` or script
- **I** install the bundled pack: **hello**, **git**, **devtools**, **themes**, **workflow**, **keys**, **format**, **lint**, **ai**

| Plugin | Kind | What you get |
| --- | --- | --- |
| `hello` | commands | Demo commands + amber theme |
| `git` | commands | Status, diff, log, branch, pull, push, stash |
| `devtools` | commands | pwd, ls, tree, clear, disk, ports, env |
| `themes` | theme | ocean, forest, midnight, rose |
| `workflow` | commands | New tab, split, open/save workspace, search |
| `keys` | keys | **Starter custom shortcuts** — edit this to make Orbit yours |
| `format` | format | Format the open file (`Ctrl+Shift+I`) — edit `run.sh` |
| `lint` | lint | Lint the open file (`Ctrl+Shift+;`) — unix diagnostics |
| `ai` | ai | Explain selection (`Ctrl+Shift+A`) — Ollama or your CLI; never auto-runs |

Or copy from the repo:

```bash
cp -R assets/plugins/* ~/.config/orbit/plugins/
```

Then **R** in the Plugins panel. Commands and themes appear in **Ctrl+Shift+P**. Format and lint need a file open (Search → Files / Code). AI uses selected terminal text.

### Make it yours (shortcuts, format, lint, AI)

Edit `~/.config/orbit/plugins/keys/plugin.toml`, or the **scripts**:

- `format/run.sh` — point at Prettier, `zig fmt`, rustfmt, …
- `lint/run.sh` — point at ESLint, ruff, …
- `ai/ask.sh` — Ollama by default, or `ORBIT_AI_BIN`

```toml
kind = "format"

[tool]
command = "sh"
script = "run.sh"
args = "{file}"
stdin = "buffer"
stdout = "replace"
```

Press **R** to reload. Example chords from the pack: `Ctrl+Shift+G` (git status), `Ctrl+Shift+I` (format), `Ctrl+Shift+A` (AI explain).

Full guide: [`assets/plugins/README.md`](assets/plugins/README.md). Appearance (**S**) covers look, opacity, padding, prompt, themes, text color, cursor, and shell.

## Command palette (Phase 5)

**Ctrl+Shift+P** — type to filter, Enter to run, Esc to close.

## Search

**Cmd+Shift+F** / **Ctrl+Shift+F** (or palette → Search):

| Key | Action |
| --- | ------ |
| Type | Live filter |
| `Tab` | Switch **Terminal** ↔ **Files** ↔ **Code** |
| `↑` `↓` | Move between matches |
| `Enter` | Terminal: jump to hit · Files: open the file · Code: open the file at that line |
| `Shift+Enter` | Files / Code: insert the path into the shell |
| `Esc` | Close (returns to the editor if a file is still open) |

- **Terminal** — searches visible screen + scrollback (case-insensitive)
- **Files** — searches file names under the opened folder / current cwd
- **Code** — searches inside files; Enter opens the editor on that line
- **Find in file** — with a file open, **⌘/Ctrl+F** searches that file; Enter / F3 next match, Shift+Enter previous, Esc closes find

- **Editor** — colors keywords, strings, comments, and so on by language (Java, JavaScript, Python, Zig, Rust, Go, HTML, JSON, …). Type to edit. While you type an identifier, a popup lists matching keywords, common APIs, and names already in the file, with a one-line meaning. **Tab** or **Enter** inserts the selected item, **Ctrl+Space** opens the list, **⌘/Ctrl+S** saves, **Esc** closes (press twice if unsaved).

This is not a full language server (no project-wide Java IntelliSense). Completions come from Orbit’s catalogs plus the current file.

Palette → **Open File** jumps straight to Files search. Opening a file path with Orbit (`orbit app.js`) also opens the editor.

In the shell, `vi` / `vim` / `less` use the alternate screen: quitting (`:q`) returns you to the prompt without leftover tildes. Orbit sets `TERM=xterm-256color` so those editors can color syntax (enable it in vim with `syntax on`, or use `vim` rather than `vi`).

## Workspaces (Phase 4)

1. **Open Workspace** (`O` on home, or `Ctrl+Shift+O`) — pick a folder from your computer; Orbit opens a shell there.
2. Arrange tabs/splits as you like.
3. **Ctrl+Shift+S** — save the layout as a named workspace.
4. Command palette → **Load Saved Workspace** — restore a previously saved layout.

Saved layouts live in `~/.config/orbit/workspaces/<name>.toml`.
