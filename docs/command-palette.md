# Command palette

**Ctrl+Shift+P** (or **P** on the home screen). Type to filter, **↑↓** to move, **Enter** to run, **Esc** to close, **Backspace** to edit the filter.

The list mixes **built-in actions** and **plugin commands**. Hints on the right match the real [keybindings](keybindings.md) when a chord exists.

---

## How to use it

1. Open with `Ctrl+Shift+P`.
2. Type a few letters (`tab`, `nord`, `git`, `reload`).
3. Enter runs the selected row.

You do not need to remember every shortcut. If something is in this list, you can run it from here.

---

## Built-in actions

| Command | Default hint |
| --- | --- |
| New Tab | `Ctrl+Shift+T` |
| Close Tab | `Ctrl+Shift+W` |
| Split Right | `Ctrl+Shift+D` |
| Split Down | `Ctrl+Shift+E` |
| Next Tab | `Ctrl+Tab` |
| Previous Tab | `Ctrl+Shift+Tab` |
| Focus Next Pane | `Ctrl+PageDown` |
| Focus Previous Pane | `Ctrl+PageUp` |
| Close Pane | `Ctrl+Shift+K` |
| Zoom Pane | `Ctrl+Shift+Z` |
| Open Workspace | `Ctrl+Shift+O` |
| Load Saved Workspace | saved |
| Save Workspace | `Ctrl+Shift+S` |
| Search | `Ctrl+Shift+F` |
| Command Palette | `Ctrl+Shift+P` |
| Copy Selection | `Ctrl+Shift+C` |
| Paste | `Ctrl+Shift+V` |
| Scroll Page Up / Down | |
| Scroll to Top / Bottom | |
| Open File | edit |
| SSH… | `ssh host` |
| Theme: Orbit Dark / Light, Nord, Dracula, Gruvbox Dark, Solarized Dark, Catppuccin Mocha, Tokyo Night | |
| Cursor: Block / Underline / Bar / Toggle Blink | |
| Font: Larger / Smaller / Reset Size | `Ctrl+=` / `-` / `0` |
| Appearance Settings | `S` |
| Go Home | `Ctrl+Shift+H` |
| Quit Orbit | `Ctrl+Q` |
| Reload Config | |
| Reload Plugins | |
| Check for Updates | `orbit update --check` |
| Update Orbit | `orbit update` |
| Plugins… | `L` on home |
| Format Document | plugin |
| Lint File | plugin |
| AI: Explain | plugin |
| AI: Suggest command | plugin |

**SSH…** lists `Host` entries from `~/.ssh/config` (wildcards skipped). Arrow to a host or type one, then Enter inserts `ssh -- host` after the prompt. Format, lint, and AI need the matching [plugin](plugins.md) installed and (for format/lint) a file open.

Plugin rows keep the label from `plugin.toml` (`Git: Status`, `Dev: Tree`, …).

---

## Related

- Bind any of these to a key: [Keybindings](keybindings.md)
- Plugin commands: [Plugins](plugins.md)

Back to the [docs index](README.md).
