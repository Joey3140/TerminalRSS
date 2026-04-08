---
description: Full development pipeline — ticket to ship with all quality gates chained together
---

# Dev Pipeline: Ticket to Ship

A unified development pipeline that chains ticket selection, implementation, and all quality review stages into one continuous flow.

## Execution Speed

**Use subagents aggressively.** Parallelize where possible. NITs and CONCERNs are auto-fixed inline — keep moving. Only stop on BLOCKs.

**Pipeline Stages:**
1. Ticket Selection
2. Spec Confirmation
3. Blast Radius Assessment
4. Implementation
5. Quality Gates — `/review` + build verification (parallel)
6. Commit + Ship

## Stage 1: Ticket Selection

Scan all tickets and present a summary table.

```bash
ls -la project/tickets/TICKET-*.md 2>/dev/null | grep -v README
```

For each ticket, extract title, status, priority. Present as a table. Ask the user to pick.

## Stage 2: Spec Confirmation

Read the selected ticket. Extract:
1. **Task Summary** — one sentence goal
2. **Success Criteria** — observable outcomes
3. **Key Files** — files likely modified
4. **Constraints** — patterns to follow

Present and ask: Looks good? Adjust? Wrong ticket?

## Stage 3: Blast Radius Assessment

- **Small (1-3 files):** Proceed directly.
- **Medium (4-8 files):** Break into sub-tasks.
- **Large (9+ files):** Present decomposition for approval.

## Stage 4: Implementation

Execute the work. Follow all `CLAUDE.md` rules. Run build after:
```bash
swift build 2>&1 | tail -20
```

Fix build errors before proceeding.

## Stage 5: Quality Gates (Parallel)

**Gate A:** Run `swift build -c release` for build verification
**Gate B:** Run `/review` for code quality

Auto-fix NITs and CONCERNs. Stop on BLOCKs.

## Stage 6: Commit + Ship

Run `/ship-terminalrss` to commit, push, rebuild, and install.

## Rules

- Always confirm with user before pushing to `main`
- If build fails, stop and fix
- If stuck after 3 attempts, pause and ask the user
