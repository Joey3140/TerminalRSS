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

if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

if git ls-files --error-unmatch "$FILE_PATH" > /dev/null 2>&1; then
  exit 0
fi

BACKUP_DIR="$CLAUDE_PROJECT_DIR/.claude/.backups"
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BASENAME=$(basename "$FILE_PATH")
BACKUP_FILE="${BACKUP_DIR}/${BASENAME}.${TIMESTAMP}.$$"

cp "$FILE_PATH" "$BACKUP_FILE"
echo "Backed up untracked file: $FILE_PATH -> $BACKUP_FILE" >&2

exit 0
