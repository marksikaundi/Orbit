# Orbit plugins — make it yours

Drop a folder under `~/.config/orbit/plugins/<name>/` with a `plugin.toml`.
Orbit loads it on start and when you press **R** in the Plugins panel (home → **L**).

This is the same idea as Kitty kittens or a formatter in Helix: **you own the command**. Orbit does not ship an AI API, a Prettier binary, or a linter engine. It runs the script in your plugin folder.

| Kind | What it does |
| --- | --- |
| `commands` | Palette commands, shell inserts, host actions |
| `keys` | Custom shortcuts |
| `theme` | Extra color themes |
| `format` | Format the open file with *your* tool |
| `lint` | Lint the open file; unix `file:line:col: message` overlay |
| `ai` | Explain / suggest using *your* CLI (Ollama, etc). Never auto-runs |

## Quick start

```bash
# From the Orbit repo:
cp -R assets/plugins/* ~/.config/orbit/plugins/
```

Or in Orbit: home → **Plugins** → **I** (install/update full pack).

Then edit any `plugin.toml` or `run.sh`, press **R**, and try it.

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
- **stdout** — captured and applied according to `stdout`

Edit `~/.config/orbit/plugins/format/run.sh` (or `lint/run.sh`, `ai/ask.sh`) to point at Prettier, `zig fmt`, ESLint, ruff, Ollama, or anything else on your PATH.

Palette shortcuts after install:

| Command | Default chord |
| --- | --- |
| Format Document | `Ctrl+Shift+I` |
| Lint File | `Ctrl+Shift+;` |
| AI: Explain | `Ctrl+Shift+A` |

Open a file from Search (**Files** / **Code**) before format or lint. For AI, select terminal text (or use the visible screen).

**AI never executes by itself.** You invoke it. Point `ask.sh` at a local model or set `ORBIT_AI_BIN`.

## Custom shortcuts

```toml
[[commands]]
id = "mine.status"
label = "My: Git Status"
action = "insert"
payload = "git status\r"
shortcut = "ctrl+shift+g"
```

Or separately:

```toml
[[bindings]]
keys = "ctrl+alt+l"
command = "mine.status"
```

Modifiers: `ctrl`, `cmd` / `super`, `alt` / `option`, `shift` (combine with `+`).

Keys: `a`–`z`, `0`–`9`, `f1`–`f12`, `enter`, `escape`, `space`, `tab`, `;`, …

**Use at least one modifier** (or an F-key) so normal typing still reaches the shell.
App chords from `config.toml` (`keybind = …`) win over plugin shortcuts. Unbind a built-in first if you want a plugin to own that chord.

## Custom themes / colors

```toml
[[themes]]
name = "my-night"
foreground = "#e8eef5"
background = "#0c1018"
cursor = "#7ec8ff"
selection = "#243044"
```

Pick the theme from Appearance (**S**) or the palette.

## Command actions

| `action` | Effect |
| --- | --- |
| `run` | Run this plugin's `[tool]` (format / lint / AI / any CLI) |
| `insert` | Type `payload` into the focused shell (use `\r` for Enter) |
| `status` | Show `payload` in the status toast |
| `theme` | Apply theme named in `payload` |
| `host` | Built-in: `new_tab`, `open_workspace`, `save_workspace`, `split_right`, `split_down`, `search` |

**Security:** `insert` payloads are audited. Patterns like `curl … | sh`, `rm -rf /`, reverse shells, or `sudo` trigger a warning when the plugin loads and when the command runs. `[tool]` scripts are **your** programs — treat a third-party plugin folder like a shell script you did not write. Tools never run on load; only when you invoke a `run` command.

Enable/disable is remembered in `~/.config/orbit/plugins.enabled`.

Run the repo scanner anytime with `zig build security-scan`.

## Bundled pack

`hello`, `git`, `devtools`, `themes`, `workflow`, **`keys`**, **`format`**, **`lint`**, **`ai`**.
