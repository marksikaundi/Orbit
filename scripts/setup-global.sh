#!/usr/bin/env bash
# Install Orbit so you can run it from any directory / terminal.
# - Records source tree in ~/.config/orbit/source_root
# - Installs shell integration (zig build run from anywhere)
# - Puts `orbit` on PATH via ~/.local/bin
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/orbit"
SHELL_SRC="$ROOT/assets/shell/orbit.sh"
SHELL_DST="$CONF/shell/orbit.sh"
BIN_DIR="${HOME}/.local/bin"
MARKER="# Orbit terminal — zig build run from anywhere"

if [[ ! -f "$ROOT/build.zig" ]]; then
  echo "setup-global: cannot find Orbit build.zig at $ROOT" >&2
  exit 1
fi
if [[ ! -f "$SHELL_SRC" ]]; then
  echo "setup-global: missing $SHELL_SRC" >&2
  exit 1
fi

mkdir -p "$CONF/shell" "$BIN_DIR"
printf '%s\n' "$ROOT" >"$CONF/source_root"
cp "$SHELL_SRC" "$SHELL_DST"

# Prefer the macOS app binary when present (Dock icon); else zig-out/bin.
APP_BIN="$ROOT/zig-out/Orbit.app/Contents/MacOS/orbit"
PLAIN_BIN="$ROOT/zig-out/bin/orbit"
LAUNCHER="$BIN_DIR/orbit"

cat >"$LAUNCHER" <<'EOF'
#!/usr/bin/env bash
# Orbit launcher — installed by zig build setup
# Opens Orbit detached; this terminal returns immediately.
set -euo pipefail
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/orbit"
ROOT=""
if [[ -n "${ORBIT_SOURCE_ROOT:-}" && -f "${ORBIT_SOURCE_ROOT}/build.zig" ]]; then
  ROOT="$ORBIT_SOURCE_ROOT"
elif [[ -f "$CONF/source_root" ]]; then
  ROOT="$(tr -d '[:space:]' <"$CONF/source_root")"
fi
if [[ -z "$ROOT" || ! -f "$ROOT/build.zig" ]]; then
  echo "orbit: source tree not configured. From the Orbit repo run: zig build setup" >&2
  exit 1
fi

LAUNCH="$ROOT/scripts/launch-detached.sh"
if [[ -x "$LAUNCH" ]]; then
  case "${1:-}" in
    ide-setup|--ide-setup|-h|--help|-V|--version)
      export ORBIT_FOREGROUND=1
      ;;
  esac
  exec "$LAUNCH" "$@"
fi

# Fallback if the script is missing (older checkout).
APP="$ROOT/zig-out/Orbit.app/Contents/MacOS/orbit"
BIN="$ROOT/zig-out/bin/orbit"
LOG_DIR="$CONF/logs"
mkdir -p "$LOG_DIR"
if [[ -x "$APP" ]]; then
  EXE="$APP"
elif [[ -x "$BIN" ]]; then
  EXE="$BIN"
else
  echo "orbit: binary not built yet — run: zig build" >&2
  exit 1
fi
if [[ "${ORBIT_FOREGROUND:-}" == "1" ]]; then
  exec "$EXE" "$@"
fi
case "${1:-}" in
  ide-setup|--ide-setup|-h|--help|-V|--version)
    exec "$EXE" "$@"
    ;;
esac
nohup "$EXE" "$@" </dev/null >>"$LOG_DIR/orbit.log" 2>&1 &
disown $! 2>/dev/null || true
echo "Orbit terminal opened successfully"
EOF
chmod +x "$LAUNCHER"

# Soft-link a fresh build if one already exists (helps first-run).
if [[ -x "$APP_BIN" ]]; then
  : # launcher prefers app path dynamically
elif [[ -x "$PLAIN_BIN" ]]; then
  :
else
  echo "setup-global: note — binary not built yet; run zig build (or zig build run) once."
fi

append_shell_hook() {
  local rc="$1"
  [[ -z "$rc" ]] && return 0
  mkdir -p "$(dirname "$rc")"
  touch "$rc"
  if grep -qF "$MARKER" "$rc" 2>/dev/null; then
    return 0
  fi
  {
    echo ""
    echo "$MARKER"
    echo '[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/orbit/shell/orbit.sh" ] && source "${XDG_CONFIG_HOME:-$HOME/.config}/orbit/shell/orbit.sh"'
  } >>"$rc"
  echo "setup-global: hooked $rc"
}

# Detect login shell family.
user_shell="$(basename "${SHELL:-zsh}")"
case "$user_shell" in
  zsh)
    append_shell_hook "${ZDOTDIR:-$HOME}/.zshrc"
    ;;
  bash)
    if [[ -f "$HOME/.bashrc" ]] || [[ ! -f "$HOME/.bash_profile" ]]; then
      append_shell_hook "$HOME/.bashrc"
    else
      append_shell_hook "$HOME/.bash_profile"
    fi
    ;;
  *)
    # Still install zsh/bash hooks if those rc files exist (common on macOS).
    [[ -f "${ZDOTDIR:-$HOME}/.zshrc" || -f "${ZDOTDIR:-$HOME}/.zshrc.pre-oh-my-zsh" ]] && append_shell_hook "${ZDOTDIR:-$HOME}/.zshrc"
    [[ -f "$HOME/.bashrc" ]] && append_shell_hook "$HOME/.bashrc"
    echo "setup-global: shell is '$user_shell' — sourced orbit.sh for zsh/bash if present."
    echo "  For other shells, source: $SHELL_DST"
    ;;
esac

echo ""
echo "Orbit is set up for global use."
echo "  source root : $ROOT"
echo "  config      : $CONF"
echo "  command     : $LAUNCHER"
echo ""
echo "Open a new terminal tab/window (or: source $SHELL_DST), then from any directory:"
echo "  zig build run    # build & launch Orbit"
echo "  orbit            # launch the installed binary"
echo ""
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo "Note: add ~/.local/bin to PATH if 'orbit' is not found:"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
