#!/usr/bin/env bash
# Assemble zig-out/Orbit.app so macOS shows Orbit's Dock icon (not "exec").
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="${ORBIT_PREFIX:-$ROOT/zig-out}"
BIN="$PREFIX/bin/orbit"
APP="$PREFIX/Orbit.app"
PLIST="${1:-$ROOT/assets/icon/Info.plist}"
ICNS="${2:-$ROOT/assets/icon/AppIcon.icns}"

if [[ ! -x "$BIN" ]]; then
  echo "bundle-macos-app: missing binary at $BIN" >&2
  exit 1
fi
if [[ ! -f "$PLIST" || ! -f "$ICNS" ]]; then
  echo "bundle-macos-app: missing Info.plist or AppIcon.icns" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/orbit"
chmod +x "$APP/Contents/MacOS/orbit"
cp "$PLIST" "$APP/Contents/Info.plist"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Refresh Launch Services icon cache for this bundle (best-effort).
if command -v lsregister >/dev/null 2>&1; then
  lsregister -f "$APP" >/dev/null 2>&1 || true
elif [[ -x /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister ]]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1 || true
fi

echo "bundled $APP"
