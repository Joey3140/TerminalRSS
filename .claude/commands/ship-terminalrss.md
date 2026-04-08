---
description: "Preflight checks + commit + push to main (local macOS app — no staging)"
---

# Ship to Main

Preflight quality gates, commit, push to `main`. One command from "code done" to "shipped."

This is a local macOS app — no staging branch, no deploy platform, no error monitoring. The build-and-install cycle is the deploy.

## Execution Speed

**Run the entire chain without pausing between steps.** Preflight steps run in parallel where possible. Push proceeds immediately on green. Only stop if a preflight step actually fails.

## Agent Output Contract

When called by another command or subagent (e.g., from `/ham`), end your response with:

```
SHIP_RESULT:
  verdict: SHIPPED | BLOCKED | BUILD_FAILED
  commit: [short hash]
  branch: main
  preflight_build: PASS | FAIL
  preflight_diff: PASS | FAIL
  memory_health: clean | [N issues]
  summary: [one sentence]
```

When called interactively, produce the full ship report — structured block goes at the end as an appendix.

## Step 1: Preflight — Build

```bash
cd ~/Harness\ Projects/TerminalRSS && bash build.sh 2>&1
```

If the build fails, **STOP**. Fix the issue before proceeding.

## Step 2: Preflight — Stale Memory Check

```bash
bash "$CLAUDE_PROJECT_DIR/.claude/hooks/check-memory-staleness.sh" < /dev/null 2>&1
```
- Stale memories: **don't block the ship**, but present actionable recommendations.

## Step 3: Preflight — Diff Review (Quick)

```bash
git diff --stat
```

Scan the diff for:
- Hardcoded secrets or API keys
- Debug prints left in production paths
- Security violations

If any issues found, list them and ask user whether to fix or proceed.

## Step 4: Commit & Push to Main

Stage all changes, commit with a descriptive message, and push:

```bash
git add -A && git commit -m "message" && git push origin main
```

If push is rejected, pull first (no rebase), resolve conflicts, then push.

## Step 5: Ship Report

```
Ship Report
===========
Commit: [short hash] — [message]
Branch: main
Build: PASS
Diff review: PASS
Memory health: [clean or N issues]
Installed: /Applications/TerminalRSS.app
```

## Rules

- Always confirm with user before pushing to `main` — present the commit message and file list first.
- If the build fails, stop and fix — do not skip.
- If preflight finds secrets or security issues, stop and fix.
