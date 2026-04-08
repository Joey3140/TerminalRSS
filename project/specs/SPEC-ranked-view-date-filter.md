# SPEC: Intelligent Ranked View + Master Date Filter

## Ambitious Vision

A personal Techmeme built from your own feed subscriptions. Every story clustered across sources, scored by importance (multi-source coverage × recency × premium boost), with the noise stripped out. A master date filter that acts like a time machine — slide to any window and every panel in the app (articles, counts, stats, market sparklines) snaps to that range. The war room answers "what matters right now" at a glance.

## Overview

Two cross-cutting features: (1) A RANKED view that deduplicates, clusters, and scores articles across all feeds using fuzzy title matching, multi-source signal, recency weighting, and premium feed boost — surfacing the most important stories first. (2) A master date filter bar at the top of the app that filters all data (articles, unread counts, feed stats, market sparklines) to a selected time range with quick presets (TODAY, 24H, 3D, 7D, 30D, ALL).

## Acceptance Criteria

### Ranked View
- [ ] "RANKED" appears in feed sidebar below "ALL FEEDS", selecting it shows deduplicated/scored articles
- [ ] Articles with similar titles (≥0.5 Jaccard similarity on normalized word sets) are clustered together
- [ ] Clustered stories show primary article + source count badge (e.g., "3 sources")
- [ ] Clicking a cluster expands to show all source articles inline (collapsible)
- [ ] Scoring formula: `score = sourceCount × 2.0 + recencyScore + premiumBoost`
  - `recencyScore`: 1.0 for <1hr, 0.8 for <6hr, 0.5 for <24hr, 0.2 for <72hr, 0.0 for older
  - `premiumBoost`: +3.0 if ANY source in the cluster is a premium feed
- [ ] Articles are sorted by score descending (highest importance first)
- [ ] Right-click any feed → "Toggle Premium" — marks/unmarks it as premium
- [ ] Premium feeds show a ★ indicator in the feed list
- [ ] Feed premium status is persisted in feeds.json
- [ ] Existing ALL FEEDS and per-feed views are completely unchanged
- [ ] RANKED view respects the master date filter

### Master Date Filter
- [ ] A filter bar appears at the top of the app (above the market dashboard strip)
- [ ] Quick preset buttons: TODAY, 24H, 3D, 7D, 30D, ALL — styled as Bloomberg-style clickable tabs
- [ ] Active preset is highlighted (orange text on blue background), others are dim
- [ ] Selecting a preset filters articles by pubDate across ALL views (ALL FEEDS, RANKED, per-feed)
- [ ] Unread counts in the feed sidebar update to reflect filtered articles only
- [ ] Article count in the article list header reflects filtered count
- [ ] Feed stats in HEALTH tab reflect filtered article counts
- [ ] Market sparkline data adjusts Yahoo Finance `range` param to match filter (1d, 5d, 1mo, 3mo)
- [ ] The filter is global state on FeedStore (or a shared FilterStore)
- [ ] Selected filter is persisted across sessions
- [ ] "ALL" preset = no filtering (shows everything, default)
- [ ] Custom date range: clicking a preset again (or a "CUSTOM" button) shows start/end date pickers

### Build Gate
- [ ] `bash build.sh` succeeds with zero errors
- [ ] No external dependencies added
- [ ] Existing keyboard shortcuts still work
- [ ] Existing persistence format is backwards-compatible (new fields are optional in Codable)

## Constraint Architecture

### MUST DO
1. Fuzzy matching must be pure Swift — no external NLP/ML libraries. Jaccard on word sets is sufficient. -- zero deps constraint
2. Normalize titles before comparison: lowercase, strip punctuation, remove common stop words ("the", "a", "an", "in", "of", etc.), remove source-specific prefixes/suffixes -- improves match quality
3. Clustering must be O(n²) at worst (comparing all article pairs), which is fine for ~500 articles max -- personal app scale
4. Premium flag on Feed must use `decodeIfPresent` with `false` default for backwards compatibility -- existing feeds.json must load without migration
5. Date filter must be applied at the computed property level (filter `selectedArticles`, `allArticles`, `rankedArticles`) — NOT by mutating stored data -- single source of truth
6. Market sparkline range param mapping: TODAY/24H → "1d", 3D → "5d", 7D → "5d", 30D → "1mo", ALL → "3mo" -- Yahoo Finance API range options
7. Filter bar must use TerminalTheme colors and monospace fonts -- visual consistency
8. RANKED view must recalculate when articles change (feed refresh) or filter changes -- reactive
9. All new state must be persisted in existing SaveData struct with optional fields -- backwards compat

