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
    private static let marketStatusSymbol = "SPY"
    private static let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

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
            group.addTask { await self.fetchUSMarketStatus() }
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

        // Batch into chunks to avoid rate-limiting from Yahoo Finance
        let chunkSize = 15
        for chunkStart in stride(from: 0, to: watchlistSymbols.count, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, watchlistSymbols.count)
            let chunk = Array(watchlistSymbols[chunkStart..<chunkEnd])

            await withTaskGroup(of: (String, StockQuote?).self) { group in
                for symbol in chunk {
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

    /// Determine the baseline price for change calculation.
    /// For 1d range, use previousClose (standard daily change).
    /// For longer ranges, use the first close in the chart data so the
    /// change reflects the selected period.
    private func baseline(from data: [String: Any]) -> Double? {
        let meta = extractMeta(from: data)
        if chartRange == "1d" {
            return meta["previousClose"] as? Double
        }
        let allCloses = extractAllCloses(from: data)
        if let first = allCloses.first {
            return first
        }
        // Fall back to previousClose if chart data is empty
        return meta["previousClose"] as? Double
    }

    private func fetchIndex(symbol: String, name: String) async -> MarketIndex? {
        guard let data = await fetchChartData(symbol: symbol) else { return nil }

        let meta = extractMeta(from: data)
        guard let price = meta["regularMarketPrice"] as? Double,
              let base = baseline(from: data) else { return nil }

        let change = price - base
        let changePercent = base != 0 ? (change / base) * 100 : 0
        let sparkline = extractAllCloses(from: data)

        return MarketIndex(
            id: symbol,
            name: name,
            symbol: symbol,
            price: price,
            change: change,
            changePercent: changePercent,
            sparklineData: sparkline
        )
    }

    private func fetchQuote(symbol: String) async -> StockQuote? {
        guard let data = await fetchChartData(symbol: symbol) else { return nil }

        let meta = extractMeta(from: data)
        guard let price = meta["regularMarketPrice"] as? Double,
              let base = baseline(from: data) else { return nil }

        let change = price - base
        let changePercent = base != 0 ? (change / base) * 100 : 0

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
            var request = URLRequest(url: url)
            request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
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

    private func extractAllCloses(from json: [String: Any]) -> [Double] {
        let chart = json["chart"] as? [String: Any]
        let results = chart?["result"] as? [[String: Any]]
        let indicators = results?.first?["indicators"] as? [String: Any]
        let quotes = indicators?["quote"] as? [[String: Any]]
        let closes = quotes?.first?["close"] as? [Any] ?? []

        return closes.compactMap { value -> Double? in
            if let d = value as? Double { return d }
            if let n = value as? NSNumber { return n.doubleValue }
            return nil
        }
    }

    private func extractSparkline(from json: [String: Any]) -> [Double] {
        Array(extractAllCloses(from: json).suffix(20))
    }

    private func fetchUSMarketStatus() async {
        guard let data = await fetchChartData(symbol: Self.marketStatusSymbol) else {
            marketStatus = fallbackUSMarketStatus(for: Date())
            return
        }

        marketStatus = deriveUSMarketStatus(from: data, now: Date()) ?? fallbackUSMarketStatus(for: Date())
    }

    private func deriveUSMarketStatus(from json: [String: Any], now: Date) -> String? {
        let meta = extractMeta(from: json)

        if let state = meta["marketState"] as? String {
            return label(forYahooMarketState: state)
        }

        guard let periods = meta["currentTradingPeriod"] as? [String: Any] else {
            return nil
        }

        let nowTimestamp = now.timeIntervalSince1970
        if let regular = periods["regular"] as? [String: Any],
           let start = regular["start"] as? TimeInterval,
           let end = regular["end"] as? TimeInterval,
           nowTimestamp >= start, nowTimestamp < end {
            return "MARKET OPEN"
        }

        if let pre = periods["pre"] as? [String: Any],
           let start = pre["start"] as? TimeInterval,
           let end = pre["end"] as? TimeInterval,
           nowTimestamp >= start, nowTimestamp < end {
            return "PRE-MARKET"
        }

        if let post = periods["post"] as? [String: Any],
           let start = post["start"] as? TimeInterval,
           let end = post["end"] as? TimeInterval,
           nowTimestamp >= start, nowTimestamp < end {
            return "AFTER-HOURS"
        }

        return "MARKET CLOSED"
    }

    private func label(forYahooMarketState state: String) -> String {
        switch state {
        case "REGULAR":
            return "MARKET OPEN"
        case "PRE", "PREPRE":
            return "PRE-MARKET"
        case "POST", "POSTPOST":
            return "AFTER-HOURS"
        case "CLOSED":
            return "MARKET CLOSED"
        default:
            return state.uppercased()
        }
    }

    private func fallbackUSMarketStatus(for now: Date) -> String {
        let nyCalendar = Calendar(identifier: .gregorian)
        guard let newYork = TimeZone(identifier: "America/New_York") else {
            return "MARKET CLOSED"
        }

        var calendar = nyCalendar
        calendar.timeZone = newYork

        if isUSMarketHoliday(now, calendar: calendar) {
            return "MARKET CLOSED"
        }

        let weekday = calendar.component(.weekday, from: now)
        if weekday == 1 || weekday == 7 {
            return "MARKET CLOSED"
        }

        let components = calendar.dateComponents([.hour, .minute], from: now)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        if minutes >= 570 && minutes < 960 {
            return "MARKET OPEN"
        }
        if minutes >= 240 && minutes < 570 {
            return "PRE-MARKET"
        }
        if minutes >= 960 && minutes < 1200 {
            return "AFTER-HOURS"
        }

        return "MARKET CLOSED"
    }

    private func isUSMarketHoliday(_ date: Date, calendar: Calendar) -> Bool {
        let year = calendar.component(.year, from: date)

        let holidays = [
            observedHoliday(month: 1, day: 1, year: year, calendar: calendar),
            nthWeekday(3, weekday: 2, month: 1, year: year, calendar: calendar),  // MLK Day
            nthWeekday(3, weekday: 2, month: 2, year: year, calendar: calendar),  // Presidents Day
            goodFriday(year: year, calendar: calendar),
            lastWeekday(2, month: 5, year: year, calendar: calendar),             // Memorial Day
            observedHoliday(month: 6, day: 19, year: year, calendar: calendar),   // Juneteenth
            observedHoliday(month: 7, day: 4, year: year, calendar: calendar),    // Independence Day
            nthWeekday(1, weekday: 2, month: 9, year: year, calendar: calendar),  // Labor Day
            nthWeekday(4, weekday: 5, month: 11, year: year, calendar: calendar), // Thanksgiving
            observedHoliday(month: 12, day: 25, year: year, calendar: calendar),  // Christmas
        ].compactMap { $0 }

        return holidays.contains {
            calendar.isDate($0, inSameDayAs: date)
        }
    }

    private func observedHoliday(month: Int, day: Int, year: Int, calendar: Calendar) -> Date? {
        guard let actual = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }

        switch calendar.component(.weekday, from: actual) {
        case 7:
            return calendar.date(byAdding: .day, value: -1, to: actual)
        case 1:
            return calendar.date(byAdding: .day, value: 1, to: actual)
        default:
            return actual
        }
    }

    private func nthWeekday(_ ordinal: Int, weekday: Int, month: Int, year: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.weekday = weekday
        components.weekdayOrdinal = ordinal
        return calendar.date(from: components)
    }

    private func lastWeekday(_ weekday: Int, month: Int, year: Int, calendar: Calendar) -> Date? {
        guard let range = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()) else {
            return nil
        }

        for day in range.reversed() {
            if let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
               calendar.component(.weekday, from: date) == weekday {
                return date
            }
        }

        return nil
    }

    private func goodFriday(year: Int, calendar: Calendar) -> Date? {
        guard let easter = easterSunday(year: year, calendar: calendar) else {
            return nil
        }

        return calendar.date(byAdding: .day, value: -2, to: easter)
    }

    private func easterSunday(year: Int, calendar: Calendar) -> Date? {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1

        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
