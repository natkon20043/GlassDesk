// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GlassDesk",
    platforms: [.macOS(.v26)],
    targets: [
        // Screen geometry (top bar placement, widget scaling and positions) in plain C++.
        .target(
            name: "CGlassLayout",
            path: "Sources/CGlassLayout"
        ),
        .executableTarget(
            name: "GlassLayoutTests",
            dependencies: ["CGlassLayout"],
            path: "Sources/GlassLayoutTests"
        ),
        .executableTarget(
            name: "GlassDesk",
            dependencies: ["CGlassLayout"],
            path: "Sources/GlassDesk",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ],
    cxxLanguageStandard: .cxx20
)
