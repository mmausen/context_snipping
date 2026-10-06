// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "snip",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "snip",
            path: "Sources/snip",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
