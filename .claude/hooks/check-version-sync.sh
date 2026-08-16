#!/bin/bash
# claude-harness — post-commit version sync check
# PostToolUse(Bash) — exit 2 (fed back to Claude) on version drift between configured files
# Reads version file list from harness-config.json

# Find node binary
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

# Only run after git commit
if ! echo "$COMMAND" | grep -qE 'git\s+commit'; then
  exit 0
fi

# Skip if commit failed (any nonzero exit)
TOOL_EXIT=$(echo "$INPUT" | jq -r '.tool_output.exit_code // .tool_result.exit_code // empty' 2>/dev/null)
if [ -n "$TOOL_EXIT" ] && [ "$TOOL_EXIT" != "0" ]; then
  exit 0
fi

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="$REPO_DIR/harness-config.json"

# Need config to run (NODE_BIN is guaranteed set — the fallback at the top
# exits 0 when neither PATH node nor ~/.local/node exists; re-checking
# `command -v node` here silently disabled the hook on fallback-node machines)
if [ ! -f "$CONFIG" ]; then
  exit 0
fi

ERRORS=$(H_CONFIG="$CONFIG" H_REPO="$REPO_DIR" "$NODE_BIN" -e "
  const fs = require('fs');
  const path = require('path');
  const config = JSON.parse(fs.readFileSync(process.env.H_CONFIG, 'utf8'));
  const repoDir = process.env.H_REPO;

  const versionFiles = config.versioning?.files || ['package.json'];
  const changelog = config.versioning?.changelog || 'CHANGELOG.md';
  const additionalFiles = config.versioning?.additionalSyncFiles || [];

  // Get primary version from the first version file.
  //
  // JSON (package.json .version) was the ONLY shape understood, so any project
  // whose version lives in a plain-text VERSION file — every Swift/SwiftPM
  // project here, since SwiftPM has no version field — parsed as JSON, threw,
  // fell through to primaryVersion='' and exited 0. The hook reported success
  // while checking nothing at all. Silent no-ops are worse than absent hooks:
  // they look like coverage.
  let primaryVersion = '';
  const primaryFile = path.join(repoDir, versionFiles[0]);
  if (fs.existsSync(primaryFile)) {
    const raw = fs.readFileSync(primaryFile, 'utf8');
    if (primaryFile.endsWith('.json')) {
      try {
        primaryVersion = JSON.parse(raw).version || '';
      } catch (e) {}
    } else {
      // Plain-text version file: the whole contents are the version, e.g.
      // \`1.4.2\\n\`. Anchored so a stray semver inside a larger file (a
      // Package.swift dependency pin, say) can't be mistaken for the
      // project's own version — that would be worse than not checking.
      const m = raw.trim().match(/^v?(\\d+\\.\\d+\\.\\d+(?:[-+][0-9A-Za-z.-]+)?)$/);
      primaryVersion = m ? m[1] : '';
    }
  }

  if (!primaryVersion) {
    process.exit(0); // Can't check without a primary version
  }

  const errors = [];

  // Check changelog has the same version at the top
  const clPath = path.join(repoDir, changelog);
  if (fs.existsSync(clPath)) {
    const clContent = fs.readFileSync(clPath, 'utf8');
    const match = clContent.match(/\\d+\\.\\d+\\.\\d+/);
    if (match && match[0] !== primaryVersion) {
      errors.push(changelog + ': top version ' + match[0] + ' (expected ' + primaryVersion + ')');
    }
  }

  // Check additional sync files exist and contain the version
  for (const af of additionalFiles) {
    const afPath = path.join(repoDir, af);
    if (fs.existsSync(afPath)) {
      const content = fs.readFileSync(afPath, 'utf8');
      if (!content.includes(primaryVersion)) {
        errors.push(af + ': does not contain version ' + primaryVersion);
      }
    }
  }

  if (errors.length > 0) {
    console.log('Primary version (' + versionFiles[0] + '): ' + primaryVersion);
    errors.forEach(e => console.log('  - ' + e));
  }
" 2>/dev/null)

if [ -n "$ERRORS" ]; then
  echo "" >&2
  echo "============================================" >&2
  echo "  VERSION SYNC DRIFT DETECTED" >&2
  echo "============================================" >&2
  echo "$ERRORS" >&2
  echo "" >&2
  echo "  Fix the drift before pushing." >&2
  echo "============================================" >&2
  echo "" >&2
  # Exit 2: PostToolUse feeds stderr back to Claude; exit 1 is user-only
  exit 2
fi

exit 0
