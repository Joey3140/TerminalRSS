import SwiftUI

struct MarketDashboardStrip: View {
    @EnvironmentObject var store: FeedStore
    @EnvironmentObject var market: MarketStore

    var body: some View {
        HStack(spacing: 0) {
            // Left: App name + unread
            HStack(spacing: 10) {
                Text("TERMINALRSS")
                    .font(TerminalTheme.headerFont)
                    .foregroundStyle(TerminalTheme.accentOrange)

                sep

                let unread = store.totalUnreadCount
                if unread > 0 {
                    Text("\(unread) UNREAD")
                        .font(TerminalTheme.smallFont)
                        .foregroundStyle(TerminalTheme.accentGreen)
                }

                if store.isRefreshing {
                    Text("FETCHING...")
                        .font(TerminalTheme.smallFont)
                        .foregroundStyle(TerminalTheme.accentGreen)
                }
            }
            .frame(minWidth: 200, alignment: .leading)

            sep

            // Center: Indices inline
            HStack(spacing: 14) {
                ForEach(market.indices) { index in
                    indexChip(index)
                }
                if market.indices.isEmpty && market.isLoading {
                    Text("LOADING MARKETS...")
                        .font(TerminalTheme.smallFont)
                        .foregroundStyle(TerminalTheme.dimText)
                }
            }

            Spacer()

            // Right: Portfolio pulse + top movers + market status
            HStack(spacing: 10) {
                // Portfolio pulse
                if !market.watchlist.isEmpty {
                    HStack(spacing: 4) {
                        Text("\(market.upCount)")
                            .foregroundStyle(TerminalTheme.accentGreen)
                        Text("↑")
                            .foregroundStyle(TerminalTheme.accentGreen)
                        Text("\(market.downCount)")
                            .foregroundStyle(TerminalTheme.accentRed)
                        Text("↓")
                            .foregroundStyle(TerminalTheme.accentRed)
                        if market.failedSymbols.count > 0 {
                            Text("\(market.failedSymbols.count)")
                                .foregroundStyle(TerminalTheme.dimText)
                            Text("—")
                                .foregroundStyle(TerminalTheme.dimText)
                        }
                    }
                    .font(TerminalTheme.smallFont)

                    sep
                }

                // Top movers
                if let gainer = market.topGainer, gainer.changePercent > 0 {
                    HStack(spacing: 2) {
                        Text("▲")
                            .foregroundStyle(TerminalTheme.accentGreen)
                        Text(displaySymbol(gainer.symbol))
                            .foregroundStyle(TerminalTheme.brightText)
                        Text(String(format: "+%.1f%%", gainer.changePercent))
                            .foregroundStyle(TerminalTheme.accentGreen)
                    }
                    .font(TerminalTheme.smallFont)
                }

                if let loser = market.topLoser, loser.changePercent < 0 {
                    HStack(spacing: 2) {
                        Text("▼")
                            .foregroundStyle(TerminalTheme.accentRed)
                        Text(displaySymbol(loser.symbol))
                            .foregroundStyle(TerminalTheme.brightText)
                        Text(String(format: "%.1f%%", loser.changePercent))
                            .foregroundStyle(TerminalTheme.accentRed)
                    }
                    .font(TerminalTheme.smallFont)
                }

                sep

                // Market status
                Text(market.marketStatus)
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(
                        market.marketStatus == "MARKET OPEN"
                            ? TerminalTheme.accentGreen
                            : TerminalTheme.dimText
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(TerminalTheme.statusBarBackground)
        .onChange(of: store.dateFilter) { _, newFilter in
            market.updateChartRange(newFilter.yahooFinanceRange)
        }
    }

    // MARK: - Index Chip

    private func indexChip(_ index: MarketIndex) -> some View {
        let isPositive = index.change >= 0
        let color = isPositive ? TerminalTheme.accentGreen : TerminalTheme.accentRed
        let sign = isPositive ? "+" : ""

        return HStack(spacing: 4) {
            Text(index.name)
                .foregroundStyle(TerminalTheme.brightText)
            Text(formatCompact(index.price))
                .foregroundStyle(TerminalTheme.primaryText)
            Text("\(sign)\(String(format: "%.1f", index.changePercent))%")
                .foregroundStyle(color)
        }
        .font(TerminalTheme.smallFont)
    }

    // MARK: - Helpers

    private var sep: some View {
        Rectangle().fill(TerminalTheme.accentOrange.opacity(0.3)).frame(width: 1, height: 14)
    }

    private func formatCompact(_ price: Double) -> String {
        if price >= 10000 { return String(format: "%.0f", price) }
        return String(format: "%.0f", price)
    }

    private func displaySymbol(_ symbol: String) -> String {
        // Strip .TO and -USD suffixes for compact display
        symbol
            .replacingOccurrences(of: ".TO", with: "")
            .replacingOccurrences(of: "-USD", with: "")
    }
}
