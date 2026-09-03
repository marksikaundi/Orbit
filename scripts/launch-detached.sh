#!/usr/bin/env bash
# Launch Orbit detached from the calling terminal.
# Prints a short success line and returns immediately.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/zig-out/Orbit.app/Contents/MacOS/orbit"
BIN="$ROOT/zig-out/bin/orbit"
LOG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/orbit/logs"
LOG="$LOG_DIR/orbit.log"

if [[ -x "$APP" ]]; then
  EXE="$APP"
elif [[ -x "$BIN" ]]; then
  EXE="$BIN"
else
  echo "orbit: binary not found — run zig build first" >&2
  exit 1
fi

mkdir -p "$LOG_DIR"

# CLI that prints to this terminal (not a GUI window).
case "${1:-}" in
  help|ide-setup|--ide-setup|-h|--help|-V|--version)
    exec "$EXE" "$@"
    ;;
esac

# Foreground mode for debugging (keeps logs in this terminal).
if [[ "${ORBIT_FOREGROUND:-}" == "1" ]]; then
  exec "$EXE" "$@"
fi

# Detach: new session, stdin closed, stdout/stderr to log file.
# shellcheck disable=SC2086
nohup "$EXE" "$@" </dev/null >>"$LOG" 2>&1 &
disown $! 2>/dev/null || true

echo "Orbit terminal opened successfully"
