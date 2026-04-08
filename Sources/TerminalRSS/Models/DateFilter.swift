import Foundation

enum DateFilter: Equatable {
    case today
    case last24h
    case last3d
    case last7d
    case last30d
    case all
    case custom(start: Date, end: Date)

    // MARK: - Date Range

    var dateRange: (start: Date?, end: Date?) {
        let now = Date()
        switch self {
        case .today:
            return (Calendar.current.startOfDay(for: now), now)
        case .last24h:
            return (now.addingTimeInterval(-24 * 3600), now)
        case .last3d:
            return (now.addingTimeInterval(-3 * 24 * 3600), now)
        case .last7d:
            return (now.addingTimeInterval(-7 * 24 * 3600), now)
        case .last30d:
            return (now.addingTimeInterval(-30 * 24 * 3600), now)
        case .all:
            return (nil, nil)
        case .custom(let start, let end):
            return (start, end)
        }
    }

    // MARK: - Yahoo Finance Range

    var yahooFinanceRange: String {
        switch self {
        case .today, .last24h:
            return "1d"
        case .last3d, .last7d:
            return "5d"
        case .last30d:
            return "1mo"
        case .all:
            return "3mo"
        case .custom(let start, let end):
            let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
            if days <= 1 { return "1d" }
            if days <= 7 { return "5d" }
            if days <= 30 { return "1mo" }
            return "3mo"
        }
    }

    // MARK: - Label

    var label: String {
        switch self {
        case .today: return "TODAY"
        case .last24h: return "24H"
        case .last3d: return "3D"
        case .last7d: return "7D"
        case .last30d: return "30D"
        case .all: return "ALL"
        case .custom: return "CUSTOM"
        }
    }
}

// MARK: - Codable

extension DateFilter: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case start
        case end
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .today:
            try container.encode("today", forKey: .type)
        case .last24h:
            try container.encode("last24h", forKey: .type)
        case .last3d:
            try container.encode("last3d", forKey: .type)
        case .last7d:
            try container.encode("last7d", forKey: .type)
        case .last30d:
            try container.encode("last30d", forKey: .type)
        case .all:
            try container.encode("all", forKey: .type)
        case .custom(let start, let end):
            try container.encode("custom", forKey: .type)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "today": self = .today
        case "last24h": self = .last24h
        case "last3d": self = .last3d
        case "last7d": self = .last7d
        case "last30d": self = .last30d
        case "all": self = .all
        case "custom":
            let start = try container.decode(Date.self, forKey: .start)
            let end = try container.decode(Date.self, forKey: .end)
            self = .custom(start: start, end: end)
        default:
            self = .all
        }
    }
}
