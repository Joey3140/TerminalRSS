import SwiftUI

struct DateFilterBar: View {
    @EnvironmentObject var store: FeedStore

    private let presets: [(DateFilter, String)] = [
        (.today, "TODAY"),
        (.last24h, "24H"),
        (.last3d, "3D"),
        (.last7d, "7D"),
        (.last30d, "30D"),
        (.all, "ALL"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            Text("FILTER:")
                .font(TerminalTheme.smallFont)
                .foregroundStyle(TerminalTheme.dimText)
                .padding(.trailing, 8)

            ForEach(Array(presets.enumerated()), id: \.offset) { idx, preset in
                if idx > 0 { sep }
                filterButton(preset.0, label: preset.1)
            }

            Spacer()

            if store.dateFilter != .all {
                Text("SHOWING \(store.selectedArticles.count) ARTICLES")
                    .font(TerminalTheme.smallFont)
                    .foregroundStyle(TerminalTheme.dimText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(TerminalTheme.statusBarBackground.opacity(0.7))
    }

    private func filterButton(_ filter: DateFilter, label: String) -> some View {
        let isActive = store.dateFilter == filter

        return Button {
            store.dateFilter = filter
            store.save()
        } label: {
            Text(label)
                .font(TerminalTheme.smallFont)
                .foregroundStyle(isActive ? TerminalTheme.accentOrange : TerminalTheme.dimText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isActive ? TerminalTheme.selectionBackground : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var sep: some View {
        Rectangle().fill(TerminalTheme.accentOrange.opacity(0.3)).frame(width: 1, height: 12)
    }
}
