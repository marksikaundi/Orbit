# Orbit plugins — make it yours

Drop a folder under `~/.config/orbit/plugins/<name>/` with a `plugin.toml`.
Orbit loads it on start and when you press **R** in the Plugins panel (home → **L**).

Plugins can add:

| Feature | How |
| --- | --- |
| **Commands** | Appear in the command palette (`Ctrl+Shift+P`) |
| **Shortcuts** | `shortcut = "ctrl+shift+g"` on a command, or `[[bindings]]` |
| **Themes** | Extra color themes (also in palette / Appearance after reload) |
| **Hooks** | Status messages on load / workspace open / save |

## Quick start

```bash
# From the Orbit repo:
cp -R assets/plugins/* ~/.config/orbit/plugins/
```

Or in Orbit: home → **Plugins** → **I** (install/update full pack).

Then edit any `plugin.toml`, press **R**, and try your shortcuts.

## Custom shortcuts

```toml
[[commands]]
id = "mine.status"
label = "My: Git Status"
action = "insert"
payload = "git status\r"
shortcut = "ctrl+shift+g"
```

Or separately:

```toml
[[bindings]]
keys = "ctrl+alt+l"
command = "mine.status"
```

Modifiers: `ctrl`, `cmd` / `super`, `alt` / `option`, `shift` (combine with `+`).

Keys: `a`–`z`, `0`–`9`, `f1`–`f12`, `enter`, `escape`, `space`, `tab`, …

**Use at least one modifier** (or an F-key) so normal typing still reaches the shell.
Built-in Orbit chords (`Ctrl+Shift+P`, `Cmd+Q`, …) always win.

## Custom themes / colors

```toml
[[themes]]
name = "my-night"
foreground = "#e8eef5"
background = "#0c1018"
cursor = "#7ec8ff"
selection = "#243044"
```

Pick the theme from Appearance (**S**) or the palette. For text color alone, Appearance also has **Text** presets saved in `config.toml`.

## Command actions

| `action` | Effect |
| --- | --- |
| `insert` | Type `payload` into the focused shell (use `\r` for Enter) |
| `status` | Show `payload` in the status toast |
| `theme` | Apply theme named in `payload` |
| `host` | Built-in: `new_tab`, `open_workspace`, `save_workspace`, `split_right`, `search` |

**Security:** `insert` payloads are audited. Patterns like `curl … | sh`, `rm -rf /`, reverse shells, or `sudo` trigger a warning when the plugin loads and when the command runs. Keep payloads to simple, reviewable commands.

Run the repo scanner anytime with `zig build security-scan`.

## Bundled pack

`hello`, `git`, `devtools`, `themes`, `workflow`, **`keys`** (shortcut examples — edit this one first).
