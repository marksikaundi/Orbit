# Terminal

How the shell, screen, selection, and clipboard work day to day.

---

## Shell

A new tab starts a login-style session:

- **Unix:** POSIX PTY, `$SHELL` unless you set [`shell`](appearance.md#shell)
- **Windows:** ConPTY (`powershell.exe` / `pwsh` / `cmd`)

`TERM=xterm-256color`. ANSI/CSI/OSC/SGR/DEC/UTF-8 are parsed (colors, cursor, title, hyperlinks).

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
| Drag, then release | Select text (copies on release) |
| `Cmd+C` / `Cmd+V` | Copy / paste (macOS) |
| `Ctrl+C` / `Ctrl+V` | Copy (when selected) / paste (Windows/Linux) |
| `Ctrl/Cmd+Shift+C` / `V` | Copy / paste on every platform |
| Right-click | Copy / Paste menu |
| Palette | Copy Selection, Paste |

---

## Toasts

Short status messages appear bottom-left and hide after a few seconds: save, theme change, plugin load, errors. Terminal output can also raise a toast for file create/edit/save/delete lines, `error:` / `failed`, and OSC 9 / OSC 99.

---

## Related

- Tabs and panes: [Tabs & splits](tabs-and-splits.md)
- Full-screen `vim` / `less`: [Search & editor](search-and-editor.md#full-screen-terminal-apps)
- Launch flags (`-e`, working directory): [CLI & IDEs](cli-and-ides.md)

Back to the [docs index](README.md).
