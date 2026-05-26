# TerminalRSS

A terminal-styled RSS reader for macOS with a built-in market dashboard, topic clustering, and article flagging.

For people who want a dense, keyboard-driven feed reader that also keeps an eye on the markets while they read. Built in SwiftUI with a Bloomberg-terminal aesthetic — monospaced fonts, amber/green accents, tiled panels — but it's a native macOS window, not a TUI.

## Features

- **RSS + Atom parsing** — custom `XMLParser`-based reader, no third-party dependencies. Handles CDATA, content/description split, multiple date formats (RFC 822, ISO 8601, etc.).
- **Ranked view** — greedy Jaccard clustering across all subscribed feeds finds the same story breaking on multiple sources, scored by source count + recency + a "premium" boost for feeds you mark important. Ads/promos are penalized to the bottom.
- **Topic view** — keyword-based classifier sorts articles into ~24 buckets (AI & ML, Apple, Crypto, Politics, Science & Space, Cybersecurity, etc.).
- **Flagging** — three flag types (Read Later, Favorite, Flag) with dedicated sidebar views.
- **Market dashboard** — top strip shows S&P 500, NASDAQ, DOW, and TSX with live sparkline charts. Right panel shows a watchlist (default ~90 symbols across US stocks, TSX, and crypto) with per-symbol sparklines, top gainers/losers, and a portfolio pulse. Data from Yahoo Finance, auto-refreshes every 60 seconds.
- **Market hours awareness** — derives MARKET OPEN / PRE-MARKET / AFTER-HOURS / CLOSED from Yahoo's `marketState`, with a fallback that knows US market holidays (including a computed Good Friday).
- **Date filter bar** — 1H / 3H / 8H / Today / 24H / 3D / 7D / 30D / All / Custom. The article filter and the market chart range stay in sync.
- **Feed health tab** — per-feed item counts, unread counts, last-refresh time, and a color-coded OK/OLD/ERR status indicator.
- **In-app browser** — Enter opens the selected article in an embedded WebKit pane, not your system browser.
- **Premium feeds** — mark any feed as premium (★) to boost its clusters in the ranked view.
- **Offline cache** — articles persist across launches; refresh merges new items rather than replacing them. Capped at 200 articles per feed.

<!-- TODO: add screenshot or terminal recording -->

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9 toolchain
- Xcode command-line tools (for `swift build`)

## Install

```bash
git clone <repo-url>
cd TerminalRSS
bash build.sh
```

`build.sh` does a release build, assembles a `.app` bundle with the included icon, copies it to `/Applications/TerminalRSS.app`, and launches it.

To run without installing:

```bash
swift run -c release
```

## Usage

The window is split into four regions:

- **Left** — feed list with ALL FEEDS, RANKED, TOPICS, flag categories, and ~80 default feeds you can override.
- **Center top** — article list for the current view (feed / ranked clusters / topic groups / flagged).
- **Center bottom** — article reader with rendered HTML.
- **Right** — market watchlist (top) and a tabbed panel (bottom) with Feed Health, Portfolio, and Hotkeys tabs.

### Keyboard shortcuts

| Key | Action |
|-----|--------|
| `j` / `↓` | Next article |
| `k` / `↑` | Previous article |
| `Space` | Toggle read / unread |
| `Enter` | Open article in the in-app browser |
| `Cmd+N` | Focus the "add feed" input |
| `Cmd+R` | Refresh all feeds |
| `Cmd+Delete` | Unsubscribe from the selected feed |
| `Cmd+M` | Refresh market data |

To add a feed, paste a URL into the input at the bottom of the feed list and hit Enter. Bare hostnames (`example.com/feed`) get `https://` prepended automatically.

## Storage

- **Feeds, articles, read state, flags, sort modes** — JSON at:
  `~/Library/Application Support/TerminalRSS/feeds.json`
- **Watchlist symbols** — `UserDefaults` under key `TerminalRSS.watchlistSymbols.v2`

There's no OPML import/export yet. New default feeds added to the source are auto-subscribed on next launch; existing subscriptions are preserved.

## Architecture

- `App.swift` — `@main` entry point, command menus, notification routing
- `Models/FeedStore.swift` — observable feed/article/flag state, persistence, refresh, derived views
- `Models/MarketStore.swift` — Yahoo Finance fetching, US market hours, watchlist
- `Utilities/FeedParser.swift` — RSS + Atom XML parser
- `Utilities/ArticleRanker.swift` — Jaccard clustering and scoring
- `Utilities/TopicClassifier.swift` — keyword-based topic buckets
- `Utilities/MoltbookFetcher.swift` — JSON API fetcher for moltbook.com
- `Views/` — SwiftUI panels (feed list, article list, reader, market panels, sparklines, tabbed utility panel)

## License

PolyForm Noncommercial 1.0.0 — see [LICENSE](LICENSE). Free for personal use, hobby projects, and noncommercial organizations. Commercial use is not permitted.
