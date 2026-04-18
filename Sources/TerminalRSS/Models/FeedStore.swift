import SwiftUI

enum FeedSortMode: String, Codable, CaseIterable {
    case name = "NAME"
    case unreadCount = "UNREAD"
    case dateAdded = "ADDED"
}

enum ArticleSortMode: String, Codable, CaseIterable {
    case date = "DATE"
    case title = "TITLE"
    case readStatus = "STATUS"
}

enum ArticleFlag: String, Codable, CaseIterable {
    case readLater = "READ LATER"
    case favorite = "FAVORITE"
    case flag = "FLAG"

    var icon: String {
        switch self {
        case .readLater: return "◷"
        case .favorite: return "♥"
        case .flag: return "⚑"
        }
    }
}

enum ViewMode: Equatable {
    case allFeeds
    case ranked
    case topics
    case flagged(ArticleFlag)
    case feed(UUID)
}

@MainActor
class FeedStore: ObservableObject {
    @Published var feeds: [Feed] = []
    @Published var articles: [UUID: [FeedItem]] = [:]
    @Published var readArticleIDs: Set<String> = []
    @Published var selectedFeedID: UUID? {
        didSet { rebuildSelectedArticles() }
    }
    @Published var selectedArticleID: String?
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var feedSortMode: FeedSortMode = .name
    @Published var articleSortMode: ArticleSortMode = .date {
        didSet { rebuildSelectedArticles() }
    }
    @Published var dateFilter: DateFilter = .all {
        didSet { rebuildSelectedArticles() }
    }
    @Published var viewMode: ViewMode = .allFeeds {
        didSet { rebuildSelectedArticles() }
    }
    @Published var expandedClusterIDs: Set<String> = []
    @Published var expandedTopicIDs: Set<String> = []
    @Published var flaggedArticles: [String: ArticleFlag] = [:]

    // Cached derived data — rebuilt via rebuildCaches()
    private var _cachedRankedArticles: [ArticleCluster]?
    private var _cachedTopicGroups: [TopicGroup]?
    @Published private(set) var cachedSelectedArticles: [FeedItem] = []
    private var articleFeedLookup: [String: UUID] = [:]
    private var articlesByID: [String: FeedItem] = [:]
    private var feedsByID: [UUID: Feed] = [:]

