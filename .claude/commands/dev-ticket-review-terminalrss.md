---
description: "Review all tickets, check status, reconcile, pick next task. Use when starting a work session or asking 'what should I work on next'."
---

# Ticket Review

Review all tickets in the backlog, assess status, recommend next work.

## Step 1: List All Tickets

Read all TICKET-*.md files in `project/tickets/`. For each, extract:
- Filename, Title, Status, Priority, Dependencies

## Step 2: Reconcile Ticket Status

For any ticket whose status should change:
- If code complete and AC met: set `**Status:** IN_REVIEW`
- If blocked on user/external action: set `**Status:** NEEDS_HUMAN`
- If should be closed: move to `project/tickets/closed/`

## Step 3: Create Status Table

| Ticket | Title | Status | Priority | Effort | Blocked By |
|--------|-------|--------|----------|--------|------------|

Sort by priority then status.

## Step 4: Identify Quick Wins

Flag tickets that are:
- Almost done
- Low effort + high priority
- Unblocked

## Step 5: Recommend Next Actions

Present 3 recommendations:
- **Best Next Task** — why it's top pick, estimated effort
- **Alternative Task** — good alternative
- **Skip for Now** — tickets that look urgent but should wait

## Step 6: Ask User to Pick

Present recommendations and ask which task to start.
