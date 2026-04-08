# SPEC: Bloomberg Terminal Upgrade — TerminalRSS v2

## Ambitious Vision

A personal Bloomberg terminal that happens to have RSS at its core. Dense, tiled panels showing live stock market data, world clocks, feed health stats, and a master aggregated news view — all in monospace, all keyboard-navigable, all updating in real time. The kind of app where you open it full-screen and feel like you're sitting at a trading desk, except the data is YOUR curated information feed.

## Overview

Upgrade TerminalRSS from a 3-panel RSS reader into a full Bloomberg terminal-style dashboard. Add stock market data (indices, quotes, sparklines), world clocks, feed health/stats panel, master "ALL FEEDS" aggregated view, and feed/article sorting. Restructure the layout into a dense, multi-panel tiled grid matching the Bloomberg terminal density shown in the reference screenshot.

## Acceptance Criteria

- [ ] **Master "ALL FEEDS" view**: Selecting "ALL" in the feed sidebar shows articles from every subscribed feed, sorted by date (newest first), with feed source name shown per article
- [ ] **Feed sorting**: Feed list can be sorted by name (A-Z), unread count (desc), or date added — sort mode toggleable via click on header or keyboard shortcut
- [ ] **Article sorting**: Article list sortable by date, title, or read status — sort mode shown in panel header
- [ ] **Stock Market panel**: Shows S&P 500, NASDAQ, DOW indices with price, change, % change — color-coded green/red. Refreshes on a timer (every 60s)
- [ ] **Stock Watchlist**: User-configurable list of ticker symbols with live-ish quotes (price, change, % change, sparkline-style indicator)
- [ ] **World Clocks panel**: Shows current time in 4+ major timezones (New York, London, Hong Kong, Tokyo) — updating every second, matching Bloomberg's top-bar clock style
- [ ] **Feed Stats panel**: Shows per-feed health data — article count, last refresh time, avg articles/day, total unread — like a Bloomberg portfolio panel
- [ ] **Dense tiled layout**: Main view uses a grid/tiled panel layout — not just sidebar+detail, but multiple info-dense panels visible simultaneously
- [ ] **Panel headers**: Every panel has an orange header bar with title, matching Bloomberg section header style
- [ ] **Existing functionality preserved**: Feed list, article list, article detail reader, keyboard nav (j/k/↑↓/space/enter), Cmd+N/R/Delete shortcuts, persistence all still work
- [ ] **Build succeeds**: `bash build.sh` completes without errors and installs to /Applications
- [ ] **No external dependencies**: All market data fetched via URLSession from free APIs — no SPM packages added

## Constraint Architecture

### MUST DO
1. Use Yahoo Finance v8 JSON API for stock data — it's free, no API key needed, and returns JSON. Endpoint: `https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?range=1d&interval=5m` -- reliable and key-free
2. Keep all existing keyboard shortcuts working -- user muscle memory
3. All new panels must use TerminalTheme colors and fonts -- visual consistency
4. Stock data fetch must be async and non-blocking -- can't freeze the UI waiting on network
5. Persist watchlist symbols to the same feeds.json file -- single persistence file
6. World clocks must update every second via Timer.publish -- Bloomberg clocks are always ticking
7. ALL FEEDS aggregation must be a computed property, not a duplicated data store -- single source of truth
8. Each new panel must be a self-contained SwiftUI View struct in its own file -- maintainability
9. Build with `bash build.sh` and verify it installs -- must be deployable

### MUST NOT DO
1. Add any SPM dependencies -- zero external deps constraint
2. Use WebView/WKWebView for anything -- native SwiftUI only
3. Hardcode API keys -- Yahoo Finance v8 is key-free; if using Alpha Vantage, must be configurable
4. Break existing feed persistence format -- must load existing feeds.json without migration
5. Remove or modify existing keyboard shortcuts -- preserve all current bindings
6. Add cloud sync, accounts, or auth -- purely local app