    private let maxArticlesPerFeed = 200
    private var pendingSaveWork: DispatchWorkItem?
    private let saveURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TerminalRSS")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        saveURL = dir.appendingPathComponent("feeds.json")
        load()
        selectedFeedID = nil  // ALL FEEDS mode on launch
        if feeds.isEmpty {
            Task { await populateDefaultFeeds() }
        } else {
            // Add any new default feeds not yet subscribed
            Task { await addMissingDefaultFeeds() }
        }
    }

    // MARK: - Default Feeds

    private static let defaultFeedURLs = [
        // Tech
        "https://feeds.arstechnica.com/arstechnica/index",
        "https://hnrss.org/frontpage",
        "https://daringfireball.net/feeds/main",
        "https://www.theverge.com/rss/index.xml",
        "https://techcrunch.com/feed/",
        "https://lobste.rs/rss",
        "https://www.wired.com/feed/rss",
        "https://9to5mac.com/feed/",
        "https://www.macrumors.com/macrumors.xml",
        // News
        "https://feeds.bbci.co.uk/news/rss.xml",
        "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml",
        "https://feeds.npr.org/1001/rss.xml",
        "https://www.theguardian.com/world/rss",
        "https://feeds.reuters.com/reuters/topNews",
        // Science & Space
        "https://www.nasa.gov/rss/dyn/breaking_news.rss",
        // Security
        "https://krebsonsecurity.com/feed/",
        // Dev
        "https://dev.to/feed",
        "https://blog.rust-lang.org/feed.xml",
        // Substacks & Newsletters
        "https://www.zinebriboua.com/feed",
        "https://natesnewsletter.substack.com/feed",
        "https://aiguide.substack.com/feed",
        "https://www.nadaveyal.com/feed",
        "https://www.bullionbite.com/feed",
        "https://toronto.cityhallwatcher.com/feed",
        "https://www.thestar.com/content/thestar/feed.RSSManagerServlet.articles.topstories.rss",
        "https://www.cbc.ca/webfeed/rss/rss-topstories",
        "https://www.techmeme.com/feed.xml",
        "https://www.memeorandum.com/feed.xml",
        "https://www.lennysnewsletter.com/feed",
        "https://garymarcus.substack.com/feed",
        "https://aswathdamodaran.substack.com/feed",
        "https://www.oneusefulthing.org/feed",
        "https://simonw.substack.com/feed",
        "https://sophiebakalar.substack.com/feed",
        "https://annieduke.substack.com/feed",
        "https://www.uncommons.ca/feed",
        "https://www.thereset.news/feed",
        "https://mariepascual.substack.com/feed",
        // Tech Analysis & Engineering Blogs
        "https://stratechery.com/feed/",
        "https://github.blog/feed/",
        "https://stackoverflow.blog/feed/",
        "https://netflixtechblog.com/feed",
        "https://labs.spotify.com/feed/",
        "https://world.hey.com/dhh/feed",
        "https://www.cnbc.com/id/100003114/device/rss/rss.html",
        "https://rss.slashdot.org/Slashdot/slashdotMain",
        // Programming & Software Engineering
        "https://www.aaronsw.com/2002/feeds/pgessays.rss",
        "https://www.joelonsoftware.com/feed/",
        "https://feeds.feedburner.com/codinghorror",
        "https://martinfowler.com/feed.atom",
        "https://overreacted.io/rss.xml",
        "https://robertheaton.com/feed.xml",
        // Science
        "https://www.nature.com/nature.rss",
        "https://rss.nytimes.com/services/xml/rss/nyt/Science.xml",
        // Apple / Swift / macOS Dev
        "https://www.swiftbysundell.com/feed.rss",
        "https://developer.apple.com/news/rss/news.rss",
        "https://useyourloaf.com/blog/rss.xml",
        "https://inessential.com/xml/rss.xml",
        "https://oleb.net/blog/atom.xml",
        // Fun
        "https://xkcd.com/rss.xml",
        // Engineering Blogs (wave 2)
        "https://engineering.fb.com/feed/",
        "https://slack.engineering/feed",
        "https://feed.infoq.com",
        "https://blog.jetbrains.com/feed",
        // Apple Ecosystem (wave 2)
        "https://www.macstories.net/feed",
        "https://marco.org/rss",
        "https://www.apple.com/newsroom/rss-feed.rss",
        // Science & Space (wave 2)
        "https://www.space.com/feeds/all",
        "https://rss.sciam.com/ScientificAmerican-Global",
        "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml",
        "https://flowingdata.com/feed",
        // Startups & Business (wave 2)
        "https://www.producthunt.com/feed",
        "https://feeds.feedburner.com/venturebeat/SZYF",
        "https://fortune.com/feed",
        "https://steveblank.com/feed/",
        // Design & Web Dev
        "https://www.smashingmagazine.com/feed",
        "https://alistapart.com/main/feed/",
        "https://css-tricks.com/feed/",
        // Fun / Misc (wave 2)
        "https://www.atlasobscura.com/feeds/latest",
        "https://hackaday.com/blog/feed/",
        "https://feeds.feedburner.com/oatmealfeed",
    ]

    private func populateDefaultFeeds() async {
        isRefreshing = true
        errorMessage = nil

        await withTaskGroup(of: (Feed, [FeedItem])?.self) { group in
            for urlString in Self.defaultFeedURLs {
                guard let url = URL(string: urlString) else { continue }
                let feedID = UUID()
                group.addTask {
                    try? await FeedParser.fetch(url: url, feedID: feedID)
                }
            }
            // Moltbook — API-based feed
            group.addTask {
                await MoltbookFetcher.fetch(feedID: UUID())
            }
            for await result in group {
                if let (feed, items) = result {
                    feeds.append(feed)
                    articles[feed.id] = items
                }
            }
        }

        // Sort feeds alphabetically
        feeds.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        save()
        isRefreshing = false
    }

    private func addMissingDefaultFeeds() async {
        let existingURLs = Set(feeds.map { $0.url.absoluteString })
        let missingURLs = Self.defaultFeedURLs.filter { !existingURLs.contains($0) }
        let needsMoltbook = !feeds.contains(where: { $0.url.host?.contains("moltbook.com") == true })

        guard !missingURLs.isEmpty || needsMoltbook else { return }

        await withTaskGroup(of: (Feed, [FeedItem])?.self) { group in
            for urlString in missingURLs {
                guard let url = URL(string: urlString) else { continue }
                let feedID = UUID()
                group.addTask {
                    try? await FeedParser.fetch(url: url, feedID: feedID)
                }
            }
            if needsMoltbook {
                group.addTask {
                    await MoltbookFetcher.fetch(feedID: UUID())
                }
            }
            for await result in group {
                if let (feed, items) = result {
                    feeds.append(feed)
                    articles[feed.id] = items
                }
            }
        }

        save()
    }

    // MARK: - Persistence

    private struct SaveData: Codable {
        var feeds: [Feed]
        var articles: [UUID: [FeedItem]]
        var readArticleIDs: Set<String>
        var feedSortMode: FeedSortMode?
        var articleSortMode: ArticleSortMode?
        var dateFilter: DateFilter?
        var flaggedArticles: [String: ArticleFlag]?
    }

    func save() {
        let data = SaveData(feeds: feeds, articles: articles, readArticleIDs: readArticleIDs,
                            feedSortMode: feedSortMode, articleSortMode: articleSortMode,
                            dateFilter: dateFilter, flaggedArticles: flaggedArticles)
        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: saveURL, options: .atomic)
        } catch {
            print("TerminalRSS save failed: \(error)")
        }
        rebuildCaches()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            let data = try Data(contentsOf: saveURL)
            let decoded = try JSONDecoder().decode(SaveData.self, from: data)
            feeds = decoded.feeds
            articles = decoded.articles
            readArticleIDs = decoded.readArticleIDs
            feedSortMode = decoded.feedSortMode ?? .name
            articleSortMode = decoded.articleSortMode ?? .date
            dateFilter = decoded.dateFilter ?? .all
            flaggedArticles = decoded.flaggedArticles ?? [:]
        } catch {
            print("TerminalRSS load failed: \(error)")
        }
        // Cap accumulated articles per feed
        for feedID in articles.keys {
            capArticles(for: feedID)
        }
        rebuildCaches()
    }

    // MARK: - Caching

    private func rebuildCaches() {
        // Rebuild feed lookup
        feedsByID = Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, $0) })

        // Rebuild article -> feed reverse lookup + article-by-ID lookup
        var feedLookup: [String: UUID] = [:]
        var idLookup: [String: FeedItem] = [:]
        for (feedID, items) in articles {
            for item in items {
                feedLookup[item.id] = feedID
                idLookup[item.id] = item
            }
        }
        articleFeedLookup = feedLookup
        articlesByID = idLookup

        // Invalidate expensive caches — recomputed lazily when accessed
        _cachedRankedArticles = nil
        _cachedTopicGroups = nil

        rebuildSelectedArticles()
    }

    private func rebuildSelectedArticles() {
        if case .flagged(let flag) = viewMode {
            cachedSelectedArticles = articlesFlagged(as: flag)
            return
        }
        if selectedFeedID == nil {
            cachedSelectedArticles = allArticles
            return
        }
        guard let feedID = selectedFeedID else {
            cachedSelectedArticles = []
            return
        }
        cachedSelectedArticles = sortArticles(filterByDate(articles[feedID] ?? []))
    }

    private func scheduleDebouncedSave() {
        pendingSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.save()
        }
        pendingSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func capArticles(for feedID: UUID) {
        guard let items = articles[feedID], items.count > maxArticlesPerFeed else { return }
        articles[feedID] = Array(
            items.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
                .prefix(maxArticlesPerFeed)
        )
    }

    // MARK: - Feed Management

    func addFeed(urlString: String) async {
        var normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
            normalized = "https://" + normalized
        }
        guard let url = URL(string: normalized) else {
            errorMessage = "Invalid URL"
            return
        }
        guard url.scheme == "http" || url.scheme == "https" else {
            errorMessage = "Only http and https URLs are supported"
            return
        }

        if feeds.contains(where: { $0.url == url }) {
            errorMessage = "Feed already subscribed"
            return
        }

        isRefreshing = true
        errorMessage = nil

        // Handle Moltbook URLs via API fetcher
        if url.host?.contains("moltbook.com") == true {
            let feedID = UUID()
            if let (feed, items) = await MoltbookFetcher.fetch(feedID: feedID) {
                feeds.append(feed)
                articles[feed.id] = items
                selectedFeedID = feed.id
                selectedArticleID = nil
                save()
            } else {
                errorMessage = "Failed to fetch Moltbook"
            }
            isRefreshing = false
            return
        }

        do {
            let feedID = UUID()
            let (feed, items) = try await FeedParser.fetch(url: url, feedID: feedID)
            feeds.append(feed)
            articles[feed.id] = items
            selectedFeedID = feed.id
            selectedArticleID = nil
            save()
        } catch {
            errorMessage = "Failed: \(error.localizedDescription)"
        }

        isRefreshing = false
    }

    func removeFeed(id: UUID) {
        feeds.removeAll { $0.id == id }
        articles.removeValue(forKey: id)
        if selectedFeedID == id {
            selectedFeedID = feeds.first?.id
            selectedArticleID = nil
        }
        save()
    }

    /// Refresh a single feed's data without persisting (used by refreshAll for batching).
    private func refreshFeedData(_ feed: Feed) async {
        // Moltbook uses its own API fetcher, not RSS
        if feed.url.host?.contains("moltbook.com") == true {
            if let (_, newItems) = await MoltbookFetcher.fetch(feedID: feed.id) {
                if let idx = feeds.firstIndex(where: { $0.id == feed.id }) {
                    feeds[idx].lastRefreshed = Date()
                }
                let existingByID = Dictionary(uniqueKeysWithValues:
                    (articles[feed.id] ?? []).map { ($0.id, $0) })
                var merged = existingByID
                for item in newItems { merged[item.id] = item }
                articles[feed.id] = Array(merged.values)
                capArticles(for: feed.id)
            }
            return
        }

        do {
            let (updated, newItems) = try await FeedParser.fetch(url: feed.url, feedID: feed.id)
            if let idx = feeds.firstIndex(where: { $0.id == feed.id }) {
                feeds[idx].title = updated.title
                feeds[idx].description = updated.description
                feeds[idx].lastRefreshed = Date()
            }
            // Merge: keep existing articles, add/update new ones (preserves offline cache)
            let existingByID = Dictionary(uniqueKeysWithValues:
                (articles[feed.id] ?? []).map { ($0.id, $0) })
            var merged = existingByID
            for item in newItems { merged[item.id] = item }
            articles[feed.id] = Array(merged.values)
            capArticles(for: feed.id)
        } catch {
            errorMessage = "Refresh failed: \(error.localizedDescription)"
        }
    }

    func refreshFeed(_ feed: Feed) async {
        await refreshFeedData(feed)
        save()
    }

    func refreshAll() async {
        isRefreshing = true
        errorMessage = nil
        await withTaskGroup(of: Void.self) { group in
            for feed in feeds {
                let feedCopy = feed
                group.addTask { await self.refreshFeedData(feedCopy) }
            }
        }
        save()
        isRefreshing = false
    }

    // MARK: - Read State

    func toggleRead(_ articleID: String) {
        if readArticleIDs.contains(articleID) {
            readArticleIDs.remove(articleID)
        } else {
            readArticleIDs.insert(articleID)
        }
        save()
    }

    func markRead(_ articleID: String) {
        if readArticleIDs.insert(articleID).inserted {
            scheduleDebouncedSave()
        }
    }

    func isRead(_ articleID: String) -> Bool {
        readArticleIDs.contains(articleID)
    }

    // MARK: - Flags

    func toggleFlag(_ articleID: String, flag: ArticleFlag) {
        if flaggedArticles[articleID] == flag {
            flaggedArticles.removeValue(forKey: articleID)
        } else {
            flaggedArticles[articleID] = flag
        }
        save()
    }

    func removeFlag(_ articleID: String) {
        flaggedArticles.removeValue(forKey: articleID)
        save()
    }

    func flag(for articleID: String) -> ArticleFlag? {
        flaggedArticles[articleID]
    }

    func flaggedCount(for flag: ArticleFlag) -> Int {
        flaggedArticles.values.filter { $0 == flag }.count
    }

    func articlesFlagged(as flag: ArticleFlag) -> [FeedItem] {
        let ids = flaggedArticles.filter { $0.value == flag }.map(\.key)
        let idSet = Set(ids)
        let items = articles.values.flatMap { $0 }.filter { idSet.contains($0.id) }
        return sortArticles(items)
    }

    // MARK: - Date Filtering

    func filterByDate(_ items: [FeedItem]) -> [FeedItem] {
        let range = dateFilter.dateRange
        guard range.start != nil || range.end != nil else { return items }
        return items.filter { item in
            guard let date = item.pubDate else { return false }
            if let start = range.start, date < start { return false }
            if let end = range.end, date > end { return false }
            return true
        }
    }

    // MARK: - Premium

    func togglePremium(_ feedID: UUID) {
        if let idx = feeds.firstIndex(where: { $0.id == feedID }) {
            feeds[idx].isPremium.toggle()
            save()
        }
    }

    // MARK: - Cluster Expansion

    func toggleClusterExpansion(_ clusterID: String) {
        if expandedClusterIDs.contains(clusterID) {
            expandedClusterIDs.remove(clusterID)
        } else {
            expandedClusterIDs.insert(clusterID)
        }
    }

    var isRankedMode: Bool { viewMode == .ranked }
    var isTopicsMode: Bool { viewMode == .topics }

    // MARK: - Computed

    func unreadCount(for feedID: UUID) -> Int {
        filterByDate(articles[feedID] ?? []).filter { !readArticleIDs.contains($0.id) }.count
    }

    var totalUnreadCount: Int {
        feeds.reduce(0) { $0 + unreadCount(for: $1.id) }
    }

    var sortedFeeds: [Feed] {
        switch feedSortMode {
        case .name:
            return feeds.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .unreadCount:
            return feeds.sorted { unreadCount(for: $0.id) > unreadCount(for: $1.id) }
        case .dateAdded:
            return feeds.sorted { $0.dateAdded > $1.dateAdded }
        }
    }

    var allArticles: [FeedItem] {
        let all = articles.values.flatMap { $0 }
        return sortArticles(filterByDate(all))
    }

    private func sortArticles(_ items: [FeedItem]) -> [FeedItem] {
        switch articleSortMode {
        case .date:
            return items.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        case .title:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .readStatus:
            return items.sorted { a, b in
                let aRead = isRead(a.id)
                let bRead = isRead(b.id)
                if aRead != bRead { return !aRead } // unread first
                return (a.pubDate ?? .distantPast) > (b.pubDate ?? .distantPast)
            }
        }
    }

    var selectedArticles: [FeedItem] { cachedSelectedArticles }

    var rankedArticles: [ArticleCluster] {
        if let cached = _cachedRankedArticles { return cached }
        let allFiltered = filterByDate(articles.values.flatMap { $0 })
        let result = ArticleRanker.rank(articles: allFiltered, feeds: feeds, readIDs: readArticleIDs)
        _cachedRankedArticles = result
        return result
    }

    var topicGroups: [TopicGroup] {
        if let cached = _cachedTopicGroups { return cached }
        let allFiltered = filterByDate(articles.values.flatMap { $0 })
        let result = TopicClassifier.group(articles: allFiltered, feeds: feeds, readIDs: readArticleIDs)
        _cachedTopicGroups = result
        return result
    }

    func toggleTopicExpansion(_ topicID: String) {
        if expandedTopicIDs.contains(topicID) {
            expandedTopicIDs.remove(topicID)
        } else {
            expandedTopicIDs.insert(topicID)
        }
    }

    /// Flat list of clusters in topic order (for keyboard navigation)
    var topicFlatClusters: [ArticleCluster] {
        topicGroups.flatMap(\.clusters)
    }

    var selectedArticle: FeedItem? {
        guard let id = selectedArticleID else { return nil }
        return articlesByID[id]
    }

    var selectedFeed: Feed? {
        guard let id = selectedFeedID else { return nil }
        return feedsByID[id]
    }

    func feedName(for articleID: String) -> String? {
        guard let feedID = articleFeedLookup[articleID] else { return nil }
        return feedsByID[feedID]?.title
    }

    // MARK: - Sort Cycling

    func cycleFeedSort() {
        let modes = FeedSortMode.allCases
        let idx = modes.firstIndex(of: feedSortMode) ?? 0
        feedSortMode = modes[(idx + 1) % modes.count]
        save()
    }

    func cycleArticleSort() {
        let modes = ArticleSortMode.allCases
        let idx = modes.firstIndex(of: articleSortMode) ?? 0
        articleSortMode = modes[(idx + 1) % modes.count]
        save()
    }
}
