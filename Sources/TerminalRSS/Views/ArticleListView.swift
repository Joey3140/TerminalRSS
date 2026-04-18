import SwiftUI

struct ArticleListView: View {
    @EnvironmentObject var store: FeedStore

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MM/dd HH:mm"
        return df
    }()

    private var isAllFeedsMode: Bool { store.selectedFeedID == nil }

    var body: some View {
        VStack(spacing: 0) {
            // Panel header
            HStack {
                Text("ARTICLES")
                    .font(TerminalTheme.headerFont)
                    .foregroundStyle(TerminalTheme.accentOrange)

                if store.isTopicsMode {
                    Text("— TOPICS")
                        .font(TerminalTheme.smallFont)
                        .foregroundStyle(TerminalTheme.accentAmber)
                    Text("\(store.topicGroups.count) topics")
                        .font(TerminalTheme.smallFont)
                        .foregroundStyle(TerminalTheme.dimText)
                        .padding(.leading, 4)
                } else if case .flagged(let flag) = store.viewMode {
                    Text("— \(flag.icon) \(flag.rawValue)")
                        .font(TerminalTheme.smallFont)
                        .foregroundStyle(TerminalTheme.accentAmber)
                } else if store.isRankedMode {
                    Text("— RANKED")
                        .font(TerminalTheme.smallFont)
                        .foregroundStyle(TerminalTheme.accentAmber)
                    Text("\(store.rankedArticles.count) stories")
                        .font(TerminalTheme.smallFont)
                        .foregroundStyle(TerminalTheme.dimText)
                        .padding(.leading, 4)
                } else if isAllFeedsMode {
                    Text("— ALL FEEDS")
                        .font(TerminalTheme.smallFont)
                        .foregroundStyle(TerminalTheme.accentAmber)
                } else if let feed = store.selectedFeed {
                    Text("— \(feed.title.uppercased())")
                        .font(TerminalTheme.smallFont)
                        .foregroundStyle(TerminalTheme.dimText)
                        .lineLimit(1)
                }

                Spacer()

                // Sort mode — clickable (hidden in ranked mode)
                if !store.isRankedMode && !store.isTopicsMode {
                    Button {
                        store.cycleArticleSort()
                    } label: {
                        HStack(spacing: 3) {
                            Text("SORT:")
                                .foregroundStyle(TerminalTheme.dimText)
                            Text(store.articleSortMode.rawValue)
                                .foregroundStyle(TerminalTheme.accentAmber)
                        }
                        .font(TerminalTheme.smallFont)
                    }
                    .buttonStyle(.plain)
                }

                Text("\(store.isTopicsMode ? store.topicFlatClusters.count : store.isRankedMode ? store.rankedArticles.count : store.selectedArticles.count)")
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.dimText)
                    .padding(.leading, 6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(TerminalTheme.panelBackground)

            Rectangle().fill(TerminalTheme.panelBorder).frame(height: 1)

            if store.isTopicsMode {
                if store.topicGroups.isEmpty {
                    Spacer()
                    Text("NO TOPICS")
                        .font(TerminalTheme.bodyFont)
                        .foregroundStyle(TerminalTheme.dimText)
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(store.topicGroups) { group in
                                    topicHeader(group)
                                        .id("topic-\(group.id)")

                                    if store.expandedTopicIDs.contains(group.id) {
                                        ForEach(group.clusters) { cluster in
                                            clusterRow(cluster)
                                                .id(cluster.id)

                                            if store.expandedClusterIDs.contains(cluster.id) {
                                                ForEach(cluster.sources.filter { $0.id != cluster.primaryArticle.id }) { source in
                                                    sourceRow(source)
                                                        .id(source.id)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .onChange(of: store.selectedArticleID) { _, newID in
                            if let id = newID {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            } else if store.isRankedMode {
                if store.rankedArticles.isEmpty {
                    Spacer()
                    Text("NO RANKED STORIES")
                        .font(TerminalTheme.bodyFont)
                        .foregroundStyle(TerminalTheme.dimText)
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(store.rankedArticles) { cluster in
                                    clusterRow(cluster)
                                        .id(cluster.id)

                                    if store.expandedClusterIDs.contains(cluster.id) {
                                        ForEach(cluster.sources.filter { $0.id != cluster.primaryArticle.id }) { source in
                                            sourceRow(source)
                                                .id(source.id)
                                        }
                                    }
                                }
                            }
                        }
                        .onChange(of: store.selectedArticleID) { _, newID in
                            if let id = newID {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            } else if store.selectedArticles.isEmpty {
                Spacer()
                Text("NO ARTICLES")
                    .font(TerminalTheme.bodyFont)
                    .foregroundStyle(TerminalTheme.dimText)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.selectedArticles) { article in
                                articleRow(article)
                                    .id(article.id)
                            }
                        }
                    }
                    .onChange(of: store.selectedArticleID) { _, newID in
                        if let id = newID {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .background(TerminalTheme.background)
    }

    // MARK: - Topic Header

    private func topicHeader(_ group: TopicGroup) -> some View {
        let isExpanded = store.expandedTopicIDs.contains(group.id)

        return HStack(spacing: 8) {
            Text(isExpanded ? "▼" : "▶")
                .font(TerminalTheme.smallFont)
                .foregroundStyle(TerminalTheme.dimText)
                .frame(width: 12)

            Text(group.topic)
                .font(TerminalTheme.headerFont)
                .foregroundStyle(TerminalTheme.accentOrange)

            Spacer()

            Text("\(group.articleCount)")
                .font(TerminalTheme.smallFont)
                .foregroundStyle(TerminalTheme.accentAmber)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(TerminalTheme.accentAmber.opacity(0.15))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(TerminalTheme.panelBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            store.toggleTopicExpansion(group.id)
        }
    }

    // MARK: - Cluster Row (Ranked Mode)

    private func clusterRow(_ cluster: ArticleCluster) -> some View {
        let isSelected = store.selectedArticleID == cluster.primaryArticle.id
        let isRead = store.isRead(cluster.primaryArticle.id)
        let isExpanded = store.expandedClusterIDs.contains(cluster.id)

        return HStack(spacing: 8) {
            // Date
            Text(cluster.primaryArticle.pubDate.map { Self.dateFormatter.string(from: $0) } ?? "—")
                .font(TerminalTheme.smallFont)
                .foregroundStyle(TerminalTheme.accentAmber)
                .frame(width: 88, alignment: .leading)

            // Expand indicator
            Text(isExpanded ? "▼" : "▶")
                .font(TerminalTheme.smallFont)
                .foregroundStyle(TerminalTheme.dimText)
                .frame(width: 12)

            // Title
            Text(cluster.primaryArticle.title)
                .font(isRead ? TerminalTheme.bodyFont : TerminalTheme.headerFont)
                .foregroundStyle(isRead ? TerminalTheme.dimText : TerminalTheme.primaryText)
                .lineLimit(1)

            Spacer()

            // Source count badge
            if cluster.sourceCount > 1 {
                Text("\(cluster.sourceCount) sources")
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.accentAmber)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(TerminalTheme.accentAmber.opacity(0.15))
            }

            // Premium indicator
            if cluster.hasPremiumSource {
                Text("★")
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.accentAmber)
            }

            // Score
            Text(String(format: "%.1f", cluster.score))
                .font(TerminalTheme.smallFont)
                .foregroundStyle(TerminalTheme.dimText)
                .frame(width: 35, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(isSelected ? TerminalTheme.selectionBackground : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            store.toggleClusterExpansion(cluster.id)
            store.selectedArticleID = cluster.primaryArticle.id
            store.markRead(cluster.primaryArticle.id)
        }
    }

    // MARK: - Source Row (Expanded Cluster)

    private func sourceRow(_ source: FeedItem) -> some View {
        let isSelected = store.selectedArticleID == source.id
        let isRead = store.isRead(source.id)

        return HStack(spacing: 8) {
            // Indent
            Text("")
                .frame(width: 88)

            Text("├")
                .font(TerminalTheme.smallFont)
                .foregroundStyle(TerminalTheme.dimText)
                .frame(width: 12)

            Text(source.title)
                .font(isRead ? TerminalTheme.bodyFont : TerminalTheme.headerFont)
                .foregroundStyle(isRead ? TerminalTheme.dimText : TerminalTheme.primaryText)
                .lineLimit(1)

            Spacer()

            if let feedName = store.feedName(for: source.id) {
                Text(feedName.uppercased())
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.accentAmber)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(isSelected ? TerminalTheme.selectionBackground : TerminalTheme.panelBackground.opacity(0.5))
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedArticleID = source.id
            store.markRead(source.id)
        }
    }

    // MARK: - Article Row

    private func articleRow(_ article: FeedItem) -> some View {
        let isSelected = store.selectedArticleID == article.id
        let isRead = store.isRead(article.id)

        return HStack(spacing: 8) {
            // Date
            Text(article.pubDate.map { Self.dateFormatter.string(from: $0) } ?? "—")
                .font(TerminalTheme.smallFont)
                .foregroundStyle(TerminalTheme.accentAmber)
                .frame(width: 88, alignment: .leading)

            // Unread dot
            Circle()
                .fill(isRead ? Color.clear : TerminalTheme.accentGreen)
                .frame(width: 6, height: 6)

            // Flag indicator
            if let flag = store.flag(for: article.id) {
                Text(flag.icon)
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.accentAmber)
            }

            // Title
            Text(article.title)
                .font(isRead ? TerminalTheme.bodyFont : TerminalTheme.headerFont)
                .foregroundStyle(isRead ? TerminalTheme.dimText : TerminalTheme.primaryText)
                .lineLimit(1)

            Spacer()

            // Source label in ALL FEEDS mode, author otherwise
            if isAllFeedsMode {
                if let source = store.feedName(for: article.id) {
                    Text(source.uppercased())
                        .font(TerminalTheme.smallFont)
                        .foregroundStyle(TerminalTheme.accentAmber)
                        .lineLimit(1)
                        .frame(maxWidth: 120, alignment: .trailing)
                }
            } else if let author = article.author {
                Text(author)
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.dimText)
                    .lineLimit(1)
                    .frame(maxWidth: 100, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(isSelected ? TerminalTheme.selectionBackground : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedArticleID = article.id
            store.markRead(article.id)
        }
        .contextMenu {
            ForEach(ArticleFlag.allCases, id: \.rawValue) { flag in
                Button {
                    store.toggleFlag(article.id, flag: flag)
                } label: {
                    if store.flag(for: article.id) == flag {
                        Text("Remove \(flag.icon) \(flag.rawValue)")
                    } else {
                        Text("\(flag.icon) \(flag.rawValue)")
                    }
                }
            }
            if store.flag(for: article.id) != nil {
                Divider()
                Button("Remove Flag") {
                    store.removeFlag(article.id)
                }
            }
        }
    }
}
