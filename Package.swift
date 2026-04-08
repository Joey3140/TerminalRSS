// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TerminalRSS",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "TerminalRSS",
            path: "Sources/TerminalRSS"
        )
    ]
)
