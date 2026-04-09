import Foundation

struct TopicGroup: Identifiable {
    let id: String           // topic raw value
    let topic: String        // display name
    let articles: [FeedItem] // sorted by date descending
    let articleCount: Int
}

struct TopicClassifier {
    enum Topic: String, CaseIterable {
        case ai = "AI & ML"
        case apple = "APPLE"
        case automotive = "AUTOMOTIVE"
        case business = "BUSINESS & FINANCE"
        case crime = "CRIME & JUSTICE"
        case crypto = "CRYPTO"
        case culture = "CULTURE & MEDIA"
        case dev = "DEV & CODE"
        case education = "EDUCATION"
        case energy = "ENERGY & CLIMATE"
        case gaming = "GAMING"
        case hardware = "HARDWARE & CHIPS"
        case health = "HEALTH"
        case legal = "LEGAL & PRIVACY"
        case military = "MILITARY & DEFENSE"
        case politics = "POLITICS"
        case science = "SCIENCE & SPACE"
        case security = "CYBERSECURITY"
        case social = "SOCIAL MEDIA"
        case sports = "SPORTS"
        case technology = "TECHNOLOGY"
        case telecom = "TELECOM & WIRELESS"
        case world = "WORLD NEWS"
        case deals = "DEALS & PROMOS"
        case other = "OTHER"
    }

