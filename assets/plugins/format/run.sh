#!/bin/sh
# Orbit format plugin — you own this.
# Receives the file path as $1 and the buffer on stdin. Print the formatted
# document to stdout. Swap the command below for prettier, black, rustfmt, …
set -eu

FILE="${1:-untitled.txt}"
BODY=$(cat)

have() { command -v "$1" >/dev/null 2>&1; }

lang="${ORBIT_LANGUAGE:-}"
ext="${FILE##*.}"

run_prettier() {
  printf '%s' "$BODY" | prettier --stdin-filepath "$FILE" 2>/dev/null
}

if have prettier; then
  case "$ext" in
    js|mjs|cjs|jsx|ts|mts|cts|tsx|json|jsonc|css|scss|html|md|markdown|yml|yaml)
      run_prettier && exit 0
      ;;
  esac
fi

if have zig && { [ "$ext" = "zig" ] || [ "$lang" = "zig" ]; }; then
  printf '%s' "$BODY" | zig fmt --stdin && exit 0
fi

if have rustfmt && { [ "$ext" = "rs" ] || [ "$lang" = "rust" ]; }; then
  printf '%s' "$BODY" | rustfmt --emit stdout && exit 0
fi

if have gofmt && { [ "$ext" = "go" ] || [ "$lang" = "go" ]; }; then
  printf '%s' "$BODY" | gofmt && exit 0
fi

if have ruff && { [ "$ext" = "py" ] || [ "$lang" = "python" ]; }; then
  printf '%s' "$BODY" | ruff format - && exit 0
fi

# Fallback: trim trailing spaces and ensure a trailing newline.
printf '%s' "$BODY" | sed 's/[[:space:]]*$//' | awk 'BEGIN{p=0} { if (NR>1) print ""; printf "%s", $0; p=1 } END { if (p) print "" }'
