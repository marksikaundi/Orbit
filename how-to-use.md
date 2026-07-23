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
| Theme | orbit-dark, orbit-light, nord, dracula, gruvbox-dark, solarized-dark |
| Text | theme (default), soft white, bright, mint, amber, sky, … |
| Cursor | block, underline, bar |
| Blink | on / off |
| Shell | `$SHELL`, zsh, bash, sh, fish… (applies to **new** tabs) |

Press **S** in Settings to save to `~/.config/orbit/config.toml`.

Or edit the file directly (see `assets/config.example.toml`). The shell prompt text itself (`%`, `$`, starship, etc.) still comes from your shell config (`.zshrc` / `.bashrc`).

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
padding_x = 10
padding_y = 6
```

## Plugins (Phase 6)

On home press **L** (or **5**) to open the Plugins panel:

- List installed plugins and **Space/Enter** to enable/disable
- **R** reload from disk after you edit a `plugin.toml`
- **I** install the bundled pack: **hello**, **git**, **devtools**, **themes**, **workflow**, **keys**

| Plugin | What you get |
| --- | --- |
| `hello` | Demo commands + amber theme |
| `git` | Status, diff, log, branch, pull, push, stash |
| `devtools` | pwd, ls, tree, clear, disk, ports, env |
| `themes` | ocean, forest, midnight, rose |
| `workflow` | New tab, split, open/save workspace, search |
| `keys` | **Starter custom shortcuts** — edit this to make Orbit yours |

Or copy from the repo:

```bash
cp -R assets/plugins/* ~/.config/orbit/plugins/
```

Then **R** in the Plugins panel. Commands and themes appear in **Ctrl+Shift+P**.

### Make it yours (shortcuts, colors, themes)

Edit `~/.config/orbit/plugins/keys/plugin.toml` (or add your own folder):

```toml
[[commands]]
id = "mine.status"
label = "My: Git Status"
action = "insert"
payload = "git status\r"
shortcut = "ctrl+shift+g"

[[themes]]
name = "my-night"
foreground = "#e8eef5"
background = "#0c1018"
cursor = "#7ec8ff"
selection = "#243044"
```

Press **R** to reload. Example chords from the `keys` pack: `Ctrl+Shift+G` (git status), `Ctrl+Alt+L` (ls), `Ctrl+Alt+K` (clear).

Full guide: [`assets/plugins/README.md`](assets/plugins/README.md). Appearance (**S**) still covers built-in themes, text color, cursor, and shell.

## Command palette (Phase 5)

**Ctrl+Shift+P** — type to filter, Enter to run, Esc to close.

## Search

**Cmd+Shift+F** / **Ctrl+Shift+F** (or palette → Search):

| Key | Action |
| --- | ------ |
| Type | Live filter |
| `Tab` | Switch **Terminal** ↔ **Files** |
| `↑` `↓` | Move between matches |
| `Enter` | Terminal: jump to hit · Files: insert path into the shell |
| `Esc` | Close |

- **Terminal** — searches visible screen + scrollback (case-insensitive)
- **Files** — searches file names under the opened folder / current cwd

## Workspaces (Phase 4)

1. **Open Workspace** (`O` on home, or `Ctrl+Shift+O`) — pick a folder from your computer; Orbit opens a shell there.
2. Arrange tabs/splits as you like.
3. **Ctrl+Shift+S** — save the layout as a named workspace.
4. Command palette → **Load Saved Workspace** — restore a previously saved layout.

Saved layouts live in `~/.config/orbit/workspaces/<name>.toml`.
