import Foundation

struct StockQuote: Identifiable {
    let id: String  // symbol
    let symbol: String
    var price: Double
    var change: Double
    var changePercent: Double
    var sparklineData: [Double]  // intraday close prices for text sparkline
}

struct MarketIndex: Identifiable {
    let id: String  // symbol
    let name: String
    let symbol: String
    var price: Double
    var change: Double
    var changePercent: Double
    var sparklineData: [Double]  // close prices for chart
}
