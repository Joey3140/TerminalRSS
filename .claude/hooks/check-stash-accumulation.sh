#!/bin/bash
# claude-harness — warn when git stashes accumulate after a commit
# PostToolUse(Bash) — warn-only (exit 0); the warning goes to Claude as additionalContext

INPUT=$(cat)

if ! command -v jq > /dev/null 2>&1; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Only run after git commit commands
if ! echo "$COMMAND" | grep -qE 'git\s+commit'; then
  exit 0
fi

# Skip if the commit failed (any nonzero exit, not just 1)
TOOL_EXIT=$(echo "$INPUT" | jq -r '.tool_output.exit_code // .tool_result.exit_code // empty' 2>/dev/null)
if [ -n "$TOOL_EXIT" ] && [ "$TOOL_EXIT" != "0" ]; then
  exit 0
fi

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_DIR" || exit 0

STASH_COUNT=$(git stash list 2>/dev/null | wc -l | tr -d ' ')

if [ "$STASH_COUNT" -gt 0 ]; then
  # Emitted as PostToolUse additionalContext on stdout. It used to go to stderr
  # with exit 0, which Claude Code shows to no one — the warning never reached
  # the agent that could act on it.
  MSG="STASH WARNING: $STASH_COUNT stash(es) exist after this commit:
$(git stash list 2>/dev/null | sed 's/^/  /')
Stashes rot fast. Check each with 'git stash show -p stash@{N}': drop it if the work is already committed, otherwise commit it or name it in the handoff."
  jq -n --arg ctx "$MSG" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
fi

exit 0
