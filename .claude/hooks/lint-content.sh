#!/bin/bash
# claude-harness — content linting wrapper
# PreToolUse(Write|Edit) — delegates to project-specific lint-content-check.js if present
# No-op passthrough by default.

INPUT=$(cat)

if [ -f "$CLAUDE_PROJECT_DIR/.claude/hooks/lint-content-check.js" ]; then
  echo "$INPUT" | node "$CLAUDE_PROJECT_DIR/.claude/hooks/lint-content-check.js"
  exit $?
fi

exit 0
