#!/usr/bin/env bash
# Build a GitHub Release archive for this platform.
# Usage: scripts/package.sh
# Env: ORBIT_SIGN_IDENTITY  — optional macOS codesign identity
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH="x86_64" ;;
  arm64|aarch64) ARCH="aarch64" ;;
esac
case "$OS" in
  darwin) OS="macos" ;;
  mingw*|msys*|cygwin*) OS="windows" ;;
esac

OUT="${ORBIT_DIST:-$ROOT/zig-out/dist}"
mkdir -p "$OUT"
STAGE="$OUT/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"

echo "packaging Orbit v${VERSION} (${OS}-${ARCH})"
zig build -Doptimize=ReleaseFast

if [[ "$OS" == "macos" ]]; then
  bash "$ROOT/scripts/bundle-macos-app.sh"
  if [[ -n "${ORBIT_SIGN_IDENTITY:-}" ]]; then
    bash "$ROOT/scripts/sign-macos.sh" "$ROOT/zig-out/Orbit.app"
  fi
  NAME="orbit-${VERSION}-${OS}-${ARCH}.zip"
  (cd "$ROOT/zig-out" && zip -qry "$OUT/$NAME" Orbit.app)
elif [[ "$OS" == "windows" ]]; then
  NAME="orbit-${VERSION}-${OS}-${ARCH}.zip"
  mkdir -p "$STAGE/orbit"
  cp zig-out/bin/orbit.exe "$STAGE/orbit/" 2>/dev/null || cp zig-out/bin/orbit "$STAGE/orbit/"
  cp README.md INSTALL.md LICENSE "$STAGE/orbit/" 2>/dev/null || true
  (cd "$STAGE" && zip -qry "$OUT/$NAME" orbit)
else
  NAME="orbit-${VERSION}-${OS}-${ARCH}.tar.gz"
  mkdir -p "$STAGE/orbit"
  cp zig-out/bin/orbit "$STAGE/orbit/"
  cp README.md INSTALL.md LICENSE "$STAGE/orbit/" 2>/dev/null || true
  tar -C "$STAGE" -czf "$OUT/$NAME" orbit
fi

echo "wrote $OUT/$NAME"
printf '%s\n' "$OUT/$NAME"
