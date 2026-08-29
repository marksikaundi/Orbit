# Orbit docs

This is the user guide for [Orbit](https://github.com/marksikaundi/Orbit) — a project-centric terminal. Start here when you are looking for how to use a feature or how to configure it.

Install first: **[INSTALL.md](../INSTALL.md)**. Then come back here.

---

## I want to…

| Goal | Go here |
| :--- | :------ |
| Launch Orbit and open a shell | [Getting started](getting-started.md) |
| Change theme, font, padding, or prompt | [Appearance](appearance.md) |
| Edit `config.toml` (all keys) | [Configuration](configuration.md) |
| See or change keyboard shortcuts | [Keybindings](keybindings.md) |
| Run an action by name | [Command palette](command-palette.md) |
| Tabs, splits, copy/paste, scrollback | [Tabs & splits](tabs-and-splits.md) · [Terminal](terminal.md) |
| Open a folder and save the layout | [Workspaces](workspaces.md) |
| Search the screen, files, or code | [Search & editor](search-and-editor.md) |
| Format, lint, Git, AI, custom commands | [Plugins](plugins.md) |
| Connect Cursor / VS Code, or use CLI flags | [CLI & IDEs](cli-and-ides.md) (`orbit --help`) |

---

## Guides

1. [Getting started](getting-started.md) — home screen, first terminal, Help overlay
2. [Configuration](configuration.md) — paths, live reload, every `config.toml` key
3. [Appearance](appearance.md) — look, themes, text color, fonts, cursor, prompt, shell
4. [Keybindings](keybindings.md) — defaults and Ghostty-compatible `keybind =`
5. [Command palette](command-palette.md) — `Ctrl+Shift+P` and the full action list
6. [Tabs & splits](tabs-and-splits.md) — tabs, panes, focus
7. [Workspaces](workspaces.md) — open a folder, save/restore layouts
8. [Search & editor](search-and-editor.md) — terminal / files / code search, in-file editor
9. [Plugins](plugins.md) — bundled pack, shortcuts, format / lint / AI, write your own
10. [Terminal](terminal.md) — PTY, scrollback, selection, clipboard, `vi` / `less`
11. [CLI & IDEs](cli-and-ides.md) — `orbit --help`, flags, `ide-setup`, developer commands

---

## Config at a glance

| File or folder | Unix | Windows |
| :--- | :--- | :--- |
| Config | `~/.config/orbit/config.toml` | `%APPDATA%\orbit\config.toml` |
| Plugins | `~/.config/orbit/plugins/<name>/` | `%APPDATA%\orbit\plugins\<name>\` |
| Workspaces | `~/.config/orbit/workspaces/<name>.toml` | `%APPDATA%\orbit\workspaces\<name>.toml` |
| Logs | `~/.config/orbit/logs/orbit.log` | `%APPDATA%\orbit\logs\orbit.log` |

Orbit watches `config.toml` and reloads it automatically. You can also run **Reload Config** from the palette.

Copy the example:

```bash
# Unix
mkdir -p ~/.config/orbit
cp assets/config.example.toml ~/.config/orbit/config.toml

# Windows (PowerShell)
New-Item -ItemType Directory -Force "$env:APPDATA\orbit" | Out-Null
Copy-Item assets\config.example.toml "$env:APPDATA\orbit\config.toml"
```

Or open **Settings** (`S` on the home screen) and press **S** to save.

---

## Keyboard cheat sheet

These are the built-in chords. Override them in [Keybindings](keybindings.md).

| Shortcut | Action |
| :------- | :----- |
| `Ctrl+Shift+H` | Home |
| `Ctrl+Shift+P` | Command palette |
| `Ctrl+Shift+T` / `W` | New / close tab |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Next / previous tab |
| `Ctrl+Shift+D` / `E` | Split right / down |
| `Ctrl+PageDown` | Focus next pane |
| `Ctrl/Cmd+Shift+F` | Search (terminal, files, or code) |
| `Ctrl/Cmd+Shift+C` / `V` | Copy / paste |
| `Ctrl/Cmd+=` `/` `-` `/` `0` | Font larger / smaller / reset |
| `Ctrl+Shift+O` / `S` | Open folder / save workspace |
| `Ctrl+Q` / `Cmd+Q` | Quit |

On the home screen: **Enter** new terminal · **O** open folder · **P** palette · **S** settings · **L** plugins · **H** help · **Q** quit.

---

## Also in this repo

| Document | What it is |
| :--- | :--- |
| [INSTALL.md](../INSTALL.md) | Build and install on macOS, Linux, Windows |
| [CHANGELOG.md](../CHANGELOG.md) | What shipped |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | How to contribute |
| [assets/plugins/README.md](../assets/plugins/README.md) | Plugin author notes (same system as [Plugins](plugins.md)) |
| [roamap.md](../roamap.md) | Architecture and phases |
