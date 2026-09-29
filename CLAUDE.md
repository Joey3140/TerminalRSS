# TerminalRSS — Rules for Claude

<!-- HARNESS:BEGIN — managed by claude-harness, do not edit this block -->

Inherits all global rules from `~/.claude/CLAUDE.md` and `~/Harness Projects/CLAUDE.md` — MUST DO / MUST NOT / PREFER / agent rules live there. Only harness-project deltas below; duplicating global rules makes maintenance lossy.

## Project MUST DO

1. **Verify before committing** — this project has no test suite yet; exercise the change the way this file describes (build script, live check, or manual run).

## Project MUST NOT

1. **NEVER use worktree isolation (`isolation: "worktree"`)** — permanently banned. Worktree agents fork from stale bases and silently destroy feature work on merge.

## Project PREFER

1. **Assess blast radius before broad changes** — if a task touches 10+ files, consider breaking it up.
2. **Structural/architectural changes** — suggest new rules and wait for review before restructuring.

<!-- HARNESS:END -->

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

### Recent Debugging Lessons

- **Rebuild the installed app, not just the SwiftPM binary** — if behavior in the running UI does not match the current source, compare timestamps for `/Applications/TerminalRSS.app` and the current `.build` binary. This project is often run from the packaged app bundle, and stale bundles can make a real fix look broken.
- **Use `bash build.sh` for end-to-end verification** — that script builds release, refreshes `build/TerminalRSS.app`, installs `/Applications/TerminalRSS.app`, and launches it. A successful `swift build` alone does not prove the app the user launched is current.
- **For US market status, prefer Yahoo `currentTradingPeriod` over hand-rolled ET conversion** — Yahoo's chart metadata exposes pre/regular/post session start and end times as epoch timestamps. Derive open/closed state from those periods first, and only fall back to a holiday-aware NYSE schedule if Yahoo fails.
- **Expect Yahoo anti-bot/rate-limit behavior** — raw requests can return `Too Many Requests` or `Unauthorized`. Send a browser-like `User-Agent` on finance requests and make market-status logic resilient when Yahoo omits `marketState`.
