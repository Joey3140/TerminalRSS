#!/bin/bash
# Post-commit hook: push to GitHub and rebuild/install the app
# PostToolUse(Bash) — runs after git commit succeeds

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
BRANCH=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)

if [ -z "$BRANCH" ]; then
  exit 0
fi

echo "" >&2
echo "============================================" >&2
echo "  SHIPPING: push + rebuild" >&2
echo "============================================" >&2

git -C "$REPO_DIR" push origin "$BRANCH" 2>&1 | while read -r line; do echo "  [push] $line" >&2; done
PUSH_EXIT=${PIPESTATUS[0]}

if [ "$PUSH_EXIT" -ne 0 ]; then
  echo "  [push] FAILED (exit $PUSH_EXIT)" >&2
  echo "============================================" >&2
fi

cd "$REPO_DIR"
swift build -c release 2>&1 | tail -3 | while read -r line; do echo "  [build] $line" >&2; done
BUILD_EXIT=${PIPESTATUS[0]}

if [ "$BUILD_EXIT" -eq 0 ]; then
  cp "$REPO_DIR/.build/release/TerminalRSS" "/Applications/TerminalRSS.app/Contents/MacOS/TerminalRSS" 2>/dev/null
  echo "  [install] Copied to /Applications/TerminalRSS.app" >&2
else
  echo "  [build] FAILED (exit $BUILD_EXIT)" >&2
fi

echo "============================================" >&2

exit 0
