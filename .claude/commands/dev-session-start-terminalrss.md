---
description: "Start a development session with context loading, status check, and focus selection. Use /morning instead for most use cases."
---

# Session Start

Efficiently load context and prepare for development.

## Step 1: Validate Workspace Structure

```bash
echo "=== Workspace Health ===" && \
for f in "Package.swift" "CLAUDE.md" "build.sh"; do
  [ -f "$f" ] && echo "OK $f" || echo "MISSING: $f"
done && \
echo "" && \
ls project/tickets/TICKET-*.md 2>/dev/null | wc -l | xargs -I{} echo "{} open tickets"
```

## Step 2: Load Session State

Read `project/SESSION_STATE.md` if it exists.

## Step 3: Quick Status Check

```
Current Status
- Version: [from .claude/.harness-version]
- Branch: [git branch]
- Last commit: [git log -1 --oneline]
- Uncommitted changes: [git status --short]
```

## Step 4: Session Focus Selection

Ask the developer:
> "What would you like to focus on today?"

Options:
1. Continue priority items from last session
2. New feature development
3. Bug fixing
4. Refactoring/improvement
5. Something else (describe)

## Step 5: Pre-Flight Check (For Non-Trivial Tasks)

Present the **7 Pre-Flight Questions**:

1. **What am I actually trying to accomplish?**
2. **Why does this matter?**
3. **What does "done" look like?**
4. **What does "wrong" look like?**
5. **What do I already know that I haven't said?**
6. **What are the pieces?**
7. **What's the hard part?**

## Step 6: Ready to Work

> "Context loaded. Ready to begin [focus area]. Let me know when you'd like to start."
