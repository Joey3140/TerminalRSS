import SwiftUI
import Combine

@MainActor
class MarketStore: ObservableObject {
    @Published var indices: [MarketIndex] = []
    @Published var watchlist: [StockQuote] = []
    @Published var watchlistSymbols: [String] = []
    @Published var lastUpdated: Date?
    @Published var isLoading = false
    @Published var marketStatus: String = "MARKET CLOSED"
    @Published var errorMessage: String?
    @Published var failedSymbols: Set<String> = []
    @Published var chartRange: String = "1d"

    private var refreshCancellable: AnyCancellable?

    // Generic starter watchlist — well-known names across US, Canada, and crypto.
    // Users can add/remove symbols from the in-app watchlist UI; their selection
    // persists to UserDefaults and overrides this default on subsequent launches.
    private static let defaultSymbols = [
        // US Stocks
        "AAPL", "MSFT", "GOOG", "NVDA", "AMZN", "META", "AMD",
        // Canadian Stocks (TSX — .TO suffix for Yahoo Finance)
        "SHOP.TO", "ENB.TO", "RY.TO",
        // Crypto
        "BTC-USD", "ETH-USD",
    ]
    // Bumped key version to reset saved watchlist to new defaults
    private static let userDefaultsKey = "TerminalRSS.watchlistSymbols.v2"

    private static let indexSymbols: [(symbol: String, name: String)] = [
        ("^GSPC", "S&P 500"),
        ("^IXIC", "NASDAQ"),
        ("^DJI", "DOW"),
        ("^GSPTSE", "TSX"),
    ]

