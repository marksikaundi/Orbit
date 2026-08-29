# How to use Orbit

The full user guide is in **[docs/](docs/README.md)** — how to use every feature and how to configure it.

| Looking for | Page |
| --- | --- |
| First launch, home screen | [Getting started](docs/getting-started.md) |
| `config.toml` keys | [Configuration](docs/configuration.md) |
| Theme, font, look, prompt | [Appearance](docs/appearance.md) |
| Shortcuts and `keybind =` | [Keybindings](docs/keybindings.md) |
| Command palette | [Command palette](docs/command-palette.md) |
| Tabs and splits | [Tabs & splits](docs/tabs-and-splits.md) |
| Open folder / save layout | [Workspaces](docs/workspaces.md) |
| Search and file editor | [Search & editor](docs/search-and-editor.md) |
| Format, lint, Git, AI | [Plugins](docs/plugins.md) |
| `orbit` flags, Cursor / VS Code | [CLI & IDEs](docs/cli-and-ides.md) |

Install: **[INSTALL.md](INSTALL.md)**.

---

## First-time setup (run once from the Orbit repo)

See [Getting started](docs/getting-started.md#launch).

```bash
zig build setup
```

Then open a new terminal tab (or `source ~/.config/orbit/shell/orbit.sh`).

```bash
--help          # all commands, flags, zig build steps, plugins
orbit --help    # same
zig build run   # from anywhere — builds & launches Orbit (detached)
orbit           # launch Orbit (detached); shell returns immediately
```

Foreground: `zig build run-fg` or `ORBIT_FOREGROUND=1 orbit`.

---

## Connect to Cursor, VS Code, and other IDEs

See **[CLI & IDEs](docs/cli-and-ides.md#connect-to-cursor-vs-code-and-other-ides)**.

```bash
orbit ide-setup
orbit ide-setup --editor cursor
```

---

## From the Orbit repo

```bash
zig build run
```

## Tests

```bash
zig build test
```

## Versioning & releases (`2026-live`)

Orbit uses [SemVer](https://semver.org/) in the root `VERSION` file.

```bash
./scripts/bump-version.sh patch   # or minor / major
# edit CHANGELOG.md for the new section
git add VERSION src/VERSION CHANGELOG.md
git commit -m "release: v$(tr -d '[:space:]' < VERSION)"
git checkout -B 2026-live
git push -u origin 2026-live
```

See [CHANGELOG.md](CHANGELOG.md) and [Releases](https://github.com/marksikaundi/Orbit/releases).

---

## Home screen

See [Getting started](docs/getting-started.md#home-screen).

## Appearance

See [Appearance](docs/appearance.md).

## Font size

See [Appearance](docs/appearance.md#fonts).

## Custom keybindings

See [Keybindings](docs/keybindings.md).

## Plugins

See [Plugins](docs/plugins.md).

## Command palette (Phase 5)

See [Command palette](docs/command-palette.md).

## Search

See [Search & editor](docs/search-and-editor.md).

## Workspaces (Phase 4)

See [Workspaces](docs/workspaces.md).
