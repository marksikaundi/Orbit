# Tabs and splits

Orbit is a single window with **tabs**. Each tab can be one shell or a tree of **split panes**.

---

## Tabs

| Shortcut | Action |
| --- | --- |
| `Ctrl+Shift+T` | New tab (uses [configured shell](appearance.md#shell) and cwd) |
| `Ctrl+Shift+W` / `Cmd+W` | Close tab |
| `Ctrl+Tab` / `Ctrl+Shift+]` | Next tab |
| `Ctrl+Shift+Tab` / `Ctrl+Shift+[` | Previous tab |
| `exit` / `Ctrl+D` | End the shell; closes that tab |

Closing the **last** tab returns to the [home screen](getting-started.md), it does not quit (unless you close from home).

Palette: **New Tab**, **Close Tab**, **Next Tab**, **Previous Tab**.

The tab title follows OSC 0 / 2 from the shell (for example `printf '\033]0;%s\007' "$PWD"`), then the pane title when you [save a workspace](workspaces.md). Drag a tab to reorder it.

---

## Splits

| Shortcut | Action |
| --- | --- |
| `Ctrl+Shift+D` | Split **right** (horizontal split — new pane on the right) |
| `Ctrl+Shift+E` | Split **down** (vertical split — new pane below) |
| `Ctrl+PageDown` | Focus the next pane in that tab |
| `Ctrl+PageUp` | Focus the previous pane |
| `Ctrl+Shift+K` | Close the focused pane (asks first if a session is running) |
| `Ctrl+Shift+Z` | Zoom / unzoom the focused pane |
| Drag the divider | Resize the split |

Palette: **Split Right**, **Split Down**, **Focus Next / Previous Pane**, **Close Pane**, **Zoom Pane**.

Each pane is its own PTY (own shell, cwd, scrollback). Click a pane or cycle focus to type into it.

---

## Layouts

Splits are part of the tab layout. **Save Workspace** (`Ctrl+Shift+S`) writes tabs, split tree, focus, and each pane’s cwd/shell. Restore with palette → **Load Saved Workspace**. See [Workspaces](workspaces.md).

---

## Related

- Copy/paste and scrollback: [Terminal](terminal.md)
- Keybind names: `new_tab`, `new_split:right`, `new_split:down`, `goto_tab:next` — [Keybindings](keybindings.md)

Back to the [docs index](README.md).
