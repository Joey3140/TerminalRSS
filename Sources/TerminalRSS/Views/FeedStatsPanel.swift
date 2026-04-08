import SwiftUI

struct FeedStatsPanel: View {
    @EnvironmentObject var store: FeedStore

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("FEED HEALTH")
                    .font(TerminalTheme.headerFont)
                    .foregroundStyle(TerminalTheme.accentOrange)
                Spacer()
                Text("\(store.feeds.count) feeds")
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.dimText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(TerminalTheme.panelBackground)

            Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)

            // Column headers
            HStack(spacing: 0) {
                Text("FEED")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("ITEMS")
                    .frame(width: 60, alignment: .trailing)
                Text("UNREAD")
                    .frame(width: 70, alignment: .trailing)
                Text("LAST REFRESH")
                    .frame(width: 110, alignment: .trailing)
                Text("STATUS")
                    .frame(width: 65, alignment: .trailing)
            }
            .font(TerminalTheme.smallFont)
            .foregroundStyle(TerminalTheme.dimText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)

            // Feed rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedFeeds.enumerated()), id: \.element.id) { index, feed in
                        feedRow(feed: feed, index: index)
                    }
                }
            }

            Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)

            // Footer
            HStack {
                Text("TOTAL: \(store.feeds.count) feeds  |  \(totalArticles) articles  |  \(totalUnread) unread")
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.brightText)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(TerminalTheme.panelBackground)
        }
        .background(TerminalTheme.background)
    }

    // MARK: - Row

    @ViewBuilder
    private func feedRow(feed: Feed, index: Int) -> some View {
        let itemCount = store.articles[feed.id]?.count ?? 0
        let unread = store.unreadCount(for: feed.id)
        let refresh = relativeTime(feed.lastRefreshed)
        let status = feedStatus(feed)

        HStack(spacing: 0) {
            Text(truncatedName(feed.title))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(TerminalTheme.primaryText)

            Text("\(itemCount)")
                .frame(width: 60, alignment: .trailing)
                .foregroundStyle(TerminalTheme.primaryText)

            Text("\(unread)")
                .frame(width: 70, alignment: .trailing)
                .foregroundStyle(unread > 0 ? TerminalTheme.accentGreen : TerminalTheme.dimText)

            Text(refresh.text)
                .frame(width: 110, alignment: .trailing)
                .foregroundStyle(refresh.color)

            Text(status.text)
                .frame(width: 65, alignment: .trailing)
                .foregroundStyle(status.color)
        }
        .font(TerminalTheme.smallFont)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(index.isMultiple(of: 2) ? TerminalTheme.panelBackground : TerminalTheme.background)
    }

    // MARK: - Computed

    private var sortedFeeds: [Feed] {
        store.feeds.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var totalArticles: Int {
        store.articles.values.reduce(0) { $0 + $1.count }
    }

    private var totalUnread: Int {
        store.feeds.reduce(0) { $0 + store.unreadCount(for: $1.id) }
    }

    // MARK: - Helpers

    private func truncatedName(_ name: String) -> String {
        let upper = name.uppercased()
        if upper.count > 20 {
            return String(upper.prefix(18)) + ".."
        }
        return upper
    }

    private func relativeTime(_ date: Date?) -> (text: String, color: Color) {
        guard let date = date else { return ("NEVER", TerminalTheme.accentRed) }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 900 { return ("\(seconds / 60) min ago", TerminalTheme.accentGreen) }
        if seconds < 3600 { return ("\(seconds / 60) min ago", TerminalTheme.accentAmber) }
        if seconds < 86400 { return ("\(seconds / 3600) hr ago", TerminalTheme.accentAmber) }
        return ("\(seconds / 86400)d ago", TerminalTheme.accentRed)
    }

    private func feedStatus(_ feed: Feed) -> (text: String, color: Color) {
        guard let last = feed.lastRefreshed else { return ("ERROR", TerminalTheme.accentRed) }
        let seconds = Int(Date().timeIntervalSince(last))
        if seconds < 1800 { return ("OK", TerminalTheme.accentGreen) }
        if seconds < 7200 { return ("STALE", TerminalTheme.accentAmber) }
        return ("ERROR", TerminalTheme.accentRed)
    }
}
