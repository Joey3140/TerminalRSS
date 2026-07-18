#!/bin/bash
# claude-harness — post-edit validator
# PostToolUse(Write|Edit) — exit 2 (fed back to Claude) on broken files, warns on reminders
# Reads ticket statuses/priorities from harness-config.json

# Find node binary (hooks can't source lib/util.sh)
NODE_BIN="node"
if ! command -v node > /dev/null 2>&1; then
  if [ -x "$HOME/.local/node/bin/node" ]; then
    NODE_BIN="$HOME/.local/node/bin/node"
  else
    # No node available — skip node-dependent checks
    NODE_BIN=""
  fi
fi

INPUT=$(cat)

if ! command -v jq > /dev/null 2>&1; then
  exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
  exit 0
fi

BASENAME=$(basename "$FILE_PATH")
EXT="${FILE_PATH##*.}"
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="$REPO_DIR/harness-config.json"
WARNINGS=""
BLOCKERS=""

# ─── BLOCK: CONFIG.JSON INTEGRITY ────────────────────────────────────
if [ -n "$NODE_BIN" ] && echo "$FILE_PATH" | grep -q '\.claude/config\.json$'; then
  if [ -f "$FILE_PATH" ]; then
    if ! H_FILE="$FILE_PATH" "$NODE_BIN" -e "JSON.parse(require('fs').readFileSync(process.env.H_FILE,'utf8'))" 2>/dev/null; then
      BLOCKERS="${BLOCKERS}  CONFIG BROKEN: .claude/config.json is not valid JSON — fix immediately\n"
    fi
  fi
fi

# ─── BLOCK: JS SYNTAX VALIDATION ─────────────────────────────────────
if [ -n "$NODE_BIN" ] && [ "$EXT" = "js" ] && [ -f "$FILE_PATH" ]; then
  if ! SYNTAX_ERR=$("$NODE_BIN" -c "$FILE_PATH" 2>&1); then
    ERR_LINE=$(echo "$SYNTAX_ERR" | grep -E 'SyntaxError|Unexpected' | head -1)
    BLOCKERS="${BLOCKERS}  SYNTAX ERROR in $BASENAME: $ERR_LINE — file will not execute\n"
  fi
fi

# ─── BLOCK: JSON SYNTAX VALIDATION ───────────────────────────────────
if [ -n "$NODE_BIN" ] && [ "$EXT" = "json" ] && [ -f "$FILE_PATH" ]; then
  if ! H_FILE="$FILE_PATH" "$NODE_BIN" -e "JSON.parse(require('fs').readFileSync(process.env.H_FILE,'utf8'))" 2>/dev/null; then
    BLOCKERS="${BLOCKERS}  JSON BROKEN: $BASENAME is not valid JSON\n"
  fi
fi

