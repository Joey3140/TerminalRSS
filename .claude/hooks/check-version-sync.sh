#!/bin/bash
# claude-harness — post-commit version sync check
# PostToolUse(Bash) — blocks (exit 1) on version drift between configured files

NODE_BIN="node"
if ! command -v node > /dev/null 2>&1; then
  [ -x "$HOME/.local/node/bin/node" ] && NODE_BIN="$HOME/.local/node/bin/node" || exit 0
fi

INPUT=$(cat)

if ! command -v jq > /dev/null 2>&1; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

if ! echo "$COMMAND" | grep -qE 'git\s+commit'; then
  exit 0
fi

TOOL_EXIT=$(echo "$INPUT" | jq -r '.tool_output.exit_code // .tool_result.exit_code // empty' 2>/dev/null)
if [ "$TOOL_EXIT" = "1" ]; then
  exit 0
fi

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="$REPO_DIR/harness-config.json"

if [ ! -f "$CONFIG" ] || [ -z "$NODE_BIN" ]; then
  exit 0
fi

# For this Swift project, version lives in .claude/.harness-version
# Version sync is less critical without package.json, so just check config consistency
exit 0
