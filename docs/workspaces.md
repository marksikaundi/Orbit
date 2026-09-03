# Workspaces

Projects are first-class. A workspace is a **folder you open** plus, optionally, a **saved layout** (tabs, splits, cwd, shell).

Saved files live in `~/.config/orbit/workspaces/<name>.toml` (Unix) or `%APPDATA%\orbit\workspaces\<name>.toml` (Windows).

---

## Open a folder

| How | Result |
| --- | --- |
| Home → **O** / `2` | Native folder picker; shell starts in that directory |
| `Ctrl+Shift+O` | Same, from a terminal |
| Palette → **Open Workspace** | Same |
| `orbit ~/code/api` | Skip home; shell in that path ([CLI](cli-and-ides.md)) |
| `open -a Orbit.app /folder` | macOS: shell in that folder |

This is “open this project.” You do not have to save a named layout unless you want to restore tabs later.

---

## Save a layout

1. Open a folder (or start a terminal).
2. Arrange [tabs and splits](tabs-and-splits.md).
3. `Ctrl+Shift+S` (or palette → **Save Workspace**).
4. Name it (for example `Backend`). Invalid names: empty, `.` / `..`, or characters `/` `\` `"`.

The file records:

- Active tab
- Each tab’s title, split tree, focus, pane ratios
- Each pane’s title, cwd, and shell

Example (also in [`assets/workspaces/Backend.example.toml`](../assets/workspaces/Backend.example.toml)):

```toml
name = "Backend"
active_tab = 0

[[tabs]]
title = "API"
layout = "0"
focus = 0

[[tabs.panes]]
title = "shell"
cwd = "/tmp"
shell = "/bin/zsh"
```

You can copy that example into the workspaces directory, or only use **Save Workspace** from the UI.

---

## Restore

Palette → **Load Saved Workspace** → **↑↓** **Enter**.

In that picker:

| Key | Action |
| --- | --- |
| `↑` `↓` | Choose a saved name |
| `Enter` | Restore that layout |
| `Delete` | Delete the selected `.toml` from disk |
| `Esc` | Cancel |

---

## Related

- Tabs inside a workspace: [Tabs & splits](tabs-and-splits.md)
- Plugin hooks `on_workspace_open` / `on_workspace_save`: [Plugins](plugins.md)

Back to the [docs index](README.md).
