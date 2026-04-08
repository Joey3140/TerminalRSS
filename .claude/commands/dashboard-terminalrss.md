---
description: "Generate and open the ticket dashboard — Kanban board, pipeline, filters, recent wins"
---

# Dashboard

Generate a self-contained HTML dashboard from the project's ticket files and open it in the browser.

## Steps

1. Run the dashboard generator:

```bash
node tools/ticket-dashboard.js
```

2. For live reload:

```bash
node tools/ticket-dashboard.js --serve
```

Starts an HTTP server on port 4001 that regenerates on every request.

## What the Dashboard Shows

- **Status Breakdown** — stacked bar showing ticket distribution
- **P0 Blockers** — highlighted callout
- **Pipeline** — horizontal bars per status
- **Kanban Board** — columns per status, cards sorted by priority
- **Recent Wins** — last 12 completed tickets

## Rules

- Do NOT install any npm packages — the script uses only Node.js built-ins
- The generated HTML is fully self-contained
