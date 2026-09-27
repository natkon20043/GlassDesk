// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GlassDesk",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "GlassDesk",
            path: "Sources/GlassDesk",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
