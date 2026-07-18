#!/bin/bash
# claude-harness — backup untracked files before Write/Edit overwrites them
# PreToolUse(Write|Edit) — always exits 0, never blocks

INPUT=$(cat)

if ! command -v jq > /dev/null 2>&1; then
  exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# File must exist to need backup
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# Tracked by git — recoverable from history, no backup needed
if git ls-files --error-unmatch "$FILE_PATH" > /dev/null 2>&1; then
  exit 0
fi

# Untracked file about to be overwritten — back it up
# (guard: unset CLAUDE_PROJECT_DIR would otherwise target /.claude/.backups)
[ -n "$CLAUDE_PROJECT_DIR" ] || exit 0
BACKUP_DIR="$CLAUDE_PROJECT_DIR/.claude/.backups"
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BASENAME=$(basename "$FILE_PATH")
BACKUP_FILE="${BACKUP_DIR}/${BASENAME}.${TIMESTAMP}.$$"

if cp "$FILE_PATH" "$BACKUP_FILE" 2>/dev/null; then
  echo "Backed up untracked file: $FILE_PATH -> $BACKUP_FILE" >&2
else
  echo "BACKUP FAILED for untracked file: $FILE_PATH" >&2
fi

# Prune backups older than 14 days so .backups doesn't grow forever
find "$BACKUP_DIR" -type f -mtime +14 -delete 2>/dev/null

exit 0