# ─── BLOCK: TICKET FRONTMATTER VALIDATION ────────────────────────────
# Honors tickets.directory from harness-config.json, and also matches the
# cross-project ~/Harness Projects/tickets/ system (was hardcoded to
# /project/tickets/, so configurable and top-level ticket dirs got no validation)
TICKET_DIR_REL="project/tickets"
if [ -f "$CONFIG" ] && [ -n "$NODE_BIN" ]; then
  CFG_TICKET_DIR=$(H_CONFIG="$CONFIG" "$NODE_BIN" -e "
    const c = JSON.parse(require('fs').readFileSync(process.env.H_CONFIG,'utf8'));
    process.stdout.write(c.tickets?.directory || '');
  " 2>/dev/null)
  [ -n "$CFG_TICKET_DIR" ] && TICKET_DIR_REL="$CFG_TICKET_DIR"
fi
if echo "$FILE_PATH" | grep -qE "/(${TICKET_DIR_REL}|tickets)/TICKET-[^/]*\.md$"; then
  if [ -f "$FILE_PATH" ]; then
    HAS_STATUS=$(grep -c '^\*\*Status:\*\*' "$FILE_PATH" 2>/dev/null | xargs)
    HAS_PRIORITY=$(grep -c '^\*\*Priority:\*\*' "$FILE_PATH" 2>/dev/null | xargs)

    if [ "$HAS_STATUS" -eq 0 ]; then
      BLOCKERS="${BLOCKERS}  TICKET: $BASENAME missing **Status:** field\n"
    else
      STATUS_VAL=$(grep '^\*\*Status:\*\*' "$FILE_PATH" | head -1 | sed 's/\*\*Status:\*\* *//' | sed 's/ *$//')
      # Validate against config statuses or default list
      VALID_STATUSES="BACKLOG NOT_SPECCED SPEC_READY IN_PROGRESS IN_REVIEW NEEDS_HUMAN"
      if [ -f "$CONFIG" ] && [ -n "$NODE_BIN" ]; then
        VALID_STATUSES=$(H_CONFIG="$CONFIG" "$NODE_BIN" -e "
          const c = JSON.parse(require('fs').readFileSync(process.env.H_CONFIG,'utf8'));
          process.stdout.write((c.tickets?.statuses || []).join(' '));
        " 2>/dev/null)
      fi
      VALID=false
      for s in $VALID_STATUSES; do
        [ "$STATUS_VAL" = "$s" ] && VALID=true
      done
      if [ "$VALID" = false ]; then
        BLOCKERS="${BLOCKERS}  TICKET: $BASENAME has invalid status '$STATUS_VAL' — must be one of: $VALID_STATUSES\n"
      fi
    fi

    if [ "$HAS_PRIORITY" -eq 0 ]; then
      BLOCKERS="${BLOCKERS}  TICKET: $BASENAME missing **Priority:** field\n"
    else
      PRIORITY_VAL=$(grep '^\*\*Priority:\*\*' "$FILE_PATH" | head -1 | sed 's/\*\*Priority:\*\* *//' | sed 's/ *$//')
      VALID_PRIORITIES="P0 P1 P2 P3 P5"
      if [ -f "$CONFIG" ] && [ -n "$NODE_BIN" ]; then
        VALID_PRIORITIES=$(H_CONFIG="$CONFIG" "$NODE_BIN" -e "
          const c = JSON.parse(require('fs').readFileSync(process.env.H_CONFIG,'utf8'));
          process.stdout.write((c.tickets?.priorities || []).join(' '));
        " 2>/dev/null)
      fi
      VALID=false
      for p in $VALID_PRIORITIES; do
        [ "$PRIORITY_VAL" = "$p" ] && VALID=true
      done
      if [ "$VALID" = false ]; then
        BLOCKERS="${BLOCKERS}  TICKET: $BASENAME has invalid priority '$PRIORITY_VAL' — must be one of: $VALID_PRIORITIES\n"
      fi
    fi
  fi
fi

# ─── WARN: SESSION FILE STRUCTURE ────────────────────────────────────
if echo "$FILE_PATH" | grep -qE '/project/sessions/session-.*\.md$'; then
  if [ -f "$FILE_PATH" ]; then
    SESSION_WARNINGS=""
    grep -q '^\*\*Start\*\*\|^| \*\*Start\*\*' "$FILE_PATH" 2>/dev/null || SESSION_WARNINGS="${SESSION_WARNINGS}missing Start; "
    grep -q '^\*\*Branch\*\*\|^| \*\*Branch\*\*' "$FILE_PATH" 2>/dev/null || SESSION_WARNINGS="${SESSION_WARNINGS}missing Branch; "
    grep -q '## Summary\|## Work Log' "$FILE_PATH" 2>/dev/null || SESSION_WARNINGS="${SESSION_WARNINGS}missing Summary or Work Log; "
    if [ -n "$SESSION_WARNINGS" ]; then
      WARNINGS="${WARNINGS}  SESSION: $BASENAME has gaps: ${SESSION_WARNINGS%%; } — fix for clean handoff\n"
    fi
  fi
fi

# ─── OUTPUT ───────────────────────────────────────────────────────────
if [ -n "$WARNINGS" ]; then
  echo "" >&2
  echo "============================================" >&2
  echo "  POST-EDIT INFO — $BASENAME" >&2
  echo "============================================" >&2
  echo -e "$WARNINGS" >&2
  echo "============================================" >&2
fi

if [ -n "$BLOCKERS" ]; then
  echo "" >&2
  echo "============================================" >&2
  echo "  POST-EDIT BROKEN — $BASENAME" >&2
  echo "============================================" >&2
  echo -e "$BLOCKERS" >&2
  echo "  The edit landed but the file is broken." >&2
  echo "  Fix this before doing anything else." >&2
  echo "============================================" >&2
  # Exit 2: PostToolUse feeds stderr back to Claude; exit 1 is user-only
  exit 2
fi

exit 0