### Anti-Goals
- No real-time WebSocket streaming — polling on timer is fine for a personal app
- No portfolio tracking with P&L — just quotes and indices
- No weather integration in v2 — clocks + stocks + feeds is enough density
- No options/futures/crypto panels — just equities and indices
- No charting library — sparklines are just small text/shape-based indicators

### PREFER
1. HSplitView/VSplitView for resizable panels -- user can adjust layout density
2. Dedicated ObservableObject per data domain (MarketStore, ClockStore) -- separation of concerns
3. Enum-based sort modes with Codable conformance -- persist user sort preferences
4. Text-based sparklines (▁▂▃▄▅▆▇█) over Shape-based charts -- terminal aesthetic, simpler
5. Timer-based refresh over manual-only -- Bloomberg feel requires live data

### ESCALATE
1. If Yahoo Finance API is blocked/changed — suggest alternative (Alpha Vantage free tier with key)
2. If layout gets too complex for HSplitView nesting — may need custom Grid layout

### Value Hierarchy
Goal wins with disclosure — build all features, disclose any compromises (e.g., "sparklines are text-based, not pixel charts").

## Task Decomposition

### Step 1: Sorting infrastructure (est: 15min)
- **Files**: `Sources/TerminalRSS/Models/FeedStore.swift`, `Sources/TerminalRSS/Views/FeedListView.swift`, `Sources/TerminalRSS/Views/ArticleListView.swift`
- **Action**: 
  - Add `FeedSortMode` enum (name, unreadCount, dateAdded) and `ArticleSortMode` enum (date, title, readStatus)
  - Add `@Published var feedSortMode` and `@Published var articleSortMode` to FeedStore
  - Add `sortedFeeds` computed property
  - Update `selectedArticles` to respect articleSortMode
  - Add `dateAdded` field to Feed model (default to Date() for existing feeds)
  - Add sort toggle UI in panel headers (clickable header text cycles through modes)
  - Persist sort preferences in SaveData
- **Verify**: Clicking feed/article panel headers cycles sort mode; articles reorder correctly

### Step 2: ALL FEEDS aggregated view (est: 10min)
- **Files**: `Sources/TerminalRSS/Models/FeedStore.swift`, `Sources/TerminalRSS/Views/FeedListView.swift`, `Sources/TerminalRSS/Views/ArticleListView.swift`
- **Action**:
  - Add sentinel `selectedFeedID == nil` to mean "ALL FEEDS" 
  - Add `allArticles` computed property that merges all feed articles, sorted by date
  - Show "ALL FEEDS" as first item in feed list with total unread count
  - In article list, show feed source name per article when in ALL FEEDS mode
  - Default to ALL FEEDS view on launch
- **Verify**: "ALL FEEDS" row appears at top of feed list; selecting it shows merged articles from all feeds with source labels

### Step 3: MarketStore + Stock data service (est: 20min)
- **Files**: NEW `Sources/TerminalRSS/Models/MarketStore.swift`, NEW `Sources/TerminalRSS/Models/MarketData.swift`
- **Action**:
  - Define `StockQuote` struct: symbol, price, change, changePercent, sparklineData ([Double])
  - Define `MarketIndex` struct: name, symbol, price, change, changePercent
  - Create `MarketStore` (ObservableObject, @MainActor):
    - `@Published var indices: [MarketIndex]` — S&P 500 (^GSPC), NASDAQ (^IXIC), DOW (^DJI)
    - `@Published var watchlist: [StockQuote]` — user-configurable symbols
    - `@Published var watchlistSymbols: [String]` — persisted list, default: ["AAPL", "GOOGL", "MSFT", "AMZN", "TSLA", "NVDA", "META"]
    - `refreshMarketData()` — fetch from Yahoo Finance v8 API
    - Timer-based auto-refresh every 60 seconds
    - Persist watchlistSymbols in UserDefaults or feeds.json
  - Yahoo Finance fetch: `https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?range=1d&interval=5m`
    - Parse: `chart.result[0].meta.regularMarketPrice`, `chart.result[0].meta.previousClose`, `chart.result[0].indicators.quote[0].close` for sparkline
