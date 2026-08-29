# Plugins

Plugins are folders you own under `~/.config/orbit/plugins/<name>/` (Unix) or `%APPDATA%\orbit\plugins\<name>\` (Windows). Each folder has a `plugin.toml`. Orbit does **not** ship an AI API, Prettier, or a linter engine — it runs **your** script.

Same idea as Kitty kittens or a Helix formatter. Author notes also live in [`assets/plugins/README.md`](../assets/plugins/README.md).

---

## Plugins panel

Home → **L** (or **5**), or palette → **Plugins…**.

| Key | Action |
| --- | --- |
| `↑` `↓` | Select a plugin |
| `Space` / `Enter` | Enable / disable (remembered in `plugins.enabled`) |
| `R` | Reload from disk after you edit a `plugin.toml` or script |
| `I` | Install / update the bundled pack |
| `U` / `Delete` | Uninstall the selected plugin from disk |
| `Esc` | Close |

Palette → **Reload Plugins** does the same as **R**.

---

## Install the bundled pack

From home: **Plugins** → **I**.

Or from the repo:

```bash
cp -R assets/plugins/* ~/.config/orbit/plugins/
```

Then **R**. Commands and themes show up in **Ctrl+Shift+P**. Format and lint need a file open (Search → Files / Code). AI uses selected terminal text (or the visible screen).

| Plugin | Kind | What you get |
| --- | --- | --- |
| `hello` | commands | Demo commands + `amber` theme |
| `git` | commands | Status, diff, log, branch, pull, push, stash |
| `devtools` | commands | pwd, ls, tree, clear, disk, ports, env |
| `themes` | theme | `ocean`, `forest`, `midnight`, `rose` |
| `workflow` | commands | New tab, split, open/save workspace, search (host actions) |
| `keys` | keys | Starter custom shortcuts — edit this to make Orbit yours |
| `format` | format | Format the open file (`Ctrl+Shift+I`) — edit `run.sh` |
| `lint` | lint | Lint the open file (`Ctrl+Shift+;`) — unix diagnostics |
| `ai` | ai | Explain selection (`Ctrl+Shift+A`); suggest command — never auto-runs |

---

## Kinds

| Kind | Role |
| --- | --- |
| `commands` | Palette commands, shell inserts, host actions |
| `keys` | Custom shortcuts |
| `theme` | Extra color themes |
| `format` | Format the open file with *your* tool |
| `lint` | Lint the open file; unix `file:line:col: message` overlay |
| `ai` | Explain / suggest using *your* CLI. Never auto-runs |

---

## Command actions

| `action` | Effect |
| --- | --- |
| `run` | Run this plugin’s `[tool]` (format / lint / AI / any CLI) |
| `insert` | Type `payload` into the focused shell (`\r` = Enter) |
| `status` | Show `payload` in the status toast |
| `theme` | Apply theme named in `payload` |
| `host` | Built-in: `new_tab`, `open_workspace`, `save_workspace`, `split_right`, `split_down`, `search` |

### Shortcuts

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

Modifiers: `ctrl`, `cmd` / `super`, `alt` / `option`, `shift`. Use at least one modifier (or an F-key). App chords from `config.toml` win; unbind a built-in first if a plugin should own that chord. See [Keybindings](keybindings.md).

---

## Format / lint / AI — `[tool]`

```toml
name = "format"
kind = "format"

[[commands]]
id = "format.document"
label = "Format: Document"
action = "run"
shortcut = "ctrl+shift+i"

[tool]
command = "sh"
script = "run.sh"          # relative to this plugin folder
args = "{file}"
stdin = "buffer"           # none | buffer | selection
stdout = "replace"         # replace | overlay | insert | status | discard
languages = "javascript, typescript, zig"
timeout_ms = 15000
```

Placeholders in `args` and `prompt`: `{file}` `{cwd}` `{language}` `{action}` `{plugin}` `{dir}`.

The script receives:

- **argv** — expanded `args` (and the script path)
- **stdin** — open file buffer, or selected terminal text
- **stdout** — applied according to `stdout`

Edit these after install:

| File | Default tools |
| --- | --- |
| `format/run.sh` | Prettier, `zig fmt`, rustfmt, gofmt, ruff — whatever is on `PATH` |
| `lint/run.sh` | ESLint, ruff, or a small built-in scan |
| `ai/ask.sh` | Ollama (`ORBIT_AI_MODEL`, default `llama3.2`) or `ORBIT_AI_BIN` |

| Command | Default chord |
| --- | --- |
| Format Document | `Ctrl+Shift+I` |
| Lint File | `Ctrl+Shift+;` |
| AI: Explain | `Ctrl+Shift+A` |
| AI: Suggest command | palette (optional `Ctrl+Shift+Q` in the stub) |

**AI never executes by itself.** You invoke it. It does not run commands in your shell.

Environment the AI script understands:

```bash
export ORBIT_AI_BIN=…       # any CLI that reads the prompt on stdin
export ORBIT_AI_MODEL=…     # Ollama model name
```

---

## Custom themes

```toml
[[themes]]
name = "my-night"
foreground = "#e8eef5"
background = "#0c1018"
cursor = "#7ec8ff"
selection = "#243044"
```

Pick the name in [Appearance](appearance.md) or the palette.

---

## Hooks (optional)

```toml
[hooks]
on_load = "status:my plugin loaded"
on_workspace_open = "status:workspace opened"
on_workspace_save = "status:workspace saved"
# clear_color = "#1a140c"
```

---

## Security

`insert` payloads are audited. Patterns like `curl … | sh`, `rm -rf /`, reverse shells, or `sudo` warn when the plugin loads and when the command runs.

`[tool]` scripts are **your** programs. Treat a third-party plugin folder like a shell script you did not write. Tools never run on load — only when you invoke a `run` command.

Repo scanner:

```bash
zig build security-scan
```

---

## Minimal plugin

`~/.config/orbit/plugins/mine/plugin.toml`:

```toml
name = "mine"
version = "0.1.0"
kind = "commands"
description = "My commands"

[[commands]]
id = "mine.pwd"
label = "Mine: pwd"
action = "insert"
payload = "pwd\r"
```

Press **R** in Plugins. Palette → **Mine: pwd**.

---

## Related

- Appearance / extra palettes: [Appearance](appearance.md)
- App-level chords: [Keybindings](keybindings.md)
- Format/lint need the [editor](search-and-editor.md)

Back to the [docs index](README.md).
