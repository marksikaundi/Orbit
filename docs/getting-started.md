# Getting started

Orbit opens on a **home screen**, not a shell. Pick an action, then work as usual.

If Orbit is not installed yet, see **[INSTALL.md](../INSTALL.md)**.

---

## Launch

After `zig build setup` (once, from the Orbit repo), open a new terminal tab:

```bash
--help                # all commands and how to use them
orbit --help          # same catalog
orbit                 # detached — prints “Orbit terminal opened successfully”
orbit update --check  # current vs latest GitHub release
orbit update          # install that release (restart Orbit after)
zig build run         # same, from any folder (unless that folder has its own build.zig)
```

Logs go to `~/.config/orbit/logs/orbit.log` (Unix) or `%APPDATA%\orbit\logs\orbit.log` (Windows).

Stay attached (logs in this terminal):

```bash
ORBIT_FOREGROUND=1 orbit    # Unix
# Windows:  $env:ORBIT_FOREGROUND=1; orbit
zig build run-fg            # from the Orbit repo
```

Open a project folder or a file directly:

```bash
orbit ~/code/api
orbit app.js                # editor + shell in that file’s folder
```

More flags: [CLI & IDEs](cli-and-ides.md).

---

## Home screen

| Key | Action |
| --- | ------ |
| `Enter` / `1` | New Terminal — a shell tab |
| `O` / `2` | Open Workspace — native folder picker, shell in that directory |
| `P` / `3` | [Command palette](command-palette.md) |
| `S` / `4` | [Settings / Appearance](appearance.md) |
| `L` / `5` | [Plugins](plugins.md) |
| `H` / `6` | Help & Shortcuts (full in-app reference; ↑↓ to scroll) |
| `Q` / `7` | Quit Orbit |
| `↑` `↓` | Move the selection |

`Ctrl+Shift+H` returns to home from a terminal. Closing the last shell tab (`exit` / `Ctrl+D`) also returns to home.

---

## A typical session

1. **Enter** — open a terminal, or **O** to start in a project folder.
2. Arrange [tabs and splits](tabs-and-splits.md) as you like.
3. `Ctrl+Shift+S` — [save the layout](workspaces.md). The next launch restores the last session automatically; home also lists recent names.
4. `Ctrl+Shift+P` — jump to any action (theme, new tab, plugin commands, …).
5. `Ctrl+Shift+F` — [search](search-and-editor.md) the screen, file names, or code.
6. `H` on home — the same shortcuts as this docs set, inside the app.

---

## Quit and close

| Shortcut | What happens |
| --- | --- |
| `Cmd+Q` / `Ctrl+Q` | Quit Orbit (works anywhere) |
| `Cmd+W` / `Ctrl+Shift+W` | Close the current tab; on home, quit |
| `exit` / `Ctrl+D` | End the shell; closes that tab |
| Window close button | Close the Orbit window (asks first if a session is running) |

Plain `Ctrl+W` is left for the shell (kill-word). Use `Ctrl+Shift+W` or `Cmd+W` to close a tab.

---

## Next

- Make it look right: [Appearance](appearance.md)
- Bind keys the way you like: [Keybindings](keybindings.md)
- Put a project on a named layout: [Workspaces](workspaces.md)
- Add Git / format / lint / AI: [Plugins](plugins.md)

Back to the [docs index](README.md).
