#!/bin/bash
# claude-harness — import/export mismatch detector for multi-agent builds
# PostToolUse(Bash) — exit 2 (fed back to Claude) on confirmed mismatches
# Reads .agent-interfaces-allow for known-good renames during migration

INPUT=$(cat)

if ! command -v jq > /dev/null 2>&1; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
if [ -z "$COMMAND" ]; then
  exit 0
fi

# Only fire after git operations that create commits — the check always diffs
# HEAD~1..HEAD, which is unrelated to what a checkout/pull changed
IS_GIT_OP=false
echo "$COMMAND" | grep -qE 'git (merge|commit|cherry-pick)' && IS_GIT_OP=true

if [ "$IS_GIT_OP" != "true" ]; then
  exit 0
fi

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ALLOWLIST="$REPO_DIR/.agent-interfaces-allow"
BLOCKERS=""
WARNINGS=""

# Load allowlist
ALLOWED_PATTERNS=""
if [ -f "$ALLOWLIST" ]; then
  ALLOWED_PATTERNS=$(grep -v '^\s*#' "$ALLOWLIST" | grep -v '^\s*$')
fi

is_allowed() {
  local imported="$1"
  if [ -z "$ALLOWED_PATTERNS" ]; then
    return 1
  fi
  echo "$ALLOWED_PATTERNS" | grep -qF "$imported" && return 0
  return 1
}

# Get files changed in the last commit
CHANGED_FILES=$(cd "$REPO_DIR" && git diff --name-only HEAD~1 HEAD 2>/dev/null | grep -E '\.(js|ts|jsx|tsx)$' || true)

if [ -z "$CHANGED_FILES" ]; then
  exit 0
fi

# Build exports and imports from changed files
EXPORTS_TMP=$(mktemp)
IMPORTS_TMP=$(mktemp)
trap 'rm -f "$EXPORTS_TMP" "$IMPORTS_TMP"' EXIT

for f in $CHANGED_FILES; do
  FULL="$REPO_DIR/$f"
  [ -f "$FULL" ] || continue

  # Extract exports
  grep -oE 'module\.exports\s*=\s*\{[^}]+\}' "$FULL" 2>/dev/null | \
    grep -oE '[a-zA-Z_][a-zA-Z0-9_]*' | \
    while read -r name; do
      [ "$name" = "module" ] || [ "$name" = "exports" ] && continue
      echo "$f:$name" >> "$EXPORTS_TMP"
    done

  grep -oE 'exports\.[a-zA-Z_][a-zA-Z0-9_]*\s*=' "$FULL" 2>/dev/null | \
    grep -oE '\.[a-zA-Z_][a-zA-Z0-9_]*' | sed 's/^\.//' | \
    while read -r name; do
      echo "$f:$name" >> "$EXPORTS_TMP"
    done

  # Extract destructured require() imports
  grep -nE 'const\s*\{[^}]+\}\s*=\s*require\(' "$FULL" 2>/dev/null | \
    while IFS= read -r line; do
      LINE_NUM=$(echo "$line" | cut -d: -f1)
      LINE_CONTENT=$(echo "$line" | cut -d: -f2-)

      REQ_PATH=$(echo "$LINE_CONTENT" | grep -oE "require\(['\"][^'\"]+['\"]\)" | \
        grep -oE "['\"][^'\"]+['\"]" | tr -d "'\"")

      echo "$REQ_PATH" | grep -qE '^\.' || continue

      IMPORTED=$(echo "$LINE_CONTENT" | grep -oE '\{[^}]+\}' | tr -d '{}' | tr ',' '\n' | \
        sed 's/^\s*//' | sed 's/\s*$//' | grep -v '^$')

      for imp_name in $IMPORTED; do
        clean_name=$(echo "$imp_name" | awk '{print $1}')
        echo "$f:$LINE_NUM:$clean_name:$REQ_PATH" >> "$IMPORTS_TMP"
      done
    done
done

# Cross-reference imports vs exports
MISMATCH_COUNT=0
if [ -f "$IMPORTS_TMP" ] && [ -s "$IMPORTS_TMP" ]; then
  while IFS=: read -r src_file line_num imp_name req_path; do
    [ -z "$imp_name" ] && continue

    SRC_DIR=$(dirname "$REPO_DIR/$src_file")
    RESOLVED=""
    for candidate in "$SRC_DIR/$req_path.js" "$SRC_DIR/$req_path/index.js" "$SRC_DIR/$req_path"; do
      if [ -f "$candidate" ]; then
        # Canonicalize before stripping the prefix — require('../x') paths
        # contain "/../" and never matched the exports table otherwise
        CANON="$(cd "$(dirname "$candidate")" 2>/dev/null && pwd)/$(basename "$candidate")"
        RESOLVED=${CANON#"$REPO_DIR"/}
        break
      fi
    done

    [ -z "$RESOLVED" ] && continue

    if [ -f "$EXPORTS_TMP" ] && ! grep -q "^$RESOLVED:$imp_name$" "$EXPORTS_TMP"; then
      if [ -f "$REPO_DIR/$RESOLVED" ] && ! grep -qE "(exports\.$imp_name\s*=|$imp_name\s*[,}])" "$REPO_DIR/$RESOLVED" 2>/dev/null; then
        if ! is_allowed "$imp_name"; then
          BLOCKERS="${BLOCKERS}  IMPORT MISMATCH: $src_file:$line_num imports '$imp_name' from $req_path but $RESOLVED does not export it\n"
          MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
        fi
      fi
    fi
  done < "$IMPORTS_TMP"
fi

if [ -n "$BLOCKERS" ]; then
  echo "" >&2
  echo "============================================" >&2
  echo "  INTERFACE MISMATCH — $MISMATCH_COUNT found" >&2
  echo "============================================" >&2
  echo -e "$BLOCKERS" >&2
  echo "  To allowlist a rename during migration:" >&2
  echo "  echo 'old_name -> new_name' >> .agent-interfaces-allow" >&2
  echo "============================================" >&2
  # Exit 2: PostToolUse feeds stderr back to Claude; exit 1 is user-only
  exit 2
fi

exit 0
