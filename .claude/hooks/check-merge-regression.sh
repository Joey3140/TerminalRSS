#!/bin/bash
# claude-harness — post-merge regression check
# PostToolUse(Bash) — exit 2 (fed back to Claude) if critical markers dropped to zero
# Reads marker list from harness-config.json hooks.criticalMarkers

# Find node binary
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

# Only run after git merge (not merge-base, merge-tree)
if echo "$COMMAND" | grep -qE 'git\s+merge-(base|tree)'; then
  exit 0
fi
if ! echo "$COMMAND" | grep -qE 'git\s+merge\b'; then
  exit 0
fi

# Skip if merge failed (any nonzero exit)
TOOL_EXIT=$(echo "$INPUT" | jq -r '.tool_output.exit_code // .tool_result.exit_code // empty' 2>/dev/null)
if [ -n "$TOOL_EXIT" ] && [ "$TOOL_EXIT" != "0" ]; then
  exit 0
fi

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_DIR" || exit 0
CONFIG="$REPO_DIR/harness-config.json"

# Get merge head and pre-merge state
MERGE_HEAD=$(git rev-parse HEAD 2>/dev/null)
PRE_MERGE=$(git rev-parse HEAD^1 2>/dev/null)

if [ -z "$MERGE_HEAD" ] || [ -z "$PRE_MERGE" ]; then
  exit 0
fi

# Verify merge commit (2+ parents)
PARENT_COUNT=$(git cat-file -p HEAD 2>/dev/null | grep -c '^parent ')
if [ "$PARENT_COUNT" -lt 2 ]; then
  exit 0
fi

CHANGED_FILES=$(git diff --name-only "$PRE_MERGE" "$MERGE_HEAD" 2>/dev/null)
if [ -z "$CHANGED_FILES" ]; then
  exit 0
fi

# Load critical markers from config
MARKERS=""
if [ -f "$CONFIG" ] && [ -n "$NODE_BIN" ]; then
  MARKERS=$(H_CONFIG="$CONFIG" "$NODE_BIN" -e "
    const c = JSON.parse(require('fs').readFileSync(process.env.H_CONFIG,'utf8'));
    const m = c.hooks?.criticalMarkers || [];
    process.stdout.write(m.join(' '));
  " 2>/dev/null)
fi

# Read size thresholds from config
DEL_THRESHOLD=-50
ADD_THRESHOLD=500
if [ -f "$CONFIG" ] && [ -n "$NODE_BIN" ]; then
  DEL_THRESHOLD=$(H_CONFIG="$CONFIG" "$NODE_BIN" -e "
    const c = JSON.parse(require('fs').readFileSync(process.env.H_CONFIG,'utf8'));
    process.stdout.write(String(c.hooks?.sizeRegression?.deletedLines || -50));
  " 2>/dev/null)
  ADD_THRESHOLD=$(H_CONFIG="$CONFIG" "$NODE_BIN" -e "
    const c = JSON.parse(require('fs').readFileSync(process.env.H_CONFIG,'utf8'));
    process.stdout.write(String(c.hooks?.sizeRegression?.addedLines || 500));
  " 2>/dev/null)
fi

REGRESSIONS=""
SIZE_WARNINGS=""

while IFS= read -r FILE; do
  case "$FILE" in
    *.js|*.ts|*.jsx|*.tsx) ;;
    *) continue ;;
  esac

  # Skip deleted files
  if ! git show "${MERGE_HEAD}:${FILE}" > /dev/null 2>&1; then
    continue
  fi

  # Fetch each revision's content once; size + marker checks reuse it
  # (was 2 git shows per marker per file — fork storm on big merges)
  PRE_CONTENT=$(git show "${PRE_MERGE}:${FILE}" 2>/dev/null)
  POST_CONTENT=$(git show "${MERGE_HEAD}:${FILE}" 2>/dev/null)

  # Size regression check
  if [ -n "$PRE_CONTENT" ]; then
    PRE_SIZE=$(printf '%s\n' "$PRE_CONTENT" | wc -l | tr -d ' ')
  else
    PRE_SIZE=0
  fi
  if [ -n "$POST_CONTENT" ]; then
    POST_SIZE=$(printf '%s\n' "$POST_CONTENT" | wc -l | tr -d ' ')
  else
    POST_SIZE=0
  fi

  if [ "$PRE_SIZE" -gt 0 ] && [ "$POST_SIZE" -gt 0 ]; then
    DIFF=$((POST_SIZE - PRE_SIZE))
    if [ "$DIFF" -lt "$DEL_THRESHOLD" ]; then
      SIZE_WARNINGS="${SIZE_WARNINGS}  - ${FILE}: ${PRE_SIZE} -> ${POST_SIZE} lines (${DIFF})\n"
    fi
    if [ "$DIFF" -gt "$ADD_THRESHOLD" ]; then
      SIZE_WARNINGS="${SIZE_WARNINGS}  - ${FILE}: ${PRE_SIZE} -> ${POST_SIZE} lines (+${DIFF}, possible stale revert)\n"
    fi
  fi

  # Marker regression check
  # NOTE: no `|| echo 0` after grep -c — grep -c already prints 0 on no match
  # while exiting 1, so `|| echo` produced "0\n0" and broke the -eq test,
  # which made this check silently dead.
  if [ -n "$MARKERS" ]; then
    for MARKER in $MARKERS; do
      PRE_COUNT=$(printf '%s' "$PRE_CONTENT" | grep -c -- "$MARKER" 2>/dev/null)
      POST_COUNT=$(printf '%s' "$POST_CONTENT" | grep -c -- "$MARKER" 2>/dev/null)
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
  echo "  Critical markers lost after merge:" >&2
  echo -e "$REGRESSIONS" >&2
  echo "  The target branch version should win conflicts" >&2
  echo "  — reapply your change on top." >&2
  if [ -n "$SIZE_WARNINGS" ]; then
    echo "  Size regressions:" >&2
    echo -e "$SIZE_WARNINGS" >&2
  fi
  echo "============================================" >&2
  # Exit 2: PostToolUse feeds stderr back to Claude; exit 1 is user-only
  exit 2
fi

if [ -n "$SIZE_WARNINGS" ]; then
  echo "" >&2
  echo "============================================" >&2
  echo "  MERGE SIZE WARNING (non-blocking)" >&2
  echo "============================================" >&2
  echo -e "$SIZE_WARNINGS" >&2
  echo "  Verify these are intentional, not stale reverts." >&2
  echo "============================================" >&2
fi

exit 0
