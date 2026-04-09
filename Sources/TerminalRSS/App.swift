import SwiftUI

@main
struct TerminalRSSApp: App {
    @StateObject private var store = FeedStore()
    @StateObject private var market = MarketStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(market)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 900)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Feed") {
                    NotificationCenter.default.post(name: .addFeed, object: nil)
                }
                .keyboardShortcut("n")
            }

            CommandMenu("Feed") {
                Button("Refresh All Feeds") {
                    Task { await store.refreshAll() }
                }
                .keyboardShortcut("r")

                Divider()

                Button("Unsubscribe Feed") {
                    NotificationCenter.default.post(name: .deleteFeed, object: nil)
                }
                .keyboardShortcut(.delete)
            }

            CommandMenu("Market") {
                Button("Refresh Market Data") {
                    Task { await market.refreshMarketData() }
                }
                .keyboardShortcut("m")
            }
        }
    }
}
