#!/bin/sh
# Orbit AI plugin — you own the backend.
# stdin is the selected terminal text (or the open file).
# $1 is the action: explain | suggest
# Default: ollama. Or set ORBIT_AI_BIN to any executable that reads stdin.
set -eu

ACTION="${1:-explain}"
BODY=$(cat)
have() { command -v "$1" >/dev/null 2>&1; }

if [ -z "$BODY" ]; then
  echo "Select text in the terminal (or open a file) then run AI: Explain."
  echo "This plugin never runs by itself."
  exit 0
fi

case "$ACTION" in
  suggest)
    TASK="Suggest a safe shell command for this situation. One command, then one line of why. Do not execute anything."
    ;;
  *)
    TASK="Explain this terminal output. What failed, and what to try next? Do not execute anything."
    ;;
esac

PROMPT="$TASK

---
$BODY
---"

if [ -n "${ORBIT_AI_BIN:-}" ]; then
  printf '%s\n' "$PROMPT" | "$ORBIT_AI_BIN"
  exit 0
fi

if have ollama; then
  MODEL="${ORBIT_AI_MODEL:-llama3.2}"
  printf '%s\n' "$PROMPT" | ollama run "$MODEL"
  exit 0
fi

cat <<EOF
No AI backend configured.

Orbit does not call a cloud API. You pick the tool:

  1. Install Ollama (https://ollama.com) then:  ollama pull llama3.2
  2. Or set ORBIT_AI_BIN to any CLI that reads the prompt on stdin
  3. Or edit this file: ~/.config/orbit/plugins/ai/ask.sh

Then press R in Plugins and run AI: Explain again.
EOF
