# How to use Orbit

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
| `H` / `5` | Help & Shortcuts (full reference; ↑↓ to scroll) |
| `Q` / `6` | Quit Orbit |
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

```bash
mkdir -p ~/.config/orbit/plugins/hello
cp assets/plugins/hello/plugin.toml ~/.config/orbit/plugins/hello/
```

Open **Ctrl+Shift+P** → `Reload Plugins` (or restart).

## Command palette (Phase 5)

**Ctrl+Shift+P** — type to filter, Enter to run, Esc to close.

## Workspaces (Phase 4)

1. **Open Workspace** (`O` on home, or `Ctrl+Shift+O`) — pick a folder from your computer; Orbit opens a shell there.
2. Arrange tabs/splits as you like.
3. **Ctrl+Shift+S** — save the layout as a named workspace.
4. Command palette → **Load Saved Workspace** — restore a previously saved layout.

Saved layouts live in `~/.config/orbit/workspaces/<name>.toml`.