    init() {
        if let saved = UserDefaults.standard.array(forKey: Self.userDefaultsKey) as? [String], !saved.isEmpty {
            watchlistSymbols = saved
        } else {
            watchlistSymbols = Self.defaultSymbols
        }

        // Auto-refresh every 60 seconds
        refreshCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshMarketData() }
            }

        // Initial fetch
        Task { await refreshMarketData() }
    }

    // MARK: - Watchlist Management

    func addSymbol(_ symbol: String) {
        let cleaned = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleaned.isEmpty, !watchlistSymbols.contains(cleaned) else { return }
        watchlistSymbols.append(cleaned)
        saveWatchlist()
        Task { await refreshMarketData() }
    }

    func removeSymbol(_ symbol: String) {
        watchlistSymbols.removeAll { $0 == symbol }
        watchlist.removeAll { $0.symbol == symbol }
        saveWatchlist()
    }

    private func saveWatchlist() {
        UserDefaults.standard.set(watchlistSymbols, forKey: Self.userDefaultsKey)
    }

    // MARK: - Data Fetching

    func refreshMarketData() async {
        isLoading = true
        errorMessage = nil

        // Fetch indices and watchlist concurrently
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchIndices() }
            group.addTask { await self.fetchWatchlist() }
        }

        lastUpdated = Date()
        isLoading = false
    }

    private func fetchIndices() async {
        var results: [MarketIndex] = []

        await withTaskGroup(of: MarketIndex?.self) { group in
            for entry in Self.indexSymbols {
                group.addTask {
                    await self.fetchIndex(symbol: entry.symbol, name: entry.name)
                }
            }
            for await result in group {
                if let index = result {
                    results.append(index)
                }
            }
        }

        // Preserve ordering: S&P, NASDAQ, DOW
        let orderedSymbols = Self.indexSymbols.map(\.symbol)
        indices = results.sorted { a, b in
            (orderedSymbols.firstIndex(of: a.symbol) ?? 0) < (orderedSymbols.firstIndex(of: b.symbol) ?? 0)
        }
    }

    private func fetchWatchlist() async {
        var results: [String: StockQuote] = [:]

        await withTaskGroup(of: (String, StockQuote?).self) { group in
            for symbol in watchlistSymbols {
                group.addTask {
                    let quote = await self.fetchQuote(symbol: symbol)
                    return (symbol, quote)
                }
            }
            for await (symbol, result) in group {
                if let quote = result {
                    results[symbol] = quote
                }
            }
        }

        // Track which symbols failed
        failedSymbols = Set(watchlistSymbols.filter { results[$0] == nil })

        // Preserve user's ordering — include failed symbols with placeholder
        watchlist = watchlistSymbols.map { sym in
            results[sym] ?? StockQuote(id: sym, symbol: sym, price: 0,
                                       change: 0, changePercent: 0, sparklineData: [])
        }
    }

    // MARK: - Portfolio Computed Properties

    var upCount: Int {
        watchlist.filter { !failedSymbols.contains($0.symbol) && $0.change > 0 }.count
    }

    var downCount: Int {
        watchlist.filter { !failedSymbols.contains($0.symbol) && $0.change < 0 }.count
    }

    var flatCount: Int {
        watchlist.filter { !failedSymbols.contains($0.symbol) && $0.change == 0 }.count
    }

    var topGainer: StockQuote? {
        watchlist.filter { !failedSymbols.contains($0.symbol) }
            .max { $0.changePercent < $1.changePercent }
    }

    var topLoser: StockQuote? {
        watchlist.filter { !failedSymbols.contains($0.symbol) }
            .min { $0.changePercent < $1.changePercent }
    }

    var topGainers: [StockQuote] {
        Array(watchlist.filter { !failedSymbols.contains($0.symbol) && $0.change > 0 }
            .sorted { $0.changePercent > $1.changePercent }
            .prefix(5))
    }

    var topLosers: [StockQuote] {
        Array(watchlist.filter { !failedSymbols.contains($0.symbol) && $0.change < 0 }
            .sorted { $0.changePercent < $1.changePercent }
            .prefix(5))
    }

    private func fetchIndex(symbol: String, name: String) async -> MarketIndex? {
        guard let data = await fetchChartData(symbol: symbol) else { return nil }

        let meta = extractMeta(from: data)
        guard let price = meta["regularMarketPrice"] as? Double,
              let previousClose = meta["previousClose"] as? Double else { return nil }

        // Update market status from any successful fetch
        if let state = meta["marketState"] as? String {
            updateMarketStatus(state)
        }

        let change = price - previousClose
        let changePercent = previousClose != 0 ? (change / previousClose) * 100 : 0

        return MarketIndex(
            id: symbol,
            name: name,
            symbol: symbol,
            price: price,
            change: change,
            changePercent: changePercent
        )
    }

    private func fetchQuote(symbol: String) async -> StockQuote? {
        guard let data = await fetchChartData(symbol: symbol) else { return nil }

        let meta = extractMeta(from: data)
        guard let price = meta["regularMarketPrice"] as? Double,
              let previousClose = meta["previousClose"] as? Double else { return nil }

        if let state = meta["marketState"] as? String {
            updateMarketStatus(state)
        }

        let change = price - previousClose
        let changePercent = previousClose != 0 ? (change / previousClose) * 100 : 0

        // Extract sparkline from close prices
        let sparkline = extractSparkline(from: data)

        return StockQuote(
            id: symbol,
            symbol: symbol,
            price: price,
            change: change,
            changePercent: changePercent,
            sparklineData: sparkline
        )
    }

    // MARK: - Chart Range

    func updateChartRange(_ range: String) {
        guard chartRange != range else { return }
        chartRange = range
        Task { await refreshMarketData() }
    }

    private var chartInterval: String {
        switch chartRange {
        case "1d": return "5m"
        case "5d": return "15m"
        case "1mo": return "1d"
        case "3mo": return "1d"
        default: return "5m"
        }
    }

    private func fetchChartData(symbol: String) async -> [String: Any]? {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=\(chartRange)&interval=\(chartInterval)") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json
        } catch {
            return nil
        }
    }

    private func extractMeta(from json: [String: Any]) -> [String: Any] {
        let chart = json["chart"] as? [String: Any]
        let results = chart?["result"] as? [[String: Any]]
        return results?.first?["meta"] as? [String: Any] ?? [:]
    }

    private func extractSparkline(from json: [String: Any]) -> [Double] {
        let chart = json["chart"] as? [String: Any]
        let results = chart?["result"] as? [[String: Any]]
        let indicators = results?.first?["indicators"] as? [String: Any]
        let quotes = indicators?["quote"] as? [[String: Any]]
        let closes = quotes?.first?["close"] as? [Any] ?? []

        // Filter nils and convert to doubles, take last 20
        let values = closes.compactMap { value -> Double? in
            if let d = value as? Double { return d }
            if let n = value as? NSNumber { return n.doubleValue }
            return nil
        }
        return Array(values.suffix(20))
    }

    private func updateMarketStatus(_ state: String) {
        switch state {
        case "REGULAR":
            marketStatus = "MARKET OPEN"
        case "PRE":
            marketStatus = "PRE-MARKET"
        case "POST":
            marketStatus = "AFTER-HOURS"
        case "CLOSED":
            marketStatus = "MARKET CLOSED"
        default:
            marketStatus = state.uppercased()
        }
    }
}
