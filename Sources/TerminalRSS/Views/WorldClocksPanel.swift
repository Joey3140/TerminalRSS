import SwiftUI
import Combine

struct WorldClocksPanel: View {
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let clocks: [(city: String, tzID: String)] = [
        ("New York", "America/New_York"),
        ("London", "Europe/London"),
        ("Hong Kong", "Asia/Hong_Kong"),
        ("Tokyo", "Asia/Tokyo"),
        ("Local", TimeZone.current.identifier),
    ]

    private static func formatter(for tzID: String) -> DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        df.timeZone = TimeZone(identifier: tzID)
        return df
    }

    private static let formatters: [(city: String, tzID: String, formatter: DateFormatter)] = {
        clocks.map { clock in
            (city: clock.city, tzID: clock.tzID, formatter: WorldClocksPanel.formatter(for: clock.tzID))
        }
    }()

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.formatters.enumerated()), id: \.offset) { _, clock in
                VStack(spacing: 1) {
                    Text(clock.formatter.string(from: now))
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(TerminalTheme.brightText)

                    Text(clock.city)
                        .font(TerminalTheme.smallFont)
                        .foregroundStyle(TerminalTheme.accentOrange)

                    Text(abbreviation(for: clock.tzID))
                        .font(TerminalTheme.smallFont)
                        .foregroundStyle(TerminalTheme.dimText)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onReceive(timer) { newTime in
            now = newTime
        }
    }

    private func abbreviation(for tzID: String) -> String {
        TimeZone(identifier: tzID)?.abbreviation(for: now) ?? ""
    }
}
