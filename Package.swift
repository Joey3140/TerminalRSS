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
        ),
        // `tests/` (lowercase) because the harness already made that folder and
        // the Mac's file system ignores case.
        .testTarget(
            name: "TerminalRSSTests",
            dependencies: ["TerminalRSS"],
            path: "tests/TerminalRSSTests"
        ),
    ]
)
