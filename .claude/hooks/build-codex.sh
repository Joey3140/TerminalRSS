#!/bin/bash
# claude-harness — regenerate .ai-codex/ structural index
# UserPromptSubmit hook — runs only when source files are newer than the codex.

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

# Skip rebuild if codex is fresher than any tracked source file.
CODEX_DIR="$REPO_DIR/.ai-codex"
if [ -d "$CODEX_DIR" ] && command -v git > /dev/null 2>&1; then
  CODEX_NEWEST=$(find "$CODEX_DIR" -name '*.md' -type f -print0 2>/dev/null \
    | xargs -0 stat -f '%m' 2>/dev/null | sort -nr | head -1)
  # Single stat fork via xargs — a per-file loop scales linearly with repo
  # size and this runs on every prompt (5s budget)
  SOURCE_NEWEST=$(cd "$REPO_DIR" && git ls-files -z -- '*.js' '*.ts' '*.jsx' '*.tsx' 2>/dev/null \
    | xargs -0 stat -f '%m' 2>/dev/null | sort -nr | head -1)
  if [ -n "$CODEX_NEWEST" ] && [ -n "$SOURCE_NEWEST" ] && [ "$CODEX_NEWEST" -ge "$SOURCE_NEWEST" ]; then
    exit 0
  fi
fi

cd "$REPO_DIR" && "$NODE_BIN" "$SCRIPT" > /dev/null 2>&1
exit 0
