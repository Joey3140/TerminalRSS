import SwiftUI

enum UtilityTab: String, CaseIterable {
    case health = "HEALTH"
    case portfolio = "PORTFOLIO"
    case hotkeys = "HOTKEYS"
}

struct TabbedUtilityPanel: View {
    @EnvironmentObject var store: FeedStore
    @EnvironmentObject var market: MarketStore
    @State private var selectedTab: UtilityTab = .health

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar (acts as panel header)
            HStack(spacing: 0) {
                ForEach(UtilityTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
                Spacer()
            }
            .background(TerminalTheme.panelBackground)

            Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)

            // Tab content
            switch selectedTab {
            case .health:
                healthTab
            case .portfolio:
                portfolioTab
            case .hotkeys:
                hotkeysTab
            }
        }
        .background(TerminalTheme.background)
    }

    // MARK: - Tab Button

    private func tabButton(_ tab: UtilityTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Text(tab.rawValue)
                .font(TerminalTheme.headerFont)
                .foregroundStyle(selectedTab == tab ? TerminalTheme.accentOrange : TerminalTheme.dimText)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(selectedTab == tab ? TerminalTheme.selectionBackground : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Health Tab

    private var healthTab: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text("FEED")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("ITEMS")
                    .frame(width: 50, alignment: .trailing)
                Text("NEW")
                    .frame(width: 50, alignment: .trailing)
                Text("REFRESH")
                    .frame(width: 90, alignment: .trailing)
                Text("ST")
                    .frame(width: 40, alignment: .trailing)
            }
            .font(TerminalTheme.smallFont)
            .foregroundStyle(TerminalTheme.dimText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)

            Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 0) {
                    let sorted = store.feeds.sorted {
                        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    }
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, feed in
                        healthRow(feed, index: idx)
                    }
                }
            }

            Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)

            // Footer
            HStack {
                let totalArticles = store.articles.values.reduce(0) { $0 + store.filterByDate($1).count }
                Text("\(store.feeds.count) feeds | \(totalArticles) articles | \(store.totalUnreadCount) unread")
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.brightText)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(TerminalTheme.panelBackground)
        }
    }

    private func healthRow(_ feed: Feed, index: Int) -> some View {
        let allItems = store.articles[feed.id] ?? []
        let filteredItems = store.filterByDate(allItems)
        let items = filteredItems.count
        let unread = store.unreadCount(for: feed.id)
        let refresh = relativeTime(feed.lastRefreshed)
        let status = feedStatus(feed)
        let namePrefix = feed.isPremium ? "★ " : ""
        let displayName = namePrefix + String(feed.title.uppercased().prefix(feed.isPremium ? 20 : 22))

        return HStack(spacing: 0) {
            Text(displayName)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(TerminalTheme.primaryText)
            Text("\(items)")
                .frame(width: 50, alignment: .trailing)
                .foregroundStyle(TerminalTheme.primaryText)
            Text("\(unread)")
                .frame(width: 50, alignment: .trailing)
                .foregroundStyle(unread > 0 ? TerminalTheme.accentGreen : TerminalTheme.dimText)
            Text(refresh.text)
                .frame(width: 90, alignment: .trailing)
                .foregroundStyle(refresh.color)
            Text(status.text)
                .frame(width: 40, alignment: .trailing)
                .foregroundStyle(status.color)
        }
        .font(TerminalTheme.smallFont)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(index.isMultiple(of: 2) ? TerminalTheme.panelBackground : Color.clear)
    }

    // MARK: - Portfolio Tab

    private var portfolioTab: some View {
        VStack(spacing: 0) {
            // Summary strip
            HStack(spacing: 16) {
                statBlock("POSITIONS", "\(market.watchlist.count)")
                statBlock("UP", "\(market.upCount)", color: TerminalTheme.accentGreen)
                statBlock("DOWN", "\(market.downCount)", color: TerminalTheme.accentRed)
                statBlock("FLAT", "\(market.flatCount)")
                statBlock("NO DATA", "\(market.failedSymbols.count)", color: TerminalTheme.accentAmber)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(TerminalTheme.panelBackground)

            Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)

            ScrollView {
                VStack(spacing: 0) {
                    // Top Gainers
                    if !market.topGainers.isEmpty {
                        sectionHeader("TOP GAINERS")
                        ForEach(market.topGainers) { quote in
                            moverRow(quote, isGainer: true)
                        }
                    }

                    Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)
                        .padding(.vertical, 2)

                    // Top Losers
                    if !market.topLosers.isEmpty {
                        sectionHeader("TOP LOSERS")
                        ForEach(market.topLosers) { quote in
                            moverRow(quote, isGainer: false)
                        }
                    }

                    Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)
                        .padding(.vertical, 2)

                    // Failed symbols
                    if !market.failedSymbols.isEmpty {
                        sectionHeader("NO DATA (\(market.failedSymbols.count))")
                        let failed = market.failedSymbols.sorted()
                        Text(failed.joined(separator: "  "))
                            .font(TerminalTheme.smallFont)
                            .foregroundStyle(TerminalTheme.dimText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func statBlock(_ label: String, _ value: String, color: Color = TerminalTheme.brightText) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(TerminalTheme.titleFont)
                .foregroundStyle(color)
            Text(label)
                .font(TerminalTheme.smallFont)
                .foregroundStyle(TerminalTheme.dimText)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(TerminalTheme.headerFont)
                .foregroundStyle(TerminalTheme.accentOrange)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    private func moverRow(_ quote: StockQuote, isGainer: Bool) -> some View {
        let color = isGainer ? TerminalTheme.accentGreen : TerminalTheme.accentRed
        let sign = isGainer ? "+" : ""
        let bg = isGainer ? TerminalTheme.positiveBackground : TerminalTheme.negativeBackground

        return HStack(spacing: 8) {
            Text(displaySymbol(quote.symbol))
                .font(TerminalTheme.bodyFont)
                .foregroundStyle(TerminalTheme.brightText)
                .frame(width: 70, alignment: .leading)

            Text(String(format: "%.2f", quote.price))
                .font(TerminalTheme.bodyFont)
                .foregroundStyle(TerminalTheme.primaryText)

            Spacer()

            HStack(spacing: 6) {
                Text("\(sign)\(String(format: "%.2f", quote.change))")
                    .foregroundStyle(color)
                Text("\(sign)\(String(format: "%.2f", quote.changePercent))%")
                    .foregroundStyle(color)
            }
            .font(TerminalTheme.smallFont)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(bg)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    // MARK: - Hotkeys Tab

    private var hotkeysTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hotkeySection("NAVIGATION") {
                    hotkeyRow("j / ↓", "Next article")
                    hotkeyRow("k / ↑", "Previous article")
                    hotkeyRow("Enter", "Open article in browser")
                }

                hotkeySection("FEEDS") {
                    hotkeyRow("Cmd + N", "Add new feed")
                    hotkeyRow("Cmd + R", "Refresh all feeds")
                    hotkeyRow("Cmd + Delete", "Unsubscribe feed")
                }

                hotkeySection("ARTICLES") {
                    hotkeyRow("Space", "Toggle read / unread")
                }

                hotkeySection("MARKET") {
                    hotkeyRow("Cmd + M", "Refresh market data")
                }
            }
            .padding(8)
        }
    }

    private func hotkeySection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(TerminalTheme.headerFont)
                .foregroundStyle(TerminalTheme.accentOrange)
                .padding(.vertical, 4)
            content()
            Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)
                .padding(.vertical, 4)
        }
    }

    private func hotkeyRow(_ key: String, _ desc: String) -> some View {
        HStack {
            Text(key)
                .font(TerminalTheme.bodyFont)
                .foregroundStyle(TerminalTheme.brightText)
                .frame(width: 130, alignment: .leading)
            Text(desc)
                .font(TerminalTheme.bodyFont)
                .foregroundStyle(TerminalTheme.primaryText)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func displaySymbol(_ symbol: String) -> String {
        symbol
            .replacingOccurrences(of: ".TO", with: "")
            .replacingOccurrences(of: "-USD", with: "")
    }

    private func relativeTime(_ date: Date?) -> (text: String, color: Color) {
        guard let date = date else { return ("NEVER", TerminalTheme.accentRed) }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 900 { return ("\(seconds / 60)m", TerminalTheme.accentGreen) }
        if seconds < 3600 { return ("\(seconds / 60)m", TerminalTheme.accentAmber) }
        if seconds < 86400 { return ("\(seconds / 3600)h", TerminalTheme.accentAmber) }
        return ("\(seconds / 86400)d", TerminalTheme.accentRed)
    }

    private func feedStatus(_ feed: Feed) -> (text: String, color: Color) {
        guard let last = feed.lastRefreshed else { return ("ERR", TerminalTheme.accentRed) }
        let seconds = Int(Date().timeIntervalSince(last))
        if seconds < 1800 { return ("OK", TerminalTheme.accentGreen) }
        if seconds < 7200 { return ("OLD", TerminalTheme.accentAmber) }
        return ("ERR", TerminalTheme.accentRed)
    }
}