### MUST NOT DO
1. Do NOT use any ML frameworks (CoreML, NLP, CreateML) -- too heavy for string matching
2. Do NOT modify the raw `articles` dictionary — filtering is always a computed/derived view -- data integrity
3. Do NOT change existing sort modes or view behaviors for ALL FEEDS / per-feed views -- user expectation
4. Do NOT add external dependencies -- zero deps constraint
5. Do NOT make the ranking algorithm configurable via UI (hardcode weights, tune later if needed) -- simplicity first

### Anti-Goals
- No full-text content comparison (title matching only — content is too noisy with HTML)
- No machine learning or NLP beyond string tokenization
- No "trending" or "breaking" badges — just the score-based ordering
- No per-article date picker — only the master filter
- No time-of-day filtering — date granularity only
- No export or share functionality

### PREFER
1. Jaccard similarity over Levenshtein — it's word-set based, handles reworded titles better, and is simpler to implement
2. Compute ranked articles lazily (only when RANKED view is selected) — avoid work when not needed
3. Struct-based ArticleCluster type over inline tuples — cleaner code
4. DateFilter enum with associated values for presets — clean, Codable, exhaustive
5. Filter bar integrated into a thin strip above the market dashboard — minimal vertical space

### ESCALATE
1. If clustering produces too many false positives (unrelated articles grouped) — may need to raise similarity threshold
2. If date filter significantly complicates market data fetching — may simplify to only filter article data, not market

### Value Hierarchy
Goal wins with disclosure — build all features, disclose any compromises.

## Task Decomposition

### Step 1: DateFilter model + global state (est: 15min)
- **Files:** NEW `Models/DateFilter.swift`, MODIFY `Models/FeedStore.swift`
- **Action:**
  - Define `DateFilter` enum: `.today`, `.last24h`, `.last3d`, `.last7d`, `.last30d`, `.all`, `.custom(start: Date, end: Date)`
  - Add `Codable` conformance (use rawValue String + optional dates for custom)
  - Add `@Published var dateFilter: DateFilter = .all` to FeedStore
  - Add `dateRange` computed property that returns `(start: Date?, end: Date?)` from the filter
  - Add filter to SaveData (optional, defaults to `.all`)
  - Add `func filterByDate(_ items: [FeedItem]) -> [FeedItem]` helper
  - Update `selectedArticles`, `allArticles` to apply date filter
  - Update `unreadCount(for:)` to respect date filter
  - Add `totalFilteredArticleCount` computed property
- **Verify:** Changing dateFilter in code causes `selectedArticles` to return only articles within range

### Step 2: Feed premium tagging (est: 10min)
- **Files:** MODIFY `Models/Feed.swift`, MODIFY `Models/FeedStore.swift`, MODIFY `Views/FeedListView.swift`
- **Action:**
  - Add `var isPremium: Bool` to Feed with `decodeIfPresent` defaulting to `false`
  - Add `func togglePremium(_ feedID: UUID)` to FeedStore
  - Add ★ indicator next to premium feed names in FeedListView
  - Add right-click context menu on feed rows: "Toggle Premium ★"
- **Verify:** Right-click feed → Toggle Premium → star appears. Restart app → star persists.

