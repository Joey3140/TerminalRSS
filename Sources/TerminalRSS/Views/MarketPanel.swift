import SwiftUI

struct MarketPanel: View {
    @EnvironmentObject var market: MarketStore
    @State private var newSymbol = ""
    @FocusState private var isAddFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Panel header
            panelHeader

            Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)

            // Watchlist
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(market.watchlist) { quote in
                        quoteRow(quote)
                            .contextMenu {
                                Button("Remove \(quote.symbol)") {
                                    market.removeSymbol(quote.symbol)
                                }
                            }
                    }
                }
            }

            Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)

            // Add symbol input
            addSymbolField
        }
        .background(TerminalTheme.background)
    }

    // MARK: - Panel Header

    private var panelHeader: some View {
        HStack {
            Text("WATCHLIST")
                .font(TerminalTheme.headerFont)
                .foregroundStyle(TerminalTheme.accentOrange)

            Text("\(market.watchlist.count)")
                .font(TerminalTheme.smallFont)
                .foregroundStyle(TerminalTheme.dimText)

            Spacer()

            if let updated = market.lastUpdated {
                Text(updated.formatted(.dateTime.hour().minute().second()))
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.dimText)
            }

            if market.isLoading {
                Text("...")
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.accentGreen)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(TerminalTheme.panelBackground)
    }

    // MARK: - Quote Row

    private func quoteRow(_ quote: StockQuote) -> some View {
        let isFailed = market.failedSymbols.contains(quote.symbol)

        return HStack(spacing: 6) {
            // Symbol — strip suffixes for display
            Text(TerminalTheme.displaySymbol(quote.symbol))
                .font(TerminalTheme.bodyFont)
                .foregroundStyle(isFailed ? TerminalTheme.dimText : TerminalTheme.brightText)
                .frame(width: 65, alignment: .leading)

            if isFailed {
                // Show dashes for failed symbols
                Text("---")
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.dimText)

                Spacer()

                Text("NO DATA")
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.accentAmber)
            } else {
                let isPositive = quote.change >= 0

                // Price
                Text(formatPrice(quote.price))
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.primaryText)

                Spacer()

                // Change with colored background
                changeLabel(change: quote.change, percent: quote.changePercent, isPositive: isPositive)

                // Sparkline
                let spark = sparkline(data: quote.sparklineData)
                Text(spark.text)
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(spark.isUp ? TerminalTheme.accentGreen : TerminalTheme.accentRed)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    // MARK: - Change Label

    private func changeLabel(change: Double, percent: Double, isPositive: Bool) -> some View {
        let sign = isPositive ? "+" : ""
        let color = isPositive ? TerminalTheme.accentGreen : TerminalTheme.accentRed
        let bgColor = isPositive ? TerminalTheme.positiveBackground : TerminalTheme.negativeBackground

        return HStack(spacing: 4) {
            Text("\(sign)\(String(format: "%.2f", change))")
                .foregroundStyle(color)
            Text("\(sign)\(String(format: "%.1f", percent))%")
                .foregroundStyle(color)
        }
        .font(TerminalTheme.smallFont)
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .background(bgColor)
    }

    // MARK: - Add Symbol

    private var addSymbolField: some View {
        HStack(spacing: 4) {
            Text(">")
                .font(TerminalTheme.bodyFont)
                .foregroundStyle(TerminalTheme.accentGreen)

            TextField("add symbol...", text: $newSymbol)
                .textFieldStyle(.plain)
                .font(TerminalTheme.bodyFont)
                .foregroundStyle(TerminalTheme.primaryText)
                .focused($isAddFieldFocused)
                .onSubmit {
                    guard !newSymbol.isEmpty else { return }
                    let symbol = newSymbol
                    newSymbol = ""
                    market.addSymbol(symbol)
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(TerminalTheme.panelBackground)
    }

    // MARK: - Helpers

    private func formatPrice(_ price: Double) -> String {
        if price >= 10000 { return String(format: "%.0f", price) }
        return String(format: "%.2f", price)
    }

    private func sparkline(data: [Double]) -> (text: String, isUp: Bool) {
        guard data.count >= 2 else { return ("", true) }
        let blocks = "▁▂▃▄▅▆▇█"
        let mn = data.min() ?? 0
        let mx = data.max() ?? 1
        let range = mx - mn
        guard range > 0 else { return (String(repeating: "▄", count: min(data.count, 20)), true) }
        let chars = data.suffix(20).map { val -> Character in
            let normalized = (val - mn) / range
            let index = min(Int(normalized * 7), 7)
            return blocks[blocks.index(blocks.startIndex, offsetBy: index)]
        }
        return (String(chars), (data.last ?? 0) >= (data.first ?? 0))
    }
}