    private static let topicKeywords: [(Topic, [String])] = [
        // Specific topics first to avoid misclassification
        (.ai, [
            "ai ", "artificial intelligence", "machine learning", "deep learning",
            "neural network", "llm", "large language model", "chatgpt", "openai",
            "claude", "anthropic", "gemini", "gpt-", "gpt4", "gpt5",
            "transformer", "diffusion model", "generative ai", "gen ai",
            "copilot", "midjourney", "stable diffusion", "dall-e",
            "mythos", "sonnet", "opus model", "haiku model",
            " ai,", " ai.", "ai-powered", "ai model", "ai agent",
            "training data", "inference", "fine-tun", "benchmark",
            "hallucination", "alignment", "rlhf", "prompt",
        ]),
        (.deals, [
            "promo code", "coupon", "discount code", "% off",
            "best deals", "deal of", "sale:", "on sale",
            "affiliate", "sponsored", "buy now", "limited time",
            "save $", "price drop", "clearance",
        ]),
        (.crypto, [
            "bitcoin", "ethereum", "crypto", "blockchain", "web3",
            "defi", "nft", "solana", "dogecoin", "binance",
            "stablecoin", "btc ", "eth ", "token",
            "mining", "wallet", "ledger", "coinbase",
        ]),
        (.apple, [
            "apple", "iphone", "ipad", "macbook", "macos", "ios ",
            "watchos", "visionos", "airpods", "apple watch", "app store",
            "swift ", "swiftui", "xcode", "wwdc", "apple silicon",
            "m4 ", "m3 ", "m2 ", "vision pro", "siri",
            "imac", "mac pro", "mac mini", "macos ",
            "carplay", "airdrop", "icloud",
        ]),
        (.security, [
            "security", "vulnerability", "exploit", "malware", "ransomware",
            "hack", "breach", "phishing", "zero-day", "0-day", "cve-",
            "cybersecurity", "cyber attack", "data leak", "encryption",
            "backdoor", "trojan", "botnet", "ddos", "firewall",
            "infosec", "threat actor", "apt ", "password",
            "spyware", "patch tuesday", "authentication",
        ]),
        (.legal, [
            "privacy", "gdpr", "lawsuit", "antitrust", "regulation",
            "compliance", "subpoena", "court ruling", "patent",
            "copyright", "dmca", "surveillance", "data protection",
            "fined", "penalty", "settlement", "terms of service",
            "right to repair", "section 230",
        ]),
        (.military, [
            "military", "defense", "pentagon", "missile", "drone strike",
            "troops", "naval", "army", "air force", "weapon",
            "nuclear", "warhead", "submarine", "fighter jet",
            "invasion", "warfare", "casualties",
        ]),
        (.crime, [
            "arrested", "murder", "shooting", "robbery", "fraud",
            "indicted", "sentenced", "prison", "fbi ", "police",
            "investigation", "suspect", "crime", "criminal",
            "trafficking", "smuggling", "assault", "theft",
            "ice agents", "manhunt",
        ]),
        (.politics, [
            "trump", "biden", "congress", "senate", "democrat", "republican",
            "election", "vote", "ballot", "political", "politics",
            "president", "white house", "supreme court", "legislation",
            "tariff", "trade war", "immigration", "border",
            "liberal", "conservative", "parliament", "prime minister",
            "diplomat", "treaty", "governor", "mayor",
            "campaign", "poll", "swing state", "executive order",
            "cabinet", "bipartisan", "filibuster",
        ]),
        (.world, [
            "ceasefire", "iran", "ukraine", "russia", "nato", "sanctions",
            "united nations", "un ", "refugee", "humanitarian",
            "middle east", "gaza", "israel", "china", "taiwan",
            "north korea", "syria", "yemen", "africa",
            "eu ", "european union", "brexit",
            "earthquake", "tsunami", "hurricane", "flood",
            "diplomatic", "ambassador", "embassy", "foreign minister",
            "peace talks", "strait", "territorial",
        ]),
        (.science, [
            "nasa", "spacex", "artemis", "rocket", "satellite", "orbit",
            "mars", "moon", "asteroid", "telescope", "cosmic",
            "physics", "quantum", "cern", "particle",
            "biodiversity", "genome", "dna", "rna",
            "neuroscience", "evolution", "fossil", "species",
            "space station", "launch", "spacecraft",
            "research", "study finds", "scientists",
            "experiment", "discovery", "observatory",
        ]),
        (.energy, [
            "climate", "carbon", "emission", "renewable", "solar",
            "wind energy", "nuclear power", "fossil fuel", "oil ",
            "natural gas", "pipeline", "opec", "petroleum",
            "ev charging", "grid", "sustainability",
            "global warming", "greenhouse", "paris agreement",
            "clean energy", "hydrogen",
        ]),
        (.automotive, [
            "tesla", "electric vehicle", "ev ", "self-driving",
            "autonomous vehicle", "car ", "truck", "suv",
            "toyota", "ford ", "gm ", "volkswagen", "bmw",
            "rivian", "lucid", "hybrid", "recall",
            "lidar", "autopilot", "driving",
        ]),
        (.hardware, [
            "chip", "semiconductor", "processor", "intel", "amd",
            "nvidia", "qualcomm", "tsmc", "arm ",
            "gpu", "cpu", "memory", "ddr", "ssd",
            "fabrication", "nanometer", "transistor",
            "motherboard", "overclocking",
        ]),
        (.social, [
            "twitter", "x.com", "facebook", "instagram", "tiktok",
            "snapchat", "threads", "bluesky", "mastodon", "fediverse",
            "social media", "influencer", "viral", "followers",
            "content moderation", "misinformation", "disinformation",
            "elon musk", "mark zuckerberg",
        ]),
        (.telecom, [
            "5g", "6g", "broadband", "fiber", "wireless",
            "spectrum", "telecom", "carrier", "at&t", "verizon",
            "t-mobile", "starlink", "satellite internet",
            "wi-fi", "wifi", "bluetooth",
        ]),
        (.sports, [
            "sport", "football", "basketball", "soccer", "baseball",
            "tennis", "golf", "nfl", "nba", "mlb", "nhl",
            "olympic", "championship", "tournament", "playoff",
            "coach", "team", "league", "stadium", "athlete",
            "premier league", "world cup", "medal",
            "arsenal", "keeper", "goalkeeper",
        ]),
        (.education, [
            "university", "college", "student", "school",
            "professor", "academic", "campus", "tuition",
            "scholarship", "curriculum", "enrollment",
        ]),
        (.health, [
            "health", "medical", "disease", "vaccine", "hospital",
            "fda", "drug", "clinical trial", "cancer", "covid",
            "pandemic", "treatment", "therapy", "diagnosis",
            "mental health", "depression", "obesity", "diabetes",
            "surgery", "pharmaceutical", "doctor",
        ]),
        (.business, [
            "stock", "market", "revenue", "profit", "earning",
            "ipo", "merger", "acquisition", "startup", "funding",
            "venture capital", "valuation", "investor", "wall street",
            "fed ", "federal reserve", "interest rate", "inflation",
            "gdp", "recession", "economy", "economic",
            "ceo", "layoff", "restructur", "quarterly",
            "billion", "million deal", "raise", "series ",
        ]),
        (.dev, [
            "rust ", "golang", "python", "javascript", "typescript",
            "react", "node.js", "kubernetes", "docker", "linux",
            "open source", "github", "git ", "api ",
            "programming", "developer", "software engineer",
            "framework", "library", "compiler", "debug",
            "code review", "pull request", "ci/cd",
            "database", "sql", "postgres", "redis",
            "web assembly", "wasm", "http", "tcp",
            "kernel", "syscall", "performance",
        ]),
        (.technology, [
            "tech", "gadget", "smartphone", "app ", "software",
            "google", "microsoft", "amazon", "meta ",
            "robot", "autonomous", "electric vehicle",
            "display", "oled", "usb", "device",
            "startup", "platform", "feature", "update",
        ]),
        (.gaming, [
            "game", "gaming", "playstation", "xbox", "nintendo",
            "steam", "esport", "fortnite", "minecraft",
            "console", "graphics card", "rtx",
            "rpg", "mmorpg", "indie game",
        ]),
        (.culture, [
            "movie", "film", "netflix", "streaming", "music",
            "album", "concert", "festival", "book", "novel",
            "art", "museum", "tv show", "series", "award",
            "oscar", "grammy", "emmy", "celebrity",
            "disney", "hbo", "podcast", "youtube",
            "fashion", "design", "architecture",
        ]),
    ]

