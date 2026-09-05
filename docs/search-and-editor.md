# Search and editor

Orbit can search the **terminal**, **file names**, and **code inside files**, and open a lightweight **syntax-highlighted editor** with autocomplete.

---

## Search (`Ctrl+Shift+F`)

`Cmd+Shift+F` / `Ctrl+Shift+F`, or palette → **Search**.

| Key | Action |
| --- | --- |
| Type | Live filter |
| `Tab` | Switch **Terminal** ↔ **Files** ↔ **Code** |
| `↑` `↓` | Move between matches |
| `Enter` | Terminal: jump to the hit · Files: open the file · Code: open the file at that line |
| `Shift+Enter` | Files / Code: insert the path into the shell |
| `F2` | Toggle case-sensitive match |
| `F3` | Toggle regex-lite (`. * + ? ^ $`, `\d` `\w` `\s`, `[abc]`) |
| `Esc` | Close (returns to the editor if a file is still open) |

- **Terminal** — visible screen + scrollback (substring by default; F2 / F3 for case and regex)
- **Files** — names under the opened folder / current cwd
- **Code** — contents of those files; Enter opens the editor on that line

Palette → **Open File** jumps straight to Files search. `orbit app.js` also opens the editor.

---

## Find in the open file

With a file open: **⌘/Ctrl+F**.

| Key | Action |
| --- | --- |
| Type | Filter in this buffer |
| `Enter` / `F3` | Next match |
| `Shift+Enter` | Previous match |
| `Esc` | Close find (editor stays open) |

---

## File editor

Open a file from Search (Files or Code) or by passing a file path to `orbit`.

| Key | Action |
| --- | --- |
| Type / arrows | Edit and move the caret |
| Autocomplete popup | Keywords, common APIs, and names already in the file, with a one-line meaning |
| `Tab` / `Enter` | Insert the selected completion |
| `Ctrl+Space` | Open the completion list |
| `⌘/Ctrl+S` | Save |
| `⌘/Ctrl+F` | Find in this file |
| `Esc` | Close (press twice if unsaved) |

This is **not** a language server. Completions come from Orbit’s catalogs plus the current file — no project-wide IntelliSense.

### Highlighted languages

JavaScript, TypeScript, Python, Zig, Rust, Go, C, C++, Java, C#, Ruby, PHP, Swift, Kotlin, HTML/XML/Vue/Svelte, CSS, JSON, TOML, YAML, Markdown, Shell, SQL, Lua.

### Format and lint

With a file open and the bundled plugins installed:

| Chord | Command |
| --- | --- |
| `Ctrl+Shift+I` | Format Document (your `format/run.sh`) |
| `Ctrl+Shift+;` | Lint File (unix `file:line:col:` overlay) |

See [Plugins](plugins.md).

---

## Full-screen terminal apps

`vi` / `vim` / `less` / `htop` use the **alternate screen**. Quitting (`:q`) returns you to the prompt without leftover tildes.

Orbit sets `TERM=xterm-256color`. Enable syntax in vim with `syntax on`, or use `vim` rather than `vi`.

---

## Related

- Search across a project folder: open it as a [workspace](workspaces.md) first
- Palette **Open File**: [Command palette](command-palette.md)

Back to the [docs index](README.md).