- **Verify**: MarketStore fetches and populates data; prices are non-zero; sparkline arrays have data points

### Step 4: Stock Market panel view (est: 20min)
- **Files**: NEW `Sources/TerminalRSS/Views/MarketPanel.swift`
- **Action**:
  - **Indices section**: Table with columns — Name, Price, Chg, %Chg. Green if positive, red if negative. Bloomberg-style colored backgrounds on change values.
  - **Watchlist section**: Same table format + text-based sparkline column using block chars (▁▂▃▄▅▆▇█)
  - Panel header "MARKETS" in orange
  - Add/remove symbols via a small text field at bottom (like feed URL input)
  - Show "MARKET CLOSED" or last update time in dim text
- **Verify**: Panel shows real stock prices with correct green/red coloring; sparklines render as block characters

### Step 5: World Clocks panel (est: 10min)
- **Files**: NEW `Sources/TerminalRSS/Views/WorldClocksPanel.swift`
- **Action**:
  - Show current time in: New York (ET), London (GMT/BST), Hong Kong (HKT), Tokyo (JST), plus local time
  - Large time display (HH:mm:ss) with city name and timezone abbreviation
  - Update every second via Timer
  - Match Bloomberg's horizontal clock bar layout from the reference image
  - Orange city names, bright white time, dim timezone labels
- **Verify**: Clocks show correct times for each timezone; seconds tick live

### Step 6: Feed Stats panel (est: 15min)
- **Files**: NEW `Sources/TerminalRSS/Views/FeedStatsPanel.swift`
- **Action**:
  - Table showing each feed: Name, Articles, Unread, Last Refreshed, Status
  - Status: green "OK" if refreshed within last hour, amber "STALE" if >1hr, red "ERROR" if last refresh failed
  - Total row at bottom
  - Orange "FEED HEALTH" header
  - Compact table with alternating row shading (subtle)
- **Verify**: Stats match actual feed data; status colors are correct

### Step 7: Dense tiled layout overhaul (est: 25min)
- **Files**: `Sources/TerminalRSS/Views/ContentView.swift`, `Sources/TerminalRSS/App.swift`
- **Action**:
  - Restructure ContentView into a Bloomberg-style tiled grid:
    ```
    ┌─────────────────────────────────────────────────────────┐
    │ TERMINALRSS  │  NEW YORK  LONDON  HONG KONG  TOKYO     │ Top bar
    ├────────┬─────┴───────────────┬──────────────────────────┤
    │ FEEDS  │ ARTICLES            │ MARKETS                  │
    │        │                     │  Indices                 │
    │        │                     │  Watchlist               │
    │        ├─────────────────────┼──────────────────────────┤
    │        │ READER              │ FEED HEALTH              │
    │        │                     │                          │
    │        │                     │                          │
    ├────────┴─────────────────────┴──────────────────────────┤
    │ Cmd+N Add │ Cmd+R Refresh │ Space Read │ j/k Nav       │ Bottom bar
    └─────────────────────────────────────────────────────────┘
    ```
  - Move world clocks INTO the top status bar (horizontal, like Bloomberg)
  - Right column split between Markets (top) and Feed Health (bottom)
  - All panels resizable via HSplitView/VSplitView nesting
  - Keep existing keyboard nav working on the article list
  - Window default size bumped to 1600x1000
- **Verify**: All panels visible simultaneously; resizing works; keyboard nav still functions

