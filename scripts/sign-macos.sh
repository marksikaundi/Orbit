#!/usr/bin/env bash
# Codesign Orbit.app when a Developer ID is available.
# Usage: scripts/sign-macos.sh [path/to/Orbit.app]
# Env: ORBIT_SIGN_IDENTITY  (e.g. "Developer ID Application: Name (TEAMID)")
#      ORBIT_NOTARIZE=1 + APPLE_ID / APPLE_TEAM_ID / APPLE_APP_PASSWORD for notarization
set -euo pipefail

APP="${1:-zig-out/Orbit.app}"
if [[ ! -d "$APP" ]]; then
  echo "sign-macos: missing $APP" >&2
  exit 1
fi
if [[ -z "${ORBIT_SIGN_IDENTITY:-}" ]]; then
  echo "sign-macos: ORBIT_SIGN_IDENTITY unset — skipping (unsigned archive is still installable)"
  exit 0
fi

codesign --force --deep --options runtime --sign "$ORBIT_SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "signed $APP"

if [[ "${ORBIT_NOTARIZE:-}" == "1" ]]; then
  if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_PASSWORD:-}" ]]; then
    echo "sign-macos: notarize requested but APPLE_ID / APPLE_TEAM_ID / APPLE_APP_PASSWORD missing" >&2
    exit 1
  fi
  ZIP="${APP}.notarize.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  echo "notarized $APP"
fi
