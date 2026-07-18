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

# Only run after an actual git commit invocation — loose 'git\s+commit'
# matched commands that merely mention it (and this hook pushes + builds)
if ! echo "$COMMAND" | grep -qE '(^|[;&|])[[:space:]]*git[[:space:]]+(-C[[:space:]]+("[^"]*"|[^[:space:]]+)[[:space:]]+)?commit([[:space:]]|$)'; then
  exit 0
fi

# Skip if commit failed (any nonzero exit, not just 1 — 128/129 = bad ref, lock held)
TOOL_EXIT=$(echo "$INPUT" | jq -r '.tool_output.exit_code // .tool_result.exit_code // empty' 2>/dev/null)
if [ -n "$TOOL_EXIT" ] && [ "$TOOL_EXIT" != "0" ]; then
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

FAILURES=""

git -C "$REPO_DIR" push origin "$BRANCH" 2>&1 | while read -r line; do echo "  [push] $line" >&2; done
PUSH_EXIT=${PIPESTATUS[0]}

if [ "$PUSH_EXIT" -ne 0 ]; then
  echo "  [push] FAILED (exit $PUSH_EXIT)" >&2
  FAILURES="push"
fi

# --- Rebuild and install via build.sh ---
# build.sh owns bundle assembly, signing, and install — raw cp over the
# installed binary breaks the code signature (SIGKILL if the app is running).
BUILD_LOG=$(mktemp)
bash "$REPO_DIR/build.sh" > "$BUILD_LOG" 2>&1
BUILD_EXIT=$?

if [ "$BUILD_EXIT" -eq 0 ]; then
  tail -3 "$BUILD_LOG" | sed 's/^/  [build] /' >&2
else
  tail -20 "$BUILD_LOG" | sed 's/^/  [build] /' >&2
  echo "  [build] FAILED (exit $BUILD_EXIT)" >&2
  FAILURES="${FAILURES:+$FAILURES, }build"
fi
rm -f "$BUILD_LOG"

echo "============================================" >&2

# Exit 2 so Claude actually sees the failure (exit 0 stderr goes nowhere)
if [ -n "$FAILURES" ]; then
  exit 2
fi

exit 0
