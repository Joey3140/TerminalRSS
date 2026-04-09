import SwiftUI

struct FeedListView: View {
    @EnvironmentObject var store: FeedStore
    @State private var newFeedURL = ""
    @State private var showDeleteConfirm = false
    @State private var feedToDelete: UUID?
    @FocusState private var isAddFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Panel header — clickable to cycle sort
            panelHeader

            Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)

            // Feed list
            ScrollView {
                LazyVStack(spacing: 0) {
                    // ALL FEEDS row
                    allFeedsRow
                    rankedRow
                    topicsRow

                    Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)
                        .padding(.vertical, 1)

                    ForEach(store.sortedFeeds) { feed in
                        feedRow(feed)
                    }
                }
            }

            Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)

            // Add feed input
            HStack(spacing: 4) {
                Text(">")
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.accentGreen)

                TextField("paste feed URL, hit enter", text: $newFeedURL)
                    .textFieldStyle(.plain)
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.primaryText)
                    .focused($isAddFieldFocused)
                    .onSubmit {
                        guard !newFeedURL.isEmpty else { return }
                        let url = newFeedURL
                        newFeedURL = ""
                        Task { await store.addFeed(urlString: url) }
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(TerminalTheme.panelBackground)
        }
        .background(TerminalTheme.background)
        .alert("Unsubscribe?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Unsubscribe", role: .destructive) {
                if let id = feedToDelete { store.removeFeed(id: id) }
            }
        } message: {
            Text("Remove this feed and all its articles?")
        }
        .onReceive(NotificationCenter.default.publisher(for: .addFeed)) { _ in
            isAddFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteFeed)) { _ in
            if let id = store.selectedFeedID {
                feedToDelete = id
                showDeleteConfirm = true
            }
        }
    }

    // MARK: - ALL FEEDS row

    private var allFeedsRow: some View {
        let isSelected = store.viewMode == .allFeeds
        let unread = store.totalUnreadCount

        return HStack(spacing: 6) {
            Text(isSelected ? ">" : " ")
                .font(TerminalTheme.bodyFont)
                .foregroundStyle(TerminalTheme.accentGreen)
                .frame(width: 14, alignment: .leading)

            Text("ALL FEEDS")
                .font(isSelected ? TerminalTheme.headerFont : TerminalTheme.bodyFont)
                .foregroundStyle(isSelected ? TerminalTheme.accentOrange : TerminalTheme.accentAmber)
                .lineLimit(1)

            Spacer()

            if unread > 0 {
                Text("\(unread)")
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.accentGreen)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(TerminalTheme.accentGreen.opacity(0.15))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? TerminalTheme.selectionBackground : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            store.viewMode = .allFeeds
            store.selectedFeedID = nil
            store.selectedArticleID = nil
        }
    }

    // MARK: - Ranked Row

    private var rankedRow: some View {
        let isSelected = store.viewMode == .ranked
        let clusterCount = store.rankedArticles.count

        return HStack(spacing: 6) {
            Text(isSelected ? ">" : " ")
                .font(TerminalTheme.bodyFont)
                .foregroundStyle(TerminalTheme.accentGreen)
                .frame(width: 14, alignment: .leading)

            Text("★ RANKED")
                .font(isSelected ? TerminalTheme.headerFont : TerminalTheme.bodyFont)
                .foregroundStyle(isSelected ? TerminalTheme.accentOrange : TerminalTheme.accentAmber)
                .lineLimit(1)

            Spacer()

            Text("\(clusterCount)")
                .font(TerminalTheme.smallFont)
                .foregroundStyle(TerminalTheme.dimText)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? TerminalTheme.selectionBackground : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            store.viewMode = .ranked
            store.selectedFeedID = nil
            store.selectedArticleID = nil
        }
    }

    // MARK: - Topics Row

    private var topicsRow: some View {
        let isSelected = store.viewMode == .topics
        let topicCount = store.topicGroups.count

        return HStack(spacing: 6) {
            Text(isSelected ? ">" : " ")
                .font(TerminalTheme.bodyFont)
                .foregroundStyle(TerminalTheme.accentGreen)
                .frame(width: 14, alignment: .leading)

            Text("◆ TOPICS")
                .font(isSelected ? TerminalTheme.headerFont : TerminalTheme.bodyFont)
                .foregroundStyle(isSelected ? TerminalTheme.accentOrange : TerminalTheme.accentAmber)
                .lineLimit(1)

            Spacer()

            Text("\(topicCount)")
                .font(TerminalTheme.smallFont)
                .foregroundStyle(TerminalTheme.dimText)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? TerminalTheme.selectionBackground : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            store.viewMode = .topics
            store.selectedFeedID = nil
            store.selectedArticleID = nil
        }
    }

    // MARK: - Feed Row

    private func feedRow(_ feed: Feed) -> some View {
        let isSelected = store.selectedFeedID == feed.id
        let unread = store.unreadCount(for: feed.id)

        return HStack(spacing: 6) {
            Text(isSelected ? ">" : " ")
                .font(TerminalTheme.bodyFont)
                .foregroundStyle(TerminalTheme.accentGreen)
                .frame(width: 14, alignment: .leading)

            Text(feed.title.uppercased())
                .font(isSelected ? TerminalTheme.headerFont : TerminalTheme.bodyFont)
                .foregroundStyle(isSelected ? TerminalTheme.brightText : TerminalTheme.primaryText)
                .lineLimit(1)

            if feed.isPremium {
                Text("★")
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.accentAmber)
            }

            Spacer()

            if unread > 0 {
                Text("\(unread)")
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.accentGreen)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(TerminalTheme.accentGreen.opacity(0.15))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? TerminalTheme.selectionBackground : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            store.viewMode = .feed(feed.id)
            store.selectedFeedID = feed.id
            store.selectedArticleID = nil
        }
        .contextMenu {
            Button(feed.isPremium ? "Remove Premium ★" : "Mark as Premium ★") {
                store.togglePremium(feed.id)
            }
        }
    }

    // MARK: - Panel Header (clickable sort toggle)

    private var panelHeader: some View {
        HStack {
            Text("FEEDS")
                .font(TerminalTheme.headerFont)
                .foregroundStyle(TerminalTheme.accentOrange)

            Spacer()

            // Sort mode — clickable
            Button {
                store.cycleFeedSort()
            } label: {
                HStack(spacing: 3) {
                    Text("SORT:")
                        .foregroundStyle(TerminalTheme.dimText)
                    Text(store.feedSortMode.rawValue)
                        .foregroundStyle(TerminalTheme.accentAmber)
                }
                .font(TerminalTheme.smallFont)
            }
            .buttonStyle(.plain)

            Text("\(store.feeds.count)")
                .font(TerminalTheme.smallFont)
                .foregroundStyle(TerminalTheme.dimText)
                .padding(.leading, 6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(TerminalTheme.panelBackground)
    }
}
