#!/usr/bin/env bash
# Bump Orbit semver in VERSION (+ CHANGELOG stub).
# Usage: ./scripts/bump-version.sh patch|minor|major
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PART="${1:-}"
if [[ ! "$PART" =~ ^(patch|minor|major)$ ]]; then
  echo "Usage: $0 patch|minor|major" >&2
  exit 1
fi

CURRENT="$(tr -d '[:space:]' < VERSION)"
if [[ ! "$CURRENT" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "VERSION must be X.Y.Z (got: $CURRENT)" >&2
  exit 1
fi

MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"

case "$PART" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac

NEXT="${MAJOR}.${MINOR}.${PATCH}"
printf '%s\n' "$NEXT" > VERSION
printf '%s\n' "$NEXT" > src/VERSION
echo "VERSION: $CURRENT → $NEXT  (VERSION + src/VERSION)"

DATE="$(date -u +%Y-%m-%d)"
CHANGELOG="CHANGELOG.md"
if [[ ! -f "$CHANGELOG" ]]; then
  cat > "$CHANGELOG" << EOF
# Changelog

All notable changes to Orbit are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/) · SemVer.

EOF
fi

# Insert new section after the header block (after first blank line following title).
TMP="$(mktemp)"
{
  awk -v ver="$NEXT" -v date="$DATE" '
    BEGIN { done=0 }
    /^## \[Unreleased\]/ && !done {
      print
      print ""
      print "## [" ver "] — " date
      print ""
      print "### Changed"
      print "- Describe what shipped in this release."
      print ""
      done=1
      next
    }
    /^## \[/ && !done {
      print "## [" ver "] — " date
      print ""
      print "### Changed"
      print "- Describe what shipped in this release."
      print ""
      print
      done=1
      next
    }
    { print }
    END {
      if (!done) {
        print ""
        print "## [" ver "] — " date
        print ""
        print "### Changed"
        print "- Describe what shipped in this release."
      }
    }
  ' "$CHANGELOG"
} > "$TMP"
mv "$TMP" "$CHANGELOG"

echo
echo "Next:"
echo "  1. Edit CHANGELOG.md for v$NEXT"
echo "  2. Commit:  git add VERSION src/VERSION CHANGELOG.md && git commit -m \"release: v$NEXT\""
echo "  3. Push to 2026-live — GitHub Actions tags v$NEXT and publishes the release"
echo
echo "    git checkout 2026-live"
echo "    git merge features   # or your feature branch"
echo "    git push origin 2026-live"
