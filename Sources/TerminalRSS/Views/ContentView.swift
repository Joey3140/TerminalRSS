import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            Text("Feeds")
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1)))
        } detail: {
            Text("TerminalRSS")
                .font(.system(.largeTitle, design: .monospaced))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.14, alpha: 1)))
        }
    }
}
