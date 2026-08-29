# Install Orbit

Step-by-step guide to download and install [Orbit](https://github.com/marksikaundi/Orbit) on **macOS**, **Linux**, and **Windows**.

Orbit is currently distributed as **source**. You clone the repository, install Zig and GLFW, then build. Prebuilt installers may arrive in a later release — until then, follow the steps below for your OS.

---

## Table of contents

1. [Requirements](#requirements)
2. [Download Orbit](#download-orbit)
3. [macOS](#macos)
4. [Linux](#linux)
5. [Windows](#windows)
6. [Verify the install](#verify-the-install)
7. [Optional: global launcher](#optional-global-launcher)
8. [Optional: connect to Cursor / VS Code](#optional-connect-to-cursor--vs-code)
9. [Optional: config & plugins](#optional-config--plugins)
10. [Update Orbit](#update-orbit)
11. [Uninstall](#uninstall)
12. [Troubleshooting](#troubleshooting)

---

## Requirements

| Tool | Version | Why |
| ---- | ------- | --- |
| [Git](https://git-scm.com/) | any recent | Clone the repository |
| [Zig](https://ziglang.org/) | **0.16.0 or newer** | Build Orbit (`build.zig.zon` sets `minimum_zig_version`) |
| [GLFW](https://www.glfw.org/) | 3.x | Windowing and input |
| OpenGL / system libs | platform-specific | GPU rendering and PTY |

Supported shells for day-to-day use: zsh, bash, fish, and other POSIX shells; on Windows: PowerShell, pwsh, and cmd via ConPTY (see [Windows](#windows)). Also supported: WSL2 for the Linux build.

---

## Download Orbit

You only need to do this once (then jump to your OS section).

### Option A — Clone with Git (recommended)

```bash
git clone https://github.com/marksikaundi/Orbit.git
cd Orbit
```

To pin a release tag (example: `v2.1.0`):

```bash
git clone https://github.com/marksikaundi/Orbit.git
cd Orbit
git checkout v2.1.0
```

Browse tags and notes: [GitHub Releases](https://github.com/marksikaundi/Orbit/releases).

### Option B — Download a ZIP

1. Open [marksikaundi/Orbit](https://github.com/marksikaundi/Orbit).
2. Click **Code → Download ZIP**, or download a source archive from [Releases](https://github.com/marksikaundi/Orbit/releases).
3. Unzip and open a terminal in that folder:

```bash
cd path/to/Orbit
```

---

## macOS

Works on Apple Silicon (M1/M2/M3/M4) and Intel Macs.

### 1. Install Homebrew (if needed)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Follow the on-screen steps so `brew` is on your `PATH`.

### 2. Install Git, Zig, and GLFW

```bash
brew install git zig glfw
```

Confirm Zig is new enough:

```bash
zig version
# Expect 0.16.0 or higher
```

If Homebrew’s Zig is older than 0.16, install from [ziglang.org/download](https://ziglang.org/download/) and put the binary on your `PATH`.

### 3. Clone (or enter) Orbit

```bash
git clone https://github.com/marksikaundi/Orbit.git
cd Orbit
```

### 4. Build

```bash
zig build
```

This produces:

- `zig-out/bin/orbit` — the binary
- `zig-out/Orbit.app` — macOS app bundle (Dock / Launch Services icon)

Release-optimized build:

```bash
zig build -Doptimize=ReleaseFast
```

### 5. Run

```bash
zig build run      # detached — shell returns immediately
zig build run-fg   # foreground — logs in this terminal
```

Or open the app:

```bash
open zig-out/Orbit.app
```

### 6. Install the global launcher (optional, recommended)

```bash
zig build setup
```

Open a **new** terminal tab, then from any directory:

```bash
orbit
# or
zig build run
```

Both print `Orbit terminal opened successfully` and return to your prompt. See [Optional: global launcher](#optional-global-launcher).

---

## Linux

Tested paths below cover Debian/Ubuntu, Fedora, and Arch-style distros. You need a working X11 (or XWayland) display for GLFW.

### 1. Install system packages

#### Debian / Ubuntu

```bash
sudo apt update
sudo apt install -y git build-essential \
  libglfw3-dev libgl1-mesa-dev libx11-dev \
  libxcursor-dev libxrandr-dev libxi-dev libxinerama-dev
```

#### Fedora

```bash
sudo dnf install -y git gcc \
  glfw-devel mesa-libGL-devel libX11-devel \
  libXcursor-devel libXrandr-devel libXi-devel libXinerama-devel
```

#### Arch / Manjaro

```bash
sudo pacman -S --needed git base-devel glfw-x11 mesa libx11
```

### 2. Install Zig 0.16+

Zig is often newer on the official site than in distro repos.

1. Download the Linux tarball for your CPU from [ziglang.org/download](https://ziglang.org/download/) (version **0.16.0+**).
2. Extract and add it to your `PATH`:

```bash
# Example — adjust version and arch to match your download
tar -xf zig-x86_64-linux-0.16.0.tar.xz
sudo mv zig-x86_64-linux-0.16.0 /opt/zig
echo 'export PATH="/opt/zig:$PATH"' >> ~/.bashrc   # or ~/.zshrc
source ~/.bashrc
zig version
```

### 3. Clone (or enter) Orbit

```bash
git clone https://github.com/marksikaundi/Orbit.git
cd Orbit
```

### 4. Build

```bash
zig build
# or
zig build -Doptimize=ReleaseFast
```

Binary: `zig-out/bin/orbit`.

### 5. Run

```bash
zig build run      # detached
zig build run-fg   # foreground (logs here)
./zig-out/bin/orbit
```

### 6. Install the global launcher (optional, recommended)

```bash
zig build setup
```

Open a new terminal, then:

```bash
orbit
```

Ensure `~/.local/bin` is on your `PATH` (most desktops already include it):

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## Windows

Native Windows is supported via **ConPTY** (Windows 10 1809+ / Windows 11). You can also run the Linux build under **WSL2** if you prefer.

### Native Windows (recommended)

#### 1. Install prerequisites

1. **Git for Windows** — [git-scm.com/download/win](https://git-scm.com/download/win)
2. **Zig 0.16+** — download the Windows zip from [ziglang.org/download](https://ziglang.org/download/), extract it, and add the folder to your user `PATH`
3. **GLFW 3.x** — pick one:

**Option A — vcpkg (recommended)**

```powershell
git clone https://github.com/microsoft/vcpkg C:\vcpkg
C:\vcpkg\bootstrap-vcpkg.bat
C:\vcpkg\vcpkg.exe install glfw3:x64-windows
```

Orbit’s `build.zig` looks in `C:\vcpkg\installed\x64-windows` by default.

**Option B — prebuilt GLFW SDK**

Download GLFW Windows binaries from [glfw.org](https://www.glfw.org/download.html), then either:

- Extract to `C:\glfw` with `include\` and `lib\` folders, **or**
- Pass explicit paths when building:

```powershell
zig build "-Dglfw-path=C:\path\to\glfw"
# or
zig build "-Dglfw-include=C:\path\to\glfw\include" "-Dglfw-lib=C:\path\to\glfw\lib"
```

Confirm Zig:

```powershell
zig version
# Expect 0.16.0 or higher
```

#### 2. Clone Orbit

```powershell
git clone https://github.com/marksikaundi/Orbit.git
cd Orbit
```

#### 3. Build

```powershell
zig build
# or optimized:
zig build -Doptimize=ReleaseFast
```

Binary: `zig-out\bin\orbit.exe`

#### 4. Run

```powershell
zig build run      # detached — new process, shell returns
zig build run-fg   # foreground — logs in this terminal
.\zig-out\bin\orbit.exe
```

#### 5. Install the global launcher (optional, recommended)

```powershell
zig build setup
```

This writes `%APPDATA%\orbit\source_root`, installs `orbit.cmd` under `%LOCALAPPDATA%\Orbit\bin`, and adds that folder to your user `PATH`.

Open a **new** PowerShell or Command Prompt, then:

```powershell
orbit
```

#### Config & plugins on Windows

| Item | Path |
| ---- | ---- |
| Config | `%APPDATA%\orbit\config.toml` |
| Plugins | `%APPDATA%\orbit\plugins\` |
| Workspaces | `%APPDATA%\orbit\workspaces\` |

```powershell
New-Item -ItemType Directory -Force -Path "$env:APPDATA\orbit" | Out-Null
Copy-Item assets\config.example.toml "$env:APPDATA\orbit\config.toml"
Copy-Item -Recurse assets\plugins\* "$env:APPDATA\orbit\plugins\"
```

Default shell is **PowerShell** (`powershell.exe`). You can set `shell = "pwsh.exe"` or `shell = "cmd.exe"` in `config.toml`.

---

### Alternative: WSL2 (Ubuntu)

Use this if you want the Linux build inside Windows.

#### 1. Install WSL2

In **PowerShell (Admin)**:

```powershell
wsl --install -d Ubuntu
```

Restart if Windows asks, then open **Ubuntu** from the Start menu and finish the first-run user setup.

#### 2. Follow the Linux guide inside WSL

In the Ubuntu terminal:

```bash
sudo apt update
sudo apt install -y git build-essential \
  libglfw3-dev libgl1-mesa-dev libx11-dev \
  libxcursor-dev libxrandr-dev libxi-dev libxinerama-dev
```

Install Zig 0.16+ (same steps as [Linux → Install Zig](#2-install-zig-016)), then:

```bash
git clone https://github.com/marksikaundi/Orbit.git
cd Orbit
zig build
zig build run-fg
```

#### 3. GUI apps from WSL

- **Windows 11** — WSLg usually provides a display out of the box; `zig build run-fg` should open a window.
- **Windows 10** — install an X server (e.g. VcXsrv or GWSL), then in WSL:

```bash
export DISPLAY=:0
# or, for some setups:
export DISPLAY=$(grep -m1 nameserver /etc/resolv.conf | awk '{print $2}'):0
```

Then run `zig build run-fg` again.

---

## Verify the install

From the Orbit repo:

```bash
zig build test           # unit tests
zig build security-scan  # secrets / injection heuristics
zig build run-fg         # should open the Orbit window (home screen)
```

On success you should see the Orbit home screen (logo, version, quick actions). Press `Enter` for a new terminal tab.

---

## Optional: global launcher

Run once from the Orbit source tree:

```bash
zig build setup
```

This:

1. Records the source path in `~/.config/orbit/source_root`
2. Installs `orbit` to `~/.local/bin`
3. Hooks your shell so `zig build run` can work from other directories

Then open a **new** tab (or `source ~/.config/orbit/shell/orbit.sh`):

```bash
orbit              # detached launch
zig build run      # same, from almost any folder
ORBIT_FOREGROUND=1 orbit   # logs in this terminal
```

Details: [docs — Getting started](docs/getting-started.md).

---

## Optional: connect to Cursor / VS Code

Orbit is added as the **external** terminal only. The built-in panel (`` Ctrl+` `` / `` Cmd+` ``) is not replaced.

```bash
orbit ide-setup
```

Reload the editor. Full steps, including a manual JSON paste that does not touch integrated profiles: [docs — CLI & IDEs](docs/cli-and-ides.md#connect-to-cursor-vs-code-and-other-ides).

---

## Optional: config & plugins

### Config

```bash
mkdir -p ~/.config/orbit
cp assets/config.example.toml ~/.config/orbit/config.toml
```

Edit themes, font size, opacity, and more. Orbit reloads config without a restart. Keys: [docs — Configuration](docs/configuration.md).

### Plugins

```bash
mkdir -p ~/.config/orbit/plugins
cp -R assets/plugins/* ~/.config/orbit/plugins/
```

Or from Orbit’s home screen: **Plugins → I** to install the bundled pack. Guide: [docs — Plugins](docs/plugins.md).

---

## Update Orbit

```bash
cd path/to/Orbit
git fetch --tags
git pull origin 2026-live   # or: git checkout vX.Y.Z
zig build -Doptimize=ReleaseFast
zig build setup             # refresh the global launcher if you use it
```

Check the latest tag on [Releases](https://github.com/marksikaundi/Orbit/releases).

---

## Uninstall

### Unix (macOS / Linux)

1. Remove the global launcher and config (optional):

```bash
rm -f ~/.local/bin/orbit
rm -rf ~/.config/orbit
```

2. Remove shell hook lines that mention Orbit from `~/.zshrc` / `~/.bashrc` (look for `# Orbit terminal`).

3. Delete the clone:

```bash
rm -rf path/to/Orbit
```

On macOS, also remove any leftover app bundle if you copied it elsewhere:

```bash
rm -rf /Applications/Orbit.app   # only if you moved it there yourself
```

### Windows

1. Remove the launcher and config (optional), in PowerShell:

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Orbit" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$env:APPDATA\orbit" -ErrorAction SilentlyContinue
```

2. Remove `%LOCALAPPDATA%\Orbit\bin` from your user PATH (Settings → System → About → Advanced system settings → Environment Variables).

3. Delete the clone folder.
---

## Troubleshooting

| Problem | What to try |
| ------- | ----------- |
| `zig: command not found` | Install Zig 0.16+ and restart the terminal; confirm with `zig version` |
| Zig too old | Download from [ziglang.org/download](https://ziglang.org/download/) — distro packages are often behind |
| `error: unable to find library glfw` (macOS) | `brew install glfw`; Apple Silicon uses `/opt/homebrew`, Intel often `/usr/local` |
| Missing GLFW / GL / X11 (Linux) | Re-run the apt/dnf/pacman package block above |
| `error: unable to find library glfw` (Windows) | Install GLFW via vcpkg or pass `-Dglfw-path=...` (see [Windows](#windows)) |
| `orbit: command not found` (Windows) | Run `zig build setup`, open a **new** terminal, confirm `%LOCALAPPDATA%\Orbit\bin` is on `PATH` |
| Window does not open (WSL) | Enable WSLg (Win 11) or set `DISPLAY` with an X server (Win 10) |
| `orbit: command not found` | Run `zig build setup` and ensure `~/.local/bin` (Unix) is on `PATH` |
| Build works but Dock icon is generic (macOS) | Use `zig build run` / `open zig-out/Orbit.app` so the bundled `Orbit.app` is used |
| Another project’s `build.zig` “steals” `zig build run` | Expected — Orbit’s shell redirect skips directories that already have a `build.zig`; use `orbit` instead |

Still stuck? Open an issue at [github.com/marksikaundi/Orbit/issues](https://github.com/marksikaundi/Orbit/issues) with your OS, `zig version`, and the full build error.

---

## Next steps

- Day-to-day usage and configuration: **[docs/](docs/README.md)**
- Shortcuts, workspaces, plugins: [docs index](docs/README.md) · [README.md](README.md)
- Contributing: [CONTRIBUTING.md](CONTRIBUTING.md)

**Orbit — Stay in the flow.**
