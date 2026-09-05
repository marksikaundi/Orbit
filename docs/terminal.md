# Terminal

How the shell, screen, selection, and clipboard work day to day.

---

## Shell

A new tab starts a login-style session:

- **Unix:** POSIX PTY, `$SHELL` unless you set [`shell`](appearance.md#shell)
- **Windows:** ConPTY (`powershell.exe` / `pwsh` / `cmd`)

`TERM=xterm-256color`. ANSI/CSI/OSC/SGR/DEC/UTF-8 are parsed (colors, cursor, titles, OSC 7 cwd, OSC 8 hyperlinks, xterm mouse 1000/1002/1006). Kitty graphics (`APC G`) and iTerm inline images (`OSC 1337;File=inline=1`) draw after the cell grid. Glyphs load on demand with fallback fonts; CJK and emoji occupy two columns. Programming ligatures (`=>`, `!=`, `->`, …) cluster when `font_ligatures = true`; `zig build -Dharfbuzz` adds OpenType GSUB.

Ctrl+A–Z (except app chords) go to the shell: `Ctrl+C` interrupt, `Ctrl+D` EOF, readline, and so on. On Windows/Linux, `Ctrl+C` **copies** when there is a selection (`performable:`), otherwise it interrupts.

---

## Scrollback

Default **2000** lines (`[terminal] scrollback` in [config](configuration.md)).

| Input | Action |
| --- | --- |
| Mouse wheel | Scroll the active pane |
| `Page Up` / `Page Down` | Page through scrollback |
| Palette | Scroll Page Up / Down, Scroll to Top / Bottom |

---

## Selection and clipboard

| How | What |
| --- | --- |
| Drag, then release | Select text (copies on release, UTF-8) |
| Double-click | Select word |
| Triple-click | Select line |
| Alt-drag | Rectangular select |
| Cmd/Ctrl-click | Open `http(s)://` or an OSC 8 hyperlink |
| Drop a file | Paste the path into the shell |
| TUI mouse | vim / less / tmux / htop / lazygit (Shift-drag still selects) |
| `Cmd+C` / `Cmd+V` | Copy / paste (macOS) |
| `Ctrl+C` / `Ctrl+V` | Copy (when selected) / paste (Windows/Linux) |
| `Ctrl/Cmd+Shift+C` / `V` | Copy / paste on every platform |
| Right-click | Copy / Paste menu |
| Palette | Copy Selection, Paste |

---

## Toasts

Short status messages appear bottom-left and hide after a few seconds: save, theme change, plugin load, errors. Terminal output can also raise a toast for file create/edit/save/delete lines, `error:` / `failed`, and OSC 9 / OSC 99. When Orbit is unfocused, OSC 9/99 and BEL also send a desktop notification.

---

## Related

- Tabs and panes: [Tabs & splits](tabs-and-splits.md)
- Full-screen `vim` / `less`: [Search & editor](search-and-editor.md#full-screen-terminal-apps)
- Launch flags (`-e`, working directory): [CLI & IDEs](cli-and-ides.md)

Back to the [docs index](README.md).
