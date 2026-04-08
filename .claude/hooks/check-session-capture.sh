#!/bin/bash
# claude-harness — missed memory crystallization detector
# PostToolUse(Write|Edit) — warn-only, fires on session file writes

INPUT=$(cat)

if ! command -v jq > /dev/null 2>&1; then
  exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

echo "$FILE_PATH" | grep -qE '/project/sessions/session-.*\.md$' || exit 0

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

if [ -n "$CLAUDE_PROJECT_DIR" ]; then
  SANITIZED=$(echo "$CLAUDE_PROJECT_DIR" | sed 's|/|-|g')
  MEMORY_DIR="$HOME/.claude/projects/$SANITIZED/memory"
else
  MEMORY_DIR="$HOME/.claude/projects/-$(echo "$REPO_DIR" | sed 's|/|-|g')/memory"
fi

WARNINGS=""

RECENT_COMMITS=$(cd "$REPO_DIR" && git log --oneline --since="2 hours ago" 2>/dev/null | wc -l | tr -d ' ')

RECENT_MEMORIES=0
if [ -d "$MEMORY_DIR" ]; then
  NOW=$(date +%s)
  TWO_HOURS=$((2 * 3600))
  for f in "$MEMORY_DIR"/*.md; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "MEMORY.md" ] && continue
    if [ "$(uname)" = "Darwin" ]; then
      MTIME=$(stat -f '%m' "$f")
    else
      MTIME=$(stat -c '%Y' "$f")
    fi
    AGE=$((NOW - MTIME))
    if [ "$AGE" -lt "$TWO_HOURS" ]; then
      RECENT_MEMORIES=$((RECENT_MEMORIES + 1))
    fi
  done
fi

if [ "$RECENT_COMMITS" -gt 2 ] && [ "$RECENT_MEMORIES" -eq 0 ]; then
  WARNINGS="${WARNINGS}  MISSED CRYSTALLIZATION: $RECENT_COMMITS commits this session but 0 memories saved.\n"
fi

TICKET_CHANGES=$(cd "$REPO_DIR" && git diff --name-only HEAD~${RECENT_COMMITS:-1} HEAD 2>/dev/null | grep 'project/tickets/' | wc -l | tr -d ' ')

PROJECT_MEMORIES=0
if [ -d "$MEMORY_DIR" ]; then
  NOW=$(date +%s)
  TWO_HOURS=$((2 * 3600))
  for f in "$MEMORY_DIR"/project_*.md; do
    [ -f "$f" ] || continue
    if [ "$(uname)" = "Darwin" ]; then
      MTIME=$(stat -f '%m' "$f")
    else
      MTIME=$(stat -c '%Y' "$f")
    fi
    AGE=$((NOW - MTIME))
    if [ "$AGE" -lt "$TWO_HOURS" ]; then
      PROJECT_MEMORIES=$((PROJECT_MEMORIES + 1))
    fi
  done
fi

if [ "$TICKET_CHANGES" -gt 1 ] && [ "$PROJECT_MEMORIES" -eq 0 ]; then
  WARNINGS="${WARNINGS}  TICKET DRIFT: $TICKET_CHANGES ticket files changed but no project memories updated.\n"
fi

if [ -n "$WARNINGS" ]; then
  echo "" >&2
  echo "============================================" >&2
  echo "  SESSION CAPTURE CHECK" >&2
  echo "============================================" >&2
  echo -e "$WARNINGS" >&2
  echo "============================================" >&2
fi

exit 0
