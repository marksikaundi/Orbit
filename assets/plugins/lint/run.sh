#!/bin/sh
# Orbit lint plugin — you own this.
# Print diagnostics as: path:line:col: message   (unix / gcc style)
# Point this at eslint, ruff, zig ast-check, or any CLI you already use.
set -eu

FILE="${1:-}"
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "untitled:1:1: open a file in Orbit (Search → Files) then run Lint"
  exit 0
fi

have() { command -v "$1" >/dev/null 2>&1; }
ext="${FILE##*.}"
found=0

if have npx; then
  case "$ext" in
    js|mjs|cjs|jsx|ts|mts|cts|tsx)
      if npx --no-install eslint --format unix "$FILE" 2>/dev/null; then
        found=1
      fi
      ;;
  esac
fi

if [ "$found" -eq 0 ] && have ruff; then
  case "$ext" in
    py|pyw)
      ruff check --output-format=concise "$FILE" 2>/dev/null | sed "s|^|$FILE:|" || true
      found=1
      ;;
  esac
fi

if [ "$found" -eq 0 ] && have zig && [ "$ext" = "zig" ]; then
  # ast-check prints errors to stderr; rewrite as unix diagnostics when possible.
  if ! zig ast-check "$FILE" 2>/tmp/orbit-lint-zig.$$; then
    sed -n "s|^.*\\($FILE:[0-9][0-9]*:[0-9][0-9]*:\\)|\\1 |p" /tmp/orbit-lint-zig.$$ || cat /tmp/orbit-lint-zig.$$
    found=1
  fi
  rm -f /tmp/orbit-lint-zig.$$
fi

if [ "$found" -eq 1 ]; then
  exit 0
fi

# Fallback: trailing whitespace, long lines, leftover TODO/FIXME.
awk -v f="$FILE" '
{
  line = $0
  if (match(line, /[ \t]+$/)) {
    printf "%s:%d:%d: trailing whitespace\n", f, NR, RSTART
    n++
  }
  if (length(line) > 120) {
    printf "%s:%d:1: line longer than 120 characters (%d)\n", f, NR, length(line)
    n++
  }
  if (match(line, /TODO|FIXME|XXX/)) {
    printf "%s:%d:%d: leftover marker\n", f, NR, RSTART
    n++
  }
}
END {
  if (n == 0) printf "%s:1:1: no issues found\n", f
}
' "$FILE"
