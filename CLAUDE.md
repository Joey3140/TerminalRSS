# TerminalRSS — Rules for Claude

## Global MUST DO (Apply to every task, every area)

1. **Understand before modifying** — read existing code before suggesting changes. Trace data flow. `grep` before editing.
2. **Audit all callers on any change** — when fixing a shared function, grep ALL callers for the same class of bug. When making a field mandatory, grep ALL call sites.
3. **Run build before committing** — `bash build.sh`, not just the changed file.
4. **Narrow try/catch** — never wrap large blocks in try/catch. Wrap only the risky operation.
5. **Verify security claims independently** — after any security fix, grep the ENTIRE codebase for the vulnerable pattern.
6. **Fix root causes, don't skip around them** — if a build step fails, fix why.
7. **Self-review before committing** — re-read every changed file. Check imports match, field names match, function signatures match.

## Global MUST NOT (Apply everywhere)

1. **NEVER push to `main`** without explicit user approval in the SAME message.
2. **NEVER hardcode secrets** or API keys.
3. **NEVER use colons in filenames** — Windows incompatible.
4. **NEVER use worktree isolation (`isolation: "worktree"`)** — permanently banned.
5. **NEVER delete or weaken passing tests** without explicit user direction.
6. **NEVER add scope creep** — don't add features, refactor surrounding code, add docstrings to unchanged code, or "improve" things beyond what was asked.

## Global PREFER (Judgment guidance)

1. **Multiple-choice prompts** when asking the user — present options with pros/cons.
2. **Design before implementation** — describe the approach before writing code.
3. **Minimal, focused edits** over large refactors.
4. **Extending existing patterns** over inventing new abstractions.
5. **Judgment unbundling** — "Here's what I found + my recommendation + the one thing I need you to decide."
6. **Screenshot-first debugging** — take a screenshot before reading code for visual bugs.
7. **Assess blast radius before broad changes** — if a task touches 10+ files, consider breaking it up.

## ESCALATE (Stop and ask the user)

1. **Production deployment** — always ask before pushing to `main`
2. **Structural/architectural changes** — suggest new rules, wait for review
3. **Test deletion or weakening** — explain why and get explicit approval
4. **Scope creep** — stop and re-scope

## Agent & Parallel Work

1. **Multi-agent builds need interface reconciliation** — parallel agents invent different names. After any parallel build, grep imports vs exports, check response field names match.
2. **Exclusive file manifests for parallelism** — if multiple agents must work simultaneously, give each ownership of specific files. Never let two agents touch the same file.
3. **Merge conflicts: favor the target branch** — the branch with more commits on the conflicted file wins. Reapply the small change on top.

## Hooks & Enforcement

- **Deterministic hooks over rules** — if a constraint can be expressed as a grep/lint check, it should be a hook (exit 1), not a rule.
- **If a hook blocks you, read the error and fix** — don't retry the same action.

## Patterns That Work

- **Test-first:** Check existing tests before implementing. Write tests before code.
- **After 3+ failed attempts**, identify the wrong *assumption*, don't just retry.

---

## Project-Specific Rules

### What This App Is

TerminalRSS is a personal RSS reader for macOS, styled like a terminal. It renders feed content with markdown formatting in a monospace, terminal-aesthetic UI. Think: reading RSS feeds as if they were output in a beautifully styled terminal.

### Architecture

- **Swift 5.9 / SwiftUI** targeting macOS 14+
- **No external dependencies** — uses only Apple frameworks + Foundation's XMLParser for RSS/Atom
- **Local-first** — feed list and read state stored on-disk (JSON or SQLite), no cloud sync
- **Single-window app** with sidebar (feed list) + detail (article content)

### Visual Design Principles

- **Terminal aesthetic** — monospace font (SF Mono / Menlo), dark background, green/amber/white text
- **Markdown rendering** — articles rendered with proper headings, bold, italic, code blocks, links
- **No browser chrome** — content is rendered natively in SwiftUI, not in a WebView
- **Minimal UI** — keyboard-driven navigation, sparse chrome, information-dense

### Key Files

| File | Responsibility |
|------|---------------|
| `App.swift` | Entry point, window setup |
| `Models/Feed.swift` | RSS/Atom feed data model |
| `Models/FeedItem.swift` | Individual article model |
| `Models/FeedStore.swift` | Persistence + feed management |
| `Utilities/FeedParser.swift` | XMLParser-based RSS/Atom parser |
| `Utilities/MarkdownRenderer.swift` | HTML-to-markdown + SwiftUI rendering |
| `Views/FeedListView.swift` | Sidebar feed list |
| `Views/ArticleListView.swift` | Article list for selected feed |
| `Views/ArticleDetailView.swift` | Full article content view |
| `Views/ContentView.swift` | Main layout (sidebar + detail) |