### Step 3: Article ranking engine (est: 25min)
- **Files:** NEW `Utilities/ArticleRanker.swift`
- **Action:**
  - Define `ArticleCluster` struct:
    ```swift
    struct ArticleCluster: Identifiable {
        let id: String           // primary article ID
        let primaryArticle: FeedItem
        let sources: [FeedItem]  // all articles in cluster (including primary)
        let sourceCount: Int
        let score: Double
        let hasPremiumSource: Bool
    }
    ```
  - Define `ArticleRanker` struct with static methods:
    - `static func rank(articles: [FeedItem], feeds: [Feed], readIDs: Set<String>) -> [ArticleCluster]`
    - `static func normalizeTitle(_ title: String) -> Set<String>` — lowercase, strip punctuation, remove stop words, split into word set
    - `static func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double`
    - `static func recencyScore(_ date: Date?) -> Double`
  - Clustering algorithm:
    1. Normalize all titles into word sets
    2. Build clusters greedily: for each article, check if it matches any existing cluster (Jaccard ≥ 0.5 against cluster primary). If yes, add to cluster. If no, start new cluster.
    3. Within each cluster, pick the article with the longest content as primary (best version)
    4. Score each cluster: `sourceCount * 2.0 + bestRecencyScore + (hasPremium ? 3.0 : 0.0)`
    5. Sort clusters by score descending
  - Stop words list: ["the", "a", "an", "in", "on", "at", "to", "for", "of", "and", "or", "is", "it", "by", "with", "from", "as", "this", "that", "are", "was", "were", "be", "has", "had", "have", "will", "but", "not", "you", "your", "we", "they", "its", "new", "how", "why", "what"]
- **Verify:** Feed ranker with test data produces correct clusters and scores

### Step 4: Wire RANKED view into FeedStore (est: 10min)
- **Files:** MODIFY `Models/FeedStore.swift`
- **Action:**
  - Add `rankedMode` sentinel: use a special UUID or a separate `@Published var viewMode: ViewMode` enum (`.allFeeds`, `.ranked`, `.feed(UUID)`)
  - Add `var rankedArticles: [ArticleCluster]` computed property that calls ArticleRanker with date-filtered articles
  - Add `@Published var expandedClusterIDs: Set<String>` for tracking which clusters are expanded
  - Add `func toggleClusterExpansion(_ clusterID: String)`
- **Verify:** `store.rankedArticles` returns scored, clustered articles

### Step 5: Date Filter bar view (est: 15min)
- **Files:** NEW `Views/DateFilterBar.swift`
- **Action:**
  - Horizontal bar with preset buttons: TODAY | 24H | 3D | 7D | 30D | ALL
  - Active button: orange text on selectionBackground, others: dim text
  - Compact height (~24px) to minimize vertical space
  - On tap: set `store.dateFilter` to corresponding preset
  - Optional: long-press or double-tap on active preset shows date picker popover for custom range
  - Bloomberg aesthetic: monospace, dark background, subtle borders
- **Verify:** Clicking presets changes filter; article list updates immediately

### Step 6: RANKED view in sidebar + article list (est: 20min)
- **Files:** MODIFY `Views/FeedListView.swift`, MODIFY `Views/ArticleListView.swift`
- **Action:**
  - Add "RANKED" row in FeedListView below "ALL FEEDS", with ★ icon, dimmed count of clusters
  - Selecting RANKED sets viewMode to `.ranked`
  - In ArticleListView: when in ranked mode, show clusters instead of flat articles
    - Each cluster row shows: primary article title (bold), source count badge ("3 sources" in amber), score indicator
    - If cluster is expanded (`expandedClusterIDs.contains`), show indented source articles below with their feed name
    - Clicking a cluster row expands/collapses it AND selects the primary article for the reader
  - Article header shows "RANKED — X stories" instead of feed name
- **Verify:** Selecting RANKED shows clustered, scored articles. Expanding a cluster shows sources.

### Step 7: Wire date filter into market data (est: 10min)
- **Files:** MODIFY `Models/MarketStore.swift`, MODIFY `Views/MarketDashboardStrip.swift`
- **Action:**
  - Add a method to map DateFilter → Yahoo Finance range string
  - When date filter changes, re-fetch market data with appropriate range
  - Pass date filter via environment or notification
  - Update sparkline data based on filtered range
