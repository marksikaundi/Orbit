# How to use Orbit

```bash
zig build run
```

## Font size

| Shortcut | Action |
| -------- | ------ |
| `Ctrl+=` / `Cmd+=` | Larger |
| `Ctrl+-` / `Cmd+-` | Smaller |
| `Ctrl+0` / `Cmd+0` | Reset to 2.0 |

Default scale is **2.0** (1.0 is tiny on Retina). Or set in `~/.config/orbit/config.toml`:

```toml
[terminal]
font_scale = 2.5
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
