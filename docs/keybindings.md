# Keybindings

Orbit ships with a small set of app chords so the shell still owns `Ctrl+A`–`Z` (interrupt, EOF, readline). Overlay, unbind, or replace them with Ghostty-compatible `keybind = trigger=action` in [config.toml](configuration.md).

Same idea as [Ghostty keybindings](https://ghostty.org/docs/config/keybind). Plugin `shortcut =` chords run **after** config keybinds.

---

## Default shortcuts

| Shortcut | Action |
| :------- | :----- |
| `Ctrl+Shift+H` | Home screen |
| `Ctrl+Shift+P` | Command palette |
| `Ctrl+Shift+T` | New tab |
| `Ctrl+Shift+W` / `Cmd+W` | Close tab (home → quit) |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | Next / previous tab |
| `Ctrl+Shift+]` / `[` | Next / previous tab |
| `Ctrl+Shift+D` | Split right (horizontal) |
| `Ctrl+Shift+E` | Split down (vertical) |
| `Ctrl+PageDown` / `Ctrl+PageUp` | Focus next / previous pane |
| `Ctrl+Shift+K` | Close focused pane |
| `Ctrl+Shift+Z` | Zoom / unzoom focused pane |
| `Ctrl/Cmd+Shift+F` | Search |
| `Cmd+C` / `Cmd+V` | Copy / paste (macOS) |
| `Ctrl+C` | Copy **if** there is a selection; otherwise interrupt (Windows/Linux) |
| `Ctrl+V` | Paste (Windows/Linux) |
| `Ctrl/Cmd+Shift+C` / `V` | Copy / paste (all platforms) |
| Right-click | Copy / Paste menu |
| `Ctrl/Cmd+=` / `-` / `0` | Font larger / smaller / reset |
| `Ctrl+Shift+O` | Open folder as workspace |
| `Ctrl+Shift+S` | Save layout as workspace |
| `Ctrl+Q` / `Cmd+Q` | Quit |
| Page Up / Down, mouse wheel | Scrollback |

Home-only keys (`Enter`, `O`, `P`, `S`, `L`, `H`, `Q`) are listed in [Getting started](getting-started.md). Plugin pack chords (`Ctrl+Shift+G`, `I`, `A`, …) are in [Plugins](plugins.md).

In-app: home → **H** for the same list, scrollable.

---

## Custom `keybind =`

Add lines to `~/.config/orbit/config.toml` (or `%APPDATA%\orbit\config.toml`). Palette → **Reload Config**, or wait for live reload.

```toml
# Overlay defaults (new tab, copy/paste, font size still work)
keybind = ctrl+k=reload_config
keybind = ctrl+shift+t=unbind
keybind = performable:ctrl+c=copy_to_clipboard
keybind = ctrl+a>n=new_tab
keybind = ctrl+u=text:\x15
keybind = up=csi:A
```

Table form:

```toml
[keybind]
ctrl+j = "new_tab"
"ctrl+shift+g" = "search"
```

Start from a blank map:

```toml
keybind = clear
keybind = ctrl+shift+t=new_tab
keybind = ctrl+q=quit
```

---

## Syntax

| Piece | Meaning |
| --- | --- |
| Trigger | `key`, `ctrl+key`, `ctrl+shift+key`, `cmd+w` — modifiers in any order |
| Sequence | `ctrl+a>n` — leader, then the next key (no timeout; max 4 keys) |
| `unbind` | Remove that trigger so the key reaches the shell |
| `clear` | Wipe **all** bindings (including defaults), then add only yours |
| `ignore` | Swallow the key |
| `text:` / `csi:` / `esc:` | Send bytes / CSI / ESC to the PTY |
| `performable:` | Only consume the key if the action can run (copy needs a selection) |
| `unconsumed:` | Run the action **and** still send the key to the shell |
| `chain=` | Extra action on the **previous** `keybind` line |
| `all:` / `global:` | Parsed (Ghostty paste); still only while Orbit is focused |
| `physical:` | Parsed and ignored (layout tables are not used yet) |

Modifiers: `shift`, `ctrl` (`control`), `alt` (`opt`, `option`), `super` (`cmd`, `command`).

Keys: `a`–`z`, `0`–`9`, `f1`–`f12`, `enter` (`return`), `escape` (`esc`), `space`, `tab`, `backspace`, `delete`, `up`/`down`/`left`/`right`, `pageup`/`pagedown`, `;`, `,`, `.`, `/`, and similar.

`text:` understands escapes like `\x15` (Ctrl+U). `csi:A` is up-arrow.

```toml
keybind = ctrl+k=reload_config
keybind = chain=go_home
```

That chord reloads config, then goes home.

---

## Action names

Ghostty names are accepted where they map (for example `close_surface`, `new_split:right`, `goto_tab:next`, `copy_to_clipboard`).

### App

| Action | Also accepted |
| --- | --- |
| `new_tab` | |
| `close_tab` | `close_surface`, `close_window` |
| `quit` | |
| `new_split:right` | `split:right`, `split:horizontal`, `split_right` |
| `new_split:down` | `split:down`, `split:vertical`, `split_down` |
| `goto_tab:next` | `next_tab`, `goto_tab:current+1` |
| `goto_tab:previous` | `prev_tab`, `previous_tab` |
| `goto_split` | `focus_next_pane`, `next_split` |
| `focus_prev_pane` | `previous_split`, `prev_split` |
| `close_pane` | `close_split` |
| `zoom_pane` | `toggle_split_zoom` |
| `increase_font_size` | `font_larger` |
| `decrease_font_size` | `font_smaller` |
| `reset_font_size` | `font_reset` |
| `copy_to_clipboard` | `copy`, `copy_selection` |
| `paste_from_clipboard` | `paste` |
| `toggle_command_palette` | `palette`, `command_palette` |
| `scroll_page_up` / `scroll_page_down` | |
| `scroll_to_top` / `scroll_to_bottom` | |
| `reload_config` | |
| `reload_plugins` | |
| `check_updates` | `check_for_updates` |
| `update_orbit` | |
| `open_config` | `settings` |
| `go_home` | `home` |
| `open_workspace` / `save_workspace` | |
| `load_saved_workspace` | `load_workspace` |
| `search` | `toggle_search` |
| `open_file` | |
| `ssh` | |
| `list_plugins` | `plugins` |
| `format_document` | `format` |
| `lint_file` | `lint` |
| `ai_explain` / `ai_suggest` | |

### Cursor and theme

```toml
keybind = ctrl+shift+b=cursor_block
keybind = f9=theme:nord
keybind = f10=theme:catppuccin-mocha
```

Themes: `orbit-dark`, `orbit-light`, `nord`, `dracula`, `gruvbox-dark`, `solarized-dark`, `catppuccin-mocha`, `tokyo-night` (underscores also work).

---

## Plugins shortcut

In any `plugin.toml`:

```toml
[[commands]]
id = "mine.status"
label = "My: Git Status"
action = "insert"
payload = "git status\r"
shortcut = "ctrl+shift+g"

[[bindings]]
keys = "ctrl+alt+l"
command = "mine.status"
```

Use at least one modifier (or an F-key) so typing still reaches the shell. If a built-in chord is in the way:

```toml
keybind = ctrl+shift+g=unbind
```

Then the plugin can own that chord. Details: [Plugins](plugins.md).

---

## Related

- Config file layout: [Configuration](configuration.md)
- Palette (same actions, no chord required): [Command palette](command-palette.md)

Back to the [docs index](README.md).
