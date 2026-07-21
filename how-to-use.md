# How to use Orbit

```bash
zig build run
```

## Plugins (Phase 6)

```bash
mkdir -p ~/.config/orbit/plugins/hello
cp assets/plugins/hello/plugin.toml ~/.config/orbit/plugins/hello/
```

Open **Ctrl+Shift+P** → `Reload Plugins` (or restart). Try `Plugin: Hello`, theme `amber`, or `List Plugins`.

Each plugin is a folder with `plugin.toml` that can register:

- **commands** — `insert` / `status` / `theme` / `host` actions
- **themes** — hex colors
- **hooks** — `on_load`, `on_unload`, `on_workspace_open`, `on_workspace_save`, optional `clear_color`

## Command palette (Phase 5)

**Ctrl+Shift+P** — type to filter, Enter to run, Esc to close.

## Workspaces (Phase 4)

1. Arrange tabs/splits as you like.
2. **Ctrl+Shift+S** — save workspace.
3. **Ctrl+Shift+O** — open picker.

Files: `~/.config/orbit/workspaces/<name>.toml`.
