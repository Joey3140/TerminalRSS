import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: FeedStore
    @EnvironmentObject var market: MarketStore
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Top: Market dashboard strip (indices, pulse, movers)
            MarketDashboardStrip()
            DateFilterBar()

            // Main tiled panels — fixed proportional layout
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                HStack(spacing: 0) {
                    // Left: Feed list (15%)
                    FeedListView()
                        .frame(width: w * 0.15)

                    dividerV

                    // Center: Articles (35% height) + Reader (65% height)
                    VStack(spacing: 0) {
                        ArticleListView()
                            .frame(height: h * 0.35)

                        dividerH

                        ArticleDetailView()
                    }

                    dividerV

                    // Right: Watchlist (55% height) + Tabbed Utilities (45% height)
                    VStack(spacing: 0) {
                        MarketPanel()
                            .frame(height: h * 0.55)

                        dividerH

                        TabbedUtilityPanel()
                    }
                    .frame(width: w * 0.30)
                }
            }

            // Bottom: compact status bar
            BottomStatusBar()
        }
        .background(TerminalTheme.background)
        .focusable()
        .focused($isFocused)
        .onAppear {
            isFocused = true
        }
        .frame(minWidth: 900, minHeight: 500)
        .onKeyPress(.downArrow) { navigateArticle(1); return .handled }
        .onKeyPress(.upArrow) { navigateArticle(-1); return .handled }
        .onKeyPress("j") { navigateArticle(1); return .handled }
        .onKeyPress("k") { navigateArticle(-1); return .handled }
        .onKeyPress(" ") { toggleCurrentRead(); return .handled }
        .onKeyPress(.return) { openCurrentArticle(); return .handled }
    }

    // MARK: - Panel Dividers

    private var dividerV: some View {
        Rectangle().fill(TerminalTheme.panelBorder).frame(width: 1)
    }

    private var dividerH: some View {
        Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)
    }

    // MARK: - Keyboard Navigation

    private func navigateArticle(_ direction: Int) {
        if store.isTopicsMode {
            let clusters = store.topicFlatClusters
            guard !clusters.isEmpty else { return }

            if let currentID = store.selectedArticleID,
               let idx = clusters.firstIndex(where: { $0.primaryArticle.id == currentID }) {
                let newIdx = min(max(idx + direction, 0), clusters.count - 1)
                store.selectedArticleID = clusters[newIdx].primaryArticle.id
                store.markRead(clusters[newIdx].primaryArticle.id)
            } else {
                let cluster = direction > 0 ? clusters.first : clusters.last
                if let c = cluster {
                    store.selectedArticleID = c.primaryArticle.id
                    store.markRead(c.primaryArticle.id)
                }
            }
        } else if store.isRankedMode {
            let clusters = store.rankedArticles
            guard !clusters.isEmpty else { return }

            if let currentID = store.selectedArticleID,
               let idx = clusters.firstIndex(where: { $0.primaryArticle.id == currentID }) {
                let newIdx = min(max(idx + direction, 0), clusters.count - 1)
                store.selectedArticleID = clusters[newIdx].primaryArticle.id
                store.markRead(clusters[newIdx].primaryArticle.id)
            } else {
                let cluster = direction > 0 ? clusters.first : clusters.last
                if let c = cluster {
                    store.selectedArticleID = c.primaryArticle.id
                    store.markRead(c.primaryArticle.id)
                }
            }
        } else {
            let articles = store.selectedArticles
            guard !articles.isEmpty else { return }

            if let currentID = store.selectedArticleID,
               let idx = articles.firstIndex(where: { $0.id == currentID }) {
                let newIdx = min(max(idx + direction, 0), articles.count - 1)
                store.selectedArticleID = articles[newIdx].id
                store.markRead(articles[newIdx].id)
            } else {
                let article = direction > 0 ? articles.first : articles.last
                if let a = article {
                    store.selectedArticleID = a.id
                    store.markRead(a.id)
                }
            }
        }
    }

    private func toggleCurrentRead() {
        if let id = store.selectedArticleID {
            store.toggleRead(id)
        }
    }

    private func openCurrentArticle() {
        // Open in the in-app browser panel
        NotificationCenter.default.post(name: .openInBrowser, object: nil)
    }
}

// MARK: - Bottom Status Bar (compact — hotkeys moved to utility tab)

struct BottomStatusBar: View {
    @EnvironmentObject var store: FeedStore
    @EnvironmentObject var market: MarketStore

    var body: some View {
        HStack(spacing: 16) {
            Text("\(store.feeds.count) feeds")
                .foregroundStyle(TerminalTheme.primaryText)

            let totalArticles = store.articles.values.reduce(0) { $0 + $1.count }
            Text("\(totalArticles) articles")
                .foregroundStyle(TerminalTheme.primaryText)

            Text("\(store.totalUnreadCount) unread")
                .foregroundStyle(store.totalUnreadCount > 0 ? TerminalTheme.accentGreen : TerminalTheme.dimText)

            Rectangle().fill(TerminalTheme.accentOrange.opacity(0.3)).frame(width: 1, height: 12)

            Text("\(market.watchlist.count) positions")
                .foregroundStyle(TerminalTheme.primaryText)

            if market.failedSymbols.count > 0 {
                Text("\(market.failedSymbols.count) no data")
                    .foregroundStyle(TerminalTheme.accentAmber)
            }

            Spacer()

            if let error = store.errorMessage {
                Text(error)
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.accentRed)
                    .lineLimit(1)
            }

            if let updated = market.lastUpdated {
                Text("MKT \(updated.formatted(.dateTime.hour().minute()))")
                    .foregroundStyle(TerminalTheme.dimText)
            }
        }
        .font(TerminalTheme.smallFont)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(TerminalTheme.statusBarBackground)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let addFeed = Notification.Name("TerminalRSS.addFeed")
    static let deleteFeed = Notification.Name("TerminalRSS.deleteFeed")
    static let openInBrowser = Notification.Name("TerminalRSS.openInBrowser")
}