- **Verify:** Changing date filter to "7D" fetches 5-day sparklines instead of 1-day

### Step 8: Wire date filter into all panels (est: 15min)
- **Files:** MODIFY `Views/ContentView.swift`, MODIFY `Views/TabbedUtilityPanel.swift`, MODIFY `Views/MarketDashboardStrip.swift`
- **Action:**
  - Add DateFilterBar to ContentView above MarketDashboardStrip
  - Feed stats in HEALTH tab: article counts reflect filtered range
  - Portfolio pulse in dashboard strip: should already reflect filtered market data
  - Unread counts in sidebar: already handled via FeedStore computed properties (Step 1)
- **Verify:** Changing date filter updates all visible counts, stats, and sparklines

### Step 9: Finalize (est: 10min)
- Run `bash build.sh` — must succeed
- Verify RANKED view works with real feed data
- Verify date filter changes propagate to all panels
- Verify premium feed toggle persists
- Verify existing views (ALL FEEDS, per-feed) unchanged
- Verify keyboard navigation works in RANKED view

## Verification Commands

```bash
# Build check (primary gate)
cd ~/Harness\ Projects/TerminalRSS && swift build 2>&1

# Release build + install
cd ~/Harness\ Projects/TerminalRSS && bash build.sh 2>&1

# Verify new files exist
ls -la Sources/TerminalRSS/Models/DateFilter.swift \
       Sources/TerminalRSS/Utilities/ArticleRanker.swift \
       Sources/TerminalRSS/Views/DateFilterBar.swift

# Verify no external deps
grep "dependencies:" Package.swift

# Verify no hardcoded API keys
grep -r "apikey\|api_key\|API_KEY" Sources/ || echo "Clean"

# Verify backwards-compatible Codable (decodeIfPresent for new fields)
grep -n "decodeIfPresent" Sources/TerminalRSS/Models/Feed.swift
grep -n "decodeIfPresent" Sources/TerminalRSS/Models/FeedStore.swift
```

## New Files to Create
| File | Responsibility |
|------|---------------|
| `Models/DateFilter.swift` | DateFilter enum, Codable, range computation |
| `Utilities/ArticleRanker.swift` | Fuzzy matching, clustering, scoring engine |
| `Views/DateFilterBar.swift` | Master date filter UI bar |

## Existing Files to Modify
| File | Changes |
|------|---------|
| `Models/Feed.swift` | Add `isPremium: Bool` field |
| `Models/FeedStore.swift` | DateFilter state, rankedArticles, viewMode, premium toggle, filtered computed properties |
| `Models/MarketStore.swift` | Accept date filter for sparkline range param |
| `Views/FeedListView.swift` | RANKED sidebar row, premium ★ indicator, context menu |
| `Views/ArticleListView.swift` | Ranked cluster display with expand/collapse |
| `Views/ContentView.swift` | Add DateFilterBar above dashboard strip |
| `Views/TabbedUtilityPanel.swift` | Health tab respects date filter |
| `Views/MarketDashboardStrip.swift` | Sparklines respect date filter |

## Context
- **Codebase:** 18 Swift files, ~2700 LOC, SPM, macOS 14+, zero deps
- **Data flow:** FeedStore is central ObservableObject, MarketStore is separate. Both via .environmentObject.
- **Persistence:** ~/Library/Application Support/TerminalRSS/feeds.json (FeedStore), UserDefaults (MarketStore watchlist)
- **Current article count:** ~500 articles across 18 feeds (well within O(n²) clustering budget)
- **Build:** `bash build.sh` → swift build -c release → /Applications
- **Related tickets:** TICKET-005 (Bloomberg upgrade, completed)

## Definition of Done
All acceptance criteria checked. `bash build.sh` succeeds. RANKED view shows deduplicated, scored, clustered articles from all feeds. Date filter presets visibly filter all panels. Premium feed toggle persists. Existing ALL FEEDS and per-feed views untouched. Keyboard navigation works in all views. Installed to /Applications.
