import SwiftUI

enum TerminalTheme {
    // Bloomberg-inspired palette
    static let background = Color(red: 0, green: 0, blue: 0)
    static let panelBackground = Color(red: 0.06, green: 0.06, blue: 0.09)
    static let panelBorder = Color(red: 0.20, green: 0.20, blue: 0.25)

    // Status bars — Bloomberg signature dark blue
    static let statusBarBackground = Color(red: 0.0, green: 0.10, blue: 0.33)
    static let statusBarText = Color(red: 1.0, green: 0.55, blue: 0.0)

    // Text
    static let primaryText = Color(red: 0.78, green: 0.78, blue: 0.78)
    static let brightText = Color.white
    static let dimText = Color(red: 0.40, green: 0.40, blue: 0.42)

    // Accents
    static let accentGreen = Color(red: 0, green: 1.0, blue: 0.25)
    static let accentOrange = Color(red: 1.0, green: 0.55, blue: 0.0)
    static let accentAmber = Color(red: 0.96, green: 0.65, blue: 0.14)
    static let accentBlue = Color(red: 0.33, green: 0.60, blue: 1.0)
    static let accentRed = Color(red: 1.0, green: 0.25, blue: 0.25)

    // Selection
    static let selectionBackground = Color(red: 0.0, green: 0.12, blue: 0.36)

    // Code blocks
    static let codeBackground = Color(red: 0.08, green: 0.08, blue: 0.12)

    // Market colors — colored backgrounds for change values
    static let positiveBackground = Color(red: 0, green: 0.25, blue: 0.05)
    static let negativeBackground = Color(red: 0.30, green: 0.05, blue: 0.05)

    // Fonts — SF Mono everywhere
    static let bodyFont = Font.system(size: 13, design: .monospaced)
    static let smallFont = Font.system(size: 11, design: .monospaced)
    static let headerFont = Font.system(size: 13, weight: .bold, design: .monospaced)
    static let titleFont = Font.system(size: 15, weight: .bold, design: .monospaced)
    static let largeTitleFont = Font.system(size: 18, weight: .bold, design: .monospaced)
}
