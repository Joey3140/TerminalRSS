import SwiftUI

struct MarketDashboardStrip: View {
    @EnvironmentObject var store: FeedStore
    @EnvironmentObject var market: MarketStore

    var body: some View {
        VStack(spacing: 0) {
            // Top row: app name, unread, status, movers
            HStack(spacing: 0) {
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

                Spacer()

                // Right: Portfolio pulse + top movers + market status
                HStack(spacing: 10) {
                    if !market.watchlist.isEmpty {
                        HStack(spacing: 4) {
                            Text("\(market.upCount)")
                                .foregroundStyle(TerminalTheme.accentGreen)
                            Text("\u{2191}")
                                .foregroundStyle(TerminalTheme.accentGreen)
                            Text("\(market.downCount)")
                                .foregroundStyle(TerminalTheme.accentRed)
                            Text("\u{2193}")
                                .foregroundStyle(TerminalTheme.accentRed)
                            if market.failedSymbols.count > 0 {
                                Text("\(market.failedSymbols.count)")
                                    .foregroundStyle(TerminalTheme.dimText)
                                Text("\u{2014}")
                                    .foregroundStyle(TerminalTheme.dimText)
                            }
                        }
                        .font(TerminalTheme.smallFont)

                        sep
                    }

                    if let gainer = market.topGainer, gainer.changePercent > 0 {
                        HStack(spacing: 2) {
                            Text("\u{25B2}")
                                .foregroundStyle(TerminalTheme.accentGreen)
                            Text(TerminalTheme.displaySymbol(gainer.symbol))
                                .foregroundStyle(TerminalTheme.brightText)
                            Text(String(format: "+%.1f%%", gainer.changePercent))
                                .foregroundStyle(TerminalTheme.accentGreen)
                        }
                        .font(TerminalTheme.smallFont)
                    }

                    if let loser = market.topLoser, loser.changePercent < 0 {
                        HStack(spacing: 2) {
                            Text("\u{25BC}")
                                .foregroundStyle(TerminalTheme.accentRed)
                            Text(TerminalTheme.displaySymbol(loser.symbol))
                                .foregroundStyle(TerminalTheme.brightText)
                            Text(String(format: "%.1f%%", loser.changePercent))
                                .foregroundStyle(TerminalTheme.accentRed)
                        }
                        .font(TerminalTheme.smallFont)
                    }

                    sep

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
            .padding(.vertical, 4)

            // Bottom row: index charts
            HStack(spacing: 0) {
                ForEach(Array(market.indices.enumerated()), id: \.element.id) { idx, index in
                    if idx > 0 {
                        Rectangle()
                            .fill(TerminalTheme.panelBorder)
                            .frame(width: 1)
                            .padding(.vertical, 4)
                    }
                    indexChartCard(index)
                }

                if market.indices.isEmpty && market.isLoading {
                    Text("LOADING MARKETS...")
                        .font(TerminalTheme.smallFont)
                        .foregroundStyle(TerminalTheme.dimText)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 60)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .background(TerminalTheme.statusBarBackground)
        .onChange(of: store.dateFilter) { _, newFilter in
            market.updateChartRange(newFilter.yahooFinanceRange)
        }
    }

    // MARK: - Index Chart Card

    private func indexChartCard(_ index: MarketIndex) -> some View {
        let isPositive = index.change >= 0
        let color = isPositive ? TerminalTheme.accentGreen : TerminalTheme.accentRed
        let sign = isPositive ? "+" : ""

        return HStack(spacing: 8) {
            // Left: name, price, change
            VStack(alignment: .leading, spacing: 2) {
                Text(index.name)
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.accentAmber)

                Text(formatCompact(index.price))
                    .font(TerminalTheme.headerFont)
                    .foregroundStyle(TerminalTheme.brightText)

                Text("\(sign)\(String(format: "%.1f", index.changePercent))%")
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(color)
            }
            .frame(minWidth: 90, alignment: .leading)

            // Right: sparkline chart
            SparklineChart(
                data: index.sparklineData,
                isPositive: isPositive,
                width: 120,
                height: 40
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var sep: some View {
        Rectangle().fill(TerminalTheme.accentOrange.opacity(0.3)).frame(width: 1, height: 14)
    }

    private func formatCompact(_ price: Double) -> String {
        String(format: "%.0f", price)
    }
}
