# Appearance

Change how Orbit looks from **Settings** (home → **S**, or palette → **Appearance Settings**) or by editing [config.toml](configuration.md).

In Settings: **↑↓** to pick a row, **←→** to change it, **S** to save.

---

## Look (fast path)

`look` is a named Ghostty-style profile: padding, line spacing, and opacity in one step.

| Look | Padding | Line height | Opacity | Feel |
| --- | --- | --- | --- | --- |
| `compact` | 10 × 6 | 1.00 (tight) | 100% | Dense grid |
| `comfortable` | 16 × 10 | 1.12 | 100% | Default Ghostty-like (`ghostty` alias) |
| `airy` | 24 × 16 | 1.24 | 100% | Extra space (`relaxed` alias) |
| `glass` | 16 × 10 | 1.12 | 86% | Transparent (`transparent` alias) |

```toml
[window]
look = "comfortable"
```

After picking a look, you can still nudge **Opacity**, **Padding**, and **Spacing** in Settings or in config.

Opacity steps in the UI: 100%, 95%, 90%, 86%, 80%, 70% (config allows `0.15`–`1.0`). Glass starts at 86%.

Spacing labels: tight → snug → comfortable → roomy → airy → loose.

---

## Themes

Built-in (Settings / palette / `theme.name`):

| Name | Palette command |
| --- | --- |
| `orbit-dark` | Theme: Orbit Dark |
| `orbit-light` | Theme: Orbit Light |
| `nord` | Theme: Nord |
| `dracula` | Theme: Dracula |
| `gruvbox-dark` | Theme: Gruvbox Dark |
| `solarized-dark` | Theme: Solarized Dark |
| `catppuccin-mocha` | Theme: Catppuccin Mocha |
| `tokyo-night` | Theme: Tokyo Night |

```toml
[theme]
name = "catppuccin-mocha"
```

Install the bundled **themes** plugin for extra palettes: `ocean`, `forest`, `midnight`, `rose`. The **hello** plugin adds `amber`; the **keys** plugin adds `keys-slate`. Pick them from Settings or the palette once the plugin is loaded.

Define your own in a plugin:

```toml
[[themes]]
name = "my-night"
foreground = "#e8eef5"
background = "#0c1018"
cursor = "#7ec8ff"
selection = "#243044"
```

See [Plugins](plugins.md).

---

## Text color

Independent of the theme. `theme` uses the theme’s foreground.

| Id | Label |
| --- | --- |
| `theme` | theme (default) |
| `soft-white` | soft white |
| `bright` | bright |
| `cool-gray` | cool gray |
| `warm-gray` | warm gray |
| `mint` | mint |
| `green` | green |
| `amber` | amber |
| `sky` | sky |
| `lavender` | lavender |
| `rose` | rose |

```toml
[theme]
foreground = "mint"
```

---

## Fonts

Default size is **14pt**. Retina scaling is automatic. Size is clamped to 9–28pt.

| Shortcut | Action |
| --- | --- |
| `Ctrl+=` / `Cmd+=` | Larger (+1pt) |
| `Ctrl+-` / `Cmd+-` | Smaller (−1pt) |
| `Ctrl+0` / `Cmd+0` | Reset to 14pt |

Only **installed** faces appear when you cycle Font / Face in Settings.

| Platform | Typical ids |
| --- | --- |
| macOS | `sf-mono` (SF Mono), `menlo`, `andale`, `jetbrains` |
| Linux | `dejavu`, `liberation`, `ubuntu`, `jetbrains` |
| Windows | `consolas`, `cascadia`, `lucida`, `courier` |

```toml
[terminal]
font_face = "jetbrains"
font_size = 15
```

Aliases: `font`, `font_family`. Missing faces fall back to the first installed catalog entry.

---

## Cursor

| Style | Config | Palette |
| --- | --- | --- |
| Block | `cursor_style = "block"` | Cursor: Block |
| Underline | `"underline"` | Cursor: Underline |
| Bar / beam | `"bar"` or `"beam"` | Cursor: Bar |

`cursor_blink = true` / `false`. Palette: **Cursor: Toggle Blink**.

---

## Prompt

Applied to **new** tabs. `default` leaves your `.zshrc` / `.bashrc` prompt alone.

| Value | Result |
| --- | --- |
| `default` | Your shell rc |
| `ghostty` | Dim path + colored `❯` — `~/Projects/Orbit ❯` |
| `minimal` | Quiet prompt |
| `starship` | Uses `starship` on `PATH`, else falls back to ghostty |

```toml
[terminal]
prompt = "ghostty"
```

Re-run `zig build setup` so `~/.config/orbit/shell/orbit.sh` includes the prompt helper, then open a new tab.

---

## Shell

Settings → **Shell** cycles binaries that actually exist.

| Platform | Choices |
| --- | --- |
| Unix | `$SHELL`, `/bin/zsh`, `/bin/bash`, `/bin/sh`, Homebrew/local `fish` / `zsh` |
| Windows | default, `powershell.exe`, `pwsh.exe`, `cmd.exe` |

```toml
[terminal]
shell = "/bin/zsh"
```

The path must be allowed and executable; otherwise Orbit uses the platform default. Existing tabs keep their shell.

---

## Related

- Every key: [Configuration](configuration.md)
- Bind a theme to a chord: [Keybindings](keybindings.md) (`theme:nord`)
- Extra palettes: [Plugins](plugins.md)

Back to the [docs index](README.md).