### Step 8: Integration + wiring (est: 15min)
- **Files**: `Sources/TerminalRSS/App.swift`, `Sources/TerminalRSS/Views/ContentView.swift`
- **Action**:
  - Create MarketStore as @StateObject in App, pass via .environmentObject
  - Wire up market refresh timer
  - Add Cmd+M shortcut to manually refresh market data
  - Ensure all stores persist correctly
  - Wire up add/remove watchlist symbol functionality
- **Verify**: Full app launches with all panels populated; market data refreshes; persistence works across restart

### Step 9: Finalize (est: 10min)
- Run `bash build.sh` — must succeed
- Verify installed app launches and shows all panels
- Test keyboard navigation still works
- Test feed add/remove still works
- Test market data populates

## Verification Commands

```bash
# Build check (primary gate)
cd ~/Harness\ Projects/TerminalRSS && swift build 2>&1

# Release build + install
cd ~/Harness\ Projects/TerminalRSS && bash build.sh 2>&1

# Verify no external deps added
grep -c "dependencies:" ~/Harness\ Projects/TerminalRSS/Package.swift
# Should be 0 or show empty array

# Verify all new files exist
ls -la Sources/TerminalRSS/Models/MarketStore.swift \
       Sources/TerminalRSS/Models/MarketData.swift \
       Sources/TerminalRSS/Views/MarketPanel.swift \
       Sources/TerminalRSS/Views/WorldClocksPanel.swift \
       Sources/TerminalRSS/Views/FeedStatsPanel.swift

# Verify existing files not deleted
ls -la Sources/TerminalRSS/Views/FeedListView.swift \
       Sources/TerminalRSS/Views/ArticleListView.swift \
       Sources/TerminalRSS/Views/ArticleDetailView.swift \
       Sources/TerminalRSS/Models/FeedStore.swift

# Check no hardcoded API keys
grep -r "apikey\|api_key\|API_KEY\|Bearer " Sources/ || echo "No API keys found (good)"
```

## Context
- **Codebase**: 12 Swift files, SPM project, macOS 14+, zero dependencies
- **Key existing files**: FeedStore.swift (state), ContentView.swift (layout), TerminalTheme.swift (colors/fonts)
- **Data flow**: FeedStore is the single ObservableObject, passed via .environmentObject
- **Persistence**: ~/Library/Application Support/TerminalRSS/feeds.json
- **Build**: `bash build.sh` → swift build -c release → copy to /Applications
- **Recent changes**: Initial scaffold + full RSS reader built in current session
- **Reference**: Bloomberg terminal screenshot provided — dense multi-panel, orange headers, black bg, blue status bars, colored data tables

## New Files to Create
| File | Responsibility |
|------|---------------|
| `Models/MarketData.swift` | StockQuote, MarketIndex structs |
| `Models/MarketStore.swift` | Market data fetch, watchlist, timer refresh |
| `Views/MarketPanel.swift` | Stock indices + watchlist panel |
| `Views/WorldClocksPanel.swift` | Multi-timezone clock display |
| `Views/FeedStatsPanel.swift` | Feed health/stats table |

## Existing Files to Modify
| File | Changes |
|------|---------|
| `Models/Feed.swift` | Add `dateAdded` field |
| `Models/FeedStore.swift` | Sort modes, ALL FEEDS aggregation, sort persistence |
| `Views/FeedListView.swift` | ALL FEEDS row, sort toggle in header |
| `Views/ArticleListView.swift` | Sort toggle, feed source label in ALL mode |
| `Views/ContentView.swift` | Complete layout overhaul — tiled grid with all panels |
| `App.swift` | Add MarketStore, new shortcuts |
| `TerminalTheme.swift` | Add any missing color/font constants (positive green, negative red backgrounds) |

## Definition of Done
All acceptance criteria checked. `bash build.sh` succeeds. App launches showing all Bloomberg-style panels (clocks, markets, feeds, reader, stats) simultaneously. Existing RSS functionality (add/remove feeds, read articles, keyboard nav, persistence) still works. No external dependencies. Installed to /Applications and opened.
