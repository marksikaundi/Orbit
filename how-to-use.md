# How to use Orbit

```bash
zig build run
```

## Tests

Feature unit tests live under `src/tests/` (terminal, config, UI, plugins, font, workspace).

```bash
zig build test
```

## Home screen

Orbit opens on a welcome home (logo, version, quick actions) — no shell until you pick one:

| Key | Action |
| --- | ------ |
| `Enter` / `1` | New Terminal |
| `O` / `2` | Open Workspace |
| `P` / `3` | Command Palette |
| `S` / `4` | Settings / Config |
| `H` / `5` | Help & Shortcuts |
| `Ctrl+Shift+H` | Return to home anytime |

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

1. Arrange tabs/splits as you like.
2. **Ctrl+Shift+S** — save workspace.
3. **Ctrl+Shift+O** — open picker.
