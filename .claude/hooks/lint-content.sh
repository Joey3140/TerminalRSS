#!/bin/bash
# claude-harness — content linting wrapper
# PreToolUse(Write|Edit) — delegates to project-specific lint-content-check.js if present
# No-op passthrough by default. To enable: create .claude/hooks/lint-content-check.js
# with a Node.js script that reads JSON from stdin and exits nonzero to block, 0 to pass.

INPUT=$(cat)

# Find node binary (hook subshell PATH may not include it)
NODE_BIN="node"
if ! command -v node > /dev/null 2>&1; then
  [ -x "$HOME/.local/node/bin/node" ] && NODE_BIN="$HOME/.local/node/bin/node" || exit 0
fi

# If project has a custom lint-content-check.js, delegate to it
if [ -f "$CLAUDE_PROJECT_DIR/.claude/hooks/lint-content-check.js" ]; then
  if ! echo "$INPUT" | "$NODE_BIN" "$CLAUDE_PROJECT_DIR/.claude/hooks/lint-content-check.js"; then
    # PreToolUse blocks only on exit 2 (stderr fed to Claude); exit 1 is user-only
    exit 2
  fi
fi

exit 0
