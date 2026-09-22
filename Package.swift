// swift-tools-version: 5.9
import PackageDescription

// AI Limits is built with SwiftPM plus a Makefile that assembles the .app and
// .appex bundles. There is deliberately no .xcodeproj: generated project files
// are unreadable and unmergeable, which makes them hostile to both humans and
// AI agents. See AGENTS.md.
let package = Package(
    name: "AILimits",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LimitKit", targets: ["LimitKit"]),
        .executable(name: "ai-limits-statusline", targets: ["StatusLineShim"]),
        .executable(name: "AILimits", targets: ["AILimitsApp"]),
        .executable(name: "AILimitsWidget", targets: ["AILimitsWidget"]),
    ],
    targets: [
        // Pure data layer: reads provider files, produces a Snapshot.
        // No AppKit, no WidgetKit, no networking. Fully unit tested.
        .target(name: "LimitKit"),

        // Tiny binary wired into Claude Code's status line.
        .executableTarget(name: "StatusLineShim", dependencies: ["LimitKit"]),

        // Menu bar app: collector, settings, widget bridge.
        .executableTarget(name: "AILimitsApp", dependencies: ["LimitKit"]),

        // WidgetKit extension: renders the snapshot pushed into its container.
        .executableTarget(name: "AILimitsWidget", dependencies: ["LimitKit"]),

        .testTarget(
            name: "LimitKitTests",
            dependencies: ["LimitKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
