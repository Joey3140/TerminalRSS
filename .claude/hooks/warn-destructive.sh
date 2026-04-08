#!/bin/bash
# claude-harness — warn on destructive bash commands
# PreToolUse(Bash) — warn-only (exit 0), never blocks

INPUT=$(cat)

if ! command -v jq > /dev/null 2>&1; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
  exit 0
fi

WARNING=""

if echo "$COMMAND" | grep -qE 'rm\s+-(rf|fr|r)\s'; then
  if ! echo "$COMMAND" | grep -qE '(node_modules|\.backups|dist/|\.cache|__pycache__|\.next|\.turbo|\.build)'; then
    WARNING="DESTRUCTIVE: rm -rf on non-safe path"
  fi
fi

if echo "$COMMAND" | grep -qE 'git\s+reset\s+--hard'; then
  WARNING="DESTRUCTIVE: git reset --hard discards all uncommitted changes"
fi

if echo "$COMMAND" | grep -qE 'git\s+checkout\s+--\s+\.'; then
  WARNING="DESTRUCTIVE: git checkout -- . discards all unstaged changes"
fi

if echo "$COMMAND" | grep -qE 'git\s+restore\s+\.'; then
  WARNING="DESTRUCTIVE: git restore . discards all unstaged changes"
fi

if echo "$COMMAND" | grep -qE 'git\s+clean\s+-[a-zA-Z]*f'; then
  WARNING="DESTRUCTIVE: git clean -f permanently deletes untracked files"
fi

if echo "$COMMAND" | grep -qE 'git\s+branch\s+-D\s'; then
  WARNING="DESTRUCTIVE: git branch -D force-deletes branch without merge check"
fi

if echo "$COMMAND" | grep -qiE 'DROP\s+(TABLE|DATABASE|INDEX|COLLECTION)'; then
  WARNING="DESTRUCTIVE: SQL DROP operation"
fi

if echo "$COMMAND" | grep -qiE 'DELETE\s+FROM\s' && ! echo "$COMMAND" | grep -qiE 'WHERE'; then
  WARNING="DESTRUCTIVE: DELETE FROM without WHERE clause"
fi

if [ -n "$WARNING" ]; then
  echo "" >&2
  echo "============================================" >&2
  echo "  $WARNING" >&2
  echo "============================================" >&2
  echo "  Command: $(echo "$COMMAND" | head -c 200)" >&2
  echo "  This is a warn-only hook — command will proceed." >&2
  echo "============================================" >&2
  echo "" >&2
fi

exit 0
