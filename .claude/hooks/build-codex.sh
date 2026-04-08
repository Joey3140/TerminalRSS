#!/bin/bash
# claude-harness — regenerate .ai-codex/ structural index
# UserPromptSubmit hook — runs every message, output suppressed

cat > /dev/null

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_DIR/scripts/build-codex.js"

if [ ! -f "$SCRIPT" ]; then
  exit 0
fi

NODE_BIN="node"
if ! command -v node > /dev/null 2>&1; then
  if [ -x "$HOME/.local/node/bin/node" ]; then
    NODE_BIN="$HOME/.local/node/bin/node"
  else
    exit 0
  fi
fi

cd "$REPO_DIR" && "$NODE_BIN" "$SCRIPT" > /dev/null 2>&1
exit 0
