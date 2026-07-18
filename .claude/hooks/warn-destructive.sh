#!/bin/bash
# claude-harness — warn on destructive bash commands
# PreToolUse(Bash) — warn-only, never blocks
# Emits JSON systemMessage so the warning is actually surfaced (PreToolUse
# exit-0 stderr is shown to no one — the old approach warned into the void).

INPUT=$(cat)

if ! command -v jq > /dev/null 2>&1; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
  exit 0
fi

WARNING=""

# rm -rf outside safe directories
if echo "$COMMAND" | grep -qE 'rm\s+-(rf|fr|r)\s'; then
  if ! echo "$COMMAND" | grep -qE '(node_modules|\.backups|dist/|\.cache|__pycache__|\.next|\.turbo)'; then
    WARNING="DESTRUCTIVE: rm -rf on non-safe path"
  fi
fi

# git reset --hard
if echo "$COMMAND" | grep -qE 'git\s+reset\s+--hard'; then
  WARNING="DESTRUCTIVE: git reset --hard discards all uncommitted changes"
fi

# git checkout -- . (restore all)
if echo "$COMMAND" | grep -qE 'git\s+checkout\s+--\s+\.'; then
  WARNING="DESTRUCTIVE: git checkout -- . discards all unstaged changes"
fi

# git restore .
if echo "$COMMAND" | grep -qE 'git\s+restore\s+\.'; then
  WARNING="DESTRUCTIVE: git restore . discards all unstaged changes"
fi

# git clean -f
if echo "$COMMAND" | grep -qE 'git\s+clean\s+-[a-zA-Z]*f'; then
  WARNING="DESTRUCTIVE: git clean -f permanently deletes untracked files"
fi

# git branch -D (force delete)
if echo "$COMMAND" | grep -qE 'git\s+branch\s+-D\s'; then
  WARNING="DESTRUCTIVE: git branch -D force-deletes branch without merge check"
fi

# SQL destructive operations
if echo "$COMMAND" | grep -qiE 'DROP\s+(TABLE|DATABASE|INDEX|COLLECTION)'; then
  WARNING="DESTRUCTIVE: SQL DROP operation"
fi

if echo "$COMMAND" | grep -qiE 'DELETE\s+FROM\s' && ! echo "$COMMAND" | grep -qiE 'WHERE'; then
  WARNING="DESTRUCTIVE: DELETE FROM without WHERE clause"
fi

if echo "$COMMAND" | grep -qiE 'TRUNCATE\s'; then
  WARNING="DESTRUCTIVE: TRUNCATE operation"
fi

# File truncation via redirect to absolute paths
if echo "$COMMAND" | grep -qE '>\s*/[^ ]' && ! echo "$COMMAND" | grep -qE '>>'; then
  if echo "$COMMAND" | grep -qE '>\s*/(Users|home|etc|var)'; then
    WARNING="CAUTION: overwrite redirect to absolute path"
  fi
fi

if [ -n "$WARNING" ]; then
  CMD_SNIPPET=$(echo "$COMMAND" | head -c 200)
  # systemMessage is the only warn-without-block channel that gets displayed
  jq -n --arg msg "$WARNING — command will proceed. Command: $CMD_SNIPPET" \
    '{systemMessage: $msg}'
fi

exit 0
