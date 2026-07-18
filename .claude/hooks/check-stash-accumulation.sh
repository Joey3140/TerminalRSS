#!/bin/bash
# claude-harness — warn when git stashes accumulate after a commit
# PostToolUse(Bash) — warn-only (exit 0)

INPUT=$(cat)

if ! command -v jq > /dev/null 2>&1; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Only run after git commit commands
if ! echo "$COMMAND" | grep -qE 'git\s+commit'; then
  exit 0
fi

# Skip if the commit failed
TOOL_EXIT=$(echo "$INPUT" | jq -r '.tool_output.exit_code // .tool_result.exit_code // empty' 2>/dev/null)
if [ "$TOOL_EXIT" = "1" ]; then
  exit 0
fi

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_DIR" || exit 0

STASH_COUNT=$(git stash list 2>/dev/null | wc -l | tr -d ' ')

if [ "$STASH_COUNT" -gt 0 ]; then
  echo "" >&2
  echo "============================================" >&2
  echo "  STASH WARNING: $STASH_COUNT stash(es) exist" >&2
  echo "============================================" >&2
  git stash list 2>/dev/null | while IFS= read -r line; do
    echo "  $line" >&2
  done
  echo "" >&2
  echo "  Stashes rot fast. Review with 'git stash show stash@{N}'" >&2
  echo "  and drop if already merged: 'git stash drop stash@{N}'" >&2
  echo "============================================" >&2
  echo "" >&2
fi

exit 0
