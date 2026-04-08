#!/bin/bash
# claude-harness — post-merge regression check
# PostToolUse(Bash) — blocks (exit 1) if critical markers dropped to zero

NODE_BIN="node"
if ! command -v node > /dev/null 2>&1; then
  [ -x "$HOME/.local/node/bin/node" ] && NODE_BIN="$HOME/.local/node/bin/node" || NODE_BIN=""
fi

INPUT=$(cat)

if ! command -v jq > /dev/null 2>&1; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

if echo "$COMMAND" | grep -qE 'git\s+merge-(base|tree)'; then
  exit 0
fi
if ! echo "$COMMAND" | grep -qE 'git\s+merge\b'; then
  exit 0
fi

TOOL_EXIT=$(echo "$INPUT" | jq -r '.tool_output.exit_code // .tool_result.exit_code // empty' 2>/dev/null)
if [ "$TOOL_EXIT" = "1" ]; then
  exit 0
fi

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_DIR" || exit 0
CONFIG="$REPO_DIR/harness-config.json"

MERGE_HEAD=$(git rev-parse HEAD 2>/dev/null)
PRE_MERGE=$(git rev-parse HEAD^1 2>/dev/null)

if [ -z "$MERGE_HEAD" ] || [ -z "$PRE_MERGE" ]; then
  exit 0
fi

PARENT_COUNT=$(git cat-file -p HEAD 2>/dev/null | grep -c '^parent ')
if [ "$PARENT_COUNT" -lt 2 ]; then
  exit 0
fi

CHANGED_FILES=$(git diff --name-only "$PRE_MERGE" "$MERGE_HEAD" 2>/dev/null)
if [ -z "$CHANGED_FILES" ]; then
  exit 0
fi

MARKERS=""
if [ -f "$CONFIG" ] && [ -n "$NODE_BIN" ]; then
  MARKERS=$("$NODE_BIN" -e "
    const c = JSON.parse(require('fs').readFileSync('$CONFIG','utf8'));
    const m = c.hooks?.criticalMarkers || [];
    process.stdout.write(m.join(' '));
  " 2>/dev/null)
fi

DEL_THRESHOLD=-50
ADD_THRESHOLD=500
if [ -f "$CONFIG" ] && [ -n "$NODE_BIN" ]; then
  DEL_THRESHOLD=$("$NODE_BIN" -e "
    const c = JSON.parse(require('fs').readFileSync('$CONFIG','utf8'));
    process.stdout.write(String(c.hooks?.sizeRegression?.deletedLines || -50));
  " 2>/dev/null)
  ADD_THRESHOLD=$("$NODE_BIN" -e "
    const c = JSON.parse(require('fs').readFileSync('$CONFIG','utf8'));
    process.stdout.write(String(c.hooks?.sizeRegression?.addedLines || 500));
  " 2>/dev/null)
fi

REGRESSIONS=""
SIZE_WARNINGS=""

while IFS= read -r FILE; do
  case "$FILE" in
    *.swift|*.js|*.ts|*.jsx|*.tsx) ;;
    *) continue ;;
  esac

  if ! git show "${MERGE_HEAD}:${FILE}" > /dev/null 2>&1; then
    continue
  fi

  PRE_SIZE=$(git show "${PRE_MERGE}:${FILE}" 2>/dev/null | wc -l | tr -d ' ')
  POST_SIZE=$(git show "${MERGE_HEAD}:${FILE}" 2>/dev/null | wc -l | tr -d ' ')
  PRE_SIZE=${PRE_SIZE:-0}
  POST_SIZE=${POST_SIZE:-0}

  if [ "$PRE_SIZE" -gt 0 ] && [ "$POST_SIZE" -gt 0 ]; then
    DIFF=$((POST_SIZE - PRE_SIZE))
    if [ "$DIFF" -lt "$DEL_THRESHOLD" ]; then
      SIZE_WARNINGS="${SIZE_WARNINGS}  - ${FILE}: ${PRE_SIZE} -> ${POST_SIZE} lines (${DIFF})\n"
    fi
    if [ "$DIFF" -gt "$ADD_THRESHOLD" ]; then
      SIZE_WARNINGS="${SIZE_WARNINGS}  - ${FILE}: ${PRE_SIZE} -> ${POST_SIZE} lines (+${DIFF}, possible stale revert)\n"
    fi
  fi

  if [ -n "$MARKERS" ]; then
    for MARKER in $MARKERS; do
      PRE_COUNT=$(git show "${PRE_MERGE}:${FILE}" 2>/dev/null | grep -c "$MARKER" 2>/dev/null || echo "0")
      POST_COUNT=$(git show "${MERGE_HEAD}:${FILE}" 2>/dev/null | grep -c "$MARKER" 2>/dev/null || echo "0")
      if [ "$PRE_COUNT" -gt "0" ] && [ "$POST_COUNT" -eq "0" ]; then
        REGRESSIONS="${REGRESSIONS}  - ${FILE}: ${MARKER} DROPPED (${PRE_COUNT} -> 0)\n"
      fi
    done
  fi
done <<< "$CHANGED_FILES"

if [ -n "$REGRESSIONS" ]; then
  echo "" >&2
  echo "============================================" >&2
  echo "  MERGE REGRESSION DETECTED — BLOCKING" >&2
  echo "============================================" >&2
  echo -e "$REGRESSIONS" >&2
  if [ -n "$SIZE_WARNINGS" ]; then
    echo "  Size regressions:" >&2
    echo -e "$SIZE_WARNINGS" >&2
  fi
  echo "============================================" >&2
  exit 1
fi

if [ -n "$SIZE_WARNINGS" ]; then
  echo "" >&2
  echo "============================================" >&2
  echo "  MERGE SIZE WARNING (non-blocking)" >&2
  echo "============================================" >&2
  echo -e "$SIZE_WARNINGS" >&2
  echo "============================================" >&2
fi

exit 0
