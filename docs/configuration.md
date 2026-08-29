# Configuration

Orbit is configured with a TOML file. Changes are **watched and reloaded** — no restart required. You can also run **Reload Config** from the [command palette](command-palette.md).

Example file in the repo: [`assets/config.example.toml`](../assets/config.example.toml).

---

## Where files live

| What | Unix | Windows |
| :--- | :--- | :--- |
| Config root | `~/.config/orbit/` | `%APPDATA%\orbit\` |
| Settings | `config.toml` | same name |
| Plugins | `plugins/<name>/plugin.toml` | same |
| Plugin on/off | `plugins.enabled` | same |
| Saved layouts | `workspaces/<name>.toml` | same |
| Shell helper | `shell/orbit.sh` (from `zig build setup`) | n/a |
| Logs | `logs/orbit.log` | same |

Create the file:

```bash
# Unix
mkdir -p ~/.config/orbit
cp assets/config.example.toml ~/.config/orbit/config.toml

# Windows (PowerShell)
New-Item -ItemType Directory -Force "$env:APPDATA\orbit" | Out-Null
Copy-Item assets\config.example.toml "$env:APPDATA\orbit\config.toml"
```

Or: home → **Settings** (`S`) → press **S** to write `config.toml` from the current Appearance values.

---

## Full example

```toml
[window]
width = 980
height = 620
look = "comfortable"   # compact | comfortable | airy | glass
opacity = 1.0          # also: background-opacity

[theme]
name = "orbit-dark"
foreground = "theme"   # or soft-white, bright, mint, amber, …

[terminal]
scrollback = 2000
font_size = 14
font_face = "jetbrains"   # also: font, font_family
padding_x = 16            # also: window-padding-x
padding_y = 10            # also: window-padding-y
line_height = 1.12        # also: adjust-cell-height
prompt = "ghostty"        # default | ghostty | minimal | starship
# shell = "/bin/zsh"      # omit for $SHELL / platform default
cursor_style = "block"    # block | underline | bar (beam = bar)
cursor_blink = true

# Ghostty-compatible (overlay the defaults)
# keybind = ctrl+k=reload_config
# keybind = performable:ctrl+c=copy_to_clipboard
```

Hyphenated Ghostty names work next to Orbit’s snake_case names.

---

## `[window]`

| Key | Default | Notes |
| --- | --- | --- |
| `width` | `900` | Logical pixels |
| `height` | `560` | Logical pixels |
| `look` | `compact` | Named profile: padding + line height + opacity. Aliases: `ghostty` → comfortable, `relaxed` → airy, `transparent` → glass. See [Appearance](appearance.md). |
| `opacity` | `1.0` | `0.15`–`1.0`. Aliases: `background-opacity`, `background_opacity`. |

Setting `look` applies that profile’s padding, spacing, and opacity. Fine-tune `opacity` / `padding_*` / `line_height` afterwards.

---

## `[theme]`

| Key | Default | Notes |
| --- | --- | --- |
| `name` | `orbit-dark` | Built-in: `orbit-dark`, `orbit-light`, `nord`, `dracula`, `gruvbox-dark`, `solarized-dark`, `catppuccin-mocha`, `tokyo-night`. Plugin themes (e.g. `ocean`) work once that plugin is loaded. |
| `foreground` | `theme` | Text-color override. Aliases: `text`, `fg`. Values: `theme`, `soft-white`, `bright`, `cool-gray`, `warm-gray`, `mint`, `green`, `amber`, `sky`, `lavender`, `rose`. |

---

## `[terminal]`

| Key | Default | Notes |
| --- | --- | --- |
| `scrollback` | `2000` | Lines kept above the visible screen |
| `font_size` | `14` | Points; clamped **9–28**. Retina scale is applied automatically |
| `font_face` | first installed face | Aliases: `font`, `font_family`. See [Appearance](appearance.md#fonts) for ids |
| `font_scale` | — | Legacy: `2.0` ≈ 14pt (`14 * scale / 2`) |
| `padding_x` / `padding_y` | from look | Logical pixels, 0–48. Aliases: `window-padding-x` / `window-padding-y` |
| `line_height` | from look | `1.0`–`1.5`. Accepts `1.12`, `12%`, `+12%`, or a pixel bump like Ghostty `adjust-cell-height = 2` |
| `look` | — | Same as `[window] look` if you prefer it here |
| `prompt` | `default` | Alias: `prompt_style`. `default` keeps your `.zshrc` / `.bashrc`. `ghostty` / `minimal` / `starship` overlay new tabs. Requires `zig build setup` so `orbit.sh` is sourced |
| `shell` | platform default | Unix: `/bin/zsh`, `/bin/bash`, `/bin/sh`, fish paths. Windows: `powershell.exe`, `pwsh.exe`, `cmd.exe`. Ignored if missing or not allowed |
| `cursor_style` | `block` | `block`, `underline`, `bar` (`beam` = bar) |
| `cursor_blink` | `true` | `true` / `false` |

`shell` applies to **new** tabs, not the one already open.

---

## Keybindings

Two equivalent forms, both Ghostty-compatible:

```toml
keybind = ctrl+shift+t=new_tab
keybind = ctrl+shift+t=unbind
keybind = clear

[keybind]
ctrl+j = "new_tab"
"ctrl+shift+g" = "search"
```

Full syntax, defaults, and action names: [Keybindings](keybindings.md).

---

## Live reload

1. Save `config.toml`.
2. Orbit reloads on the next watch tick.
3. If you want it immediately: palette → **Reload Config**.

Appearance saved with **S** in Settings overwrites `config.toml` (including commented `keybind` examples unless you already have `keybind =` lines).

---

## Related

- Visual options: [Appearance](appearance.md)
- Shortcuts: [Keybindings](keybindings.md)
- Plugins live beside this file: [Plugins](plugins.md)
- Layouts: [Workspaces](workspaces.md)

Back to the [docs index](README.md).
