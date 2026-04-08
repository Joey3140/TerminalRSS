---
description: "Full context load — tickets, session state, git status"
---

# Morning Brief

One-shot context load for the start of any session. Pulls everything you need to know before writing a single line of code.

Run all data gathering in parallel for speed.

## Section 1: Session State

Read `project/SESSION_STATE.md` if it exists and extract:
- Current version and branch
- Last commit hash and message
- Active work in progress
- Pending decisions
- Blockers

## Section 2: Git Status

```bash
git status --short && echo "---" && git log --oneline -5 && echo "---" && git branch --show-current
```

Report:
- Current branch
- Uncommitted changes (if any)
- Last 5 commits

## Section 3: Ticket Status

Scan `project/tickets/TICKET-*.md` files:

1. Count tickets by status (IN_PROGRESS, SPEC_READY, NOT_SPECCED, NEEDS_HUMAN, BACKLOG)
2. List all IN_PROGRESS tickets with their one-line summary
3. List SPEC_READY tickets (ready to pick up)
4. Flag any NEEDS_HUMAN tickets (ball is in user's court)

## Section 4: Last Session Context

List recent session logs and surface the most recent one:

```bash
ls -1t project/sessions/session-*.md 2>/dev/null | head -5
```

Read the most recent session file and extract:
- Session ID and timestamps
- Summary of what was accomplished
- Key changes

## Section 5: Morning Brief

Combine everything into a concise briefing:

```
Morning Brief — [date]
========================

Version: [version] | Branch: [branch] | Last commit: [hash]

Active Work:
  [from SESSION_STATE — what was in progress]

Alerts:
  [Blocked tickets]

Ready to Pick Up:
  [SPEC_READY tickets, ordered by priority]

Pending Decisions:
  [from SESSION_STATE]

Suggested Focus:
  [Based on: unfinished work > alerts > spec-ready tickets > backlog]
```

## Section 6: Session Routing

Based on the briefing, ask:

> "Based on the brief, I'd suggest focusing on **[recommendation]**. Or would you prefer to work on something else?"

## Rules

- Run all data gathering in PARALLEL for maximum speed
- Keep the brief concise — details on demand, not by default