    // Feed-source hints — if title doesn't match anything, use the source feed
    private static let feedTopicHints: [String: Topic] = [
        "ars technica": .technology,
        "hacker news": .dev,
        "daring fireball": .apple,
        "the verge": .technology,
        "techcrunch": .business,
        "lobste.rs": .dev,
        "lobsters": .dev,
        "wired": .technology,
        "9to5mac": .apple,
        "macrumors": .apple,
        "bbc": .world,
        "nytimes": .world,
        "nyt": .world,
        "npr": .world,
        "guardian": .world,
        "reuters": .world,
        "nasa": .science,
        "krebs": .security,
        "dev.to": .dev,
        "dev community": .dev,
        "rust": .dev,
        "moltbook": .ai,
    ]

    static func classify(_ title: String, feedName: String? = nil) -> Topic {
        let lower = title.lowercased()
        var bestTopic: Topic = .other
        var bestScore = 0

        for (topic, keywords) in topicKeywords {
            var score = 0
            for keyword in keywords {
                if lower.contains(keyword) {
                    score += 1
                }
            }
            if score > bestScore {
                bestScore = score
                bestTopic = topic
            }
        }

        // If no keyword matched, try feed source hint
        if bestTopic == .other, let feedName = feedName {
            let lowerFeed = feedName.lowercased()
            for (hint, topic) in feedTopicHints {
                if lowerFeed.contains(hint) {
                    return topic
                }
            }
        }

        return bestTopic
    }

    static func group(articles: [FeedItem], feeds: [Feed]) -> [TopicGroup] {
        let feedMap = Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, $0) })

        var topicMap: [Topic: [FeedItem]] = [:]
        for article in articles {
            let feedName = feedMap[article.feedID]?.title
            let topic = classify(article.title, feedName: feedName)
            topicMap[topic, default: []].append(article)
        }

        return topicMap.map { topic, items in
            let sorted = items.sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            return TopicGroup(
                id: topic.rawValue,
                topic: topic.rawValue,
                articles: sorted,
                articleCount: sorted.count
            )
        }
        .sorted { $0.articleCount > $1.articleCount }
    }
}
