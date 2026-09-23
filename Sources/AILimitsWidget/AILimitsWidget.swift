import LimitKit
import LimitUI
import SwiftUI
import WidgetKit

/// The desktop widgets.
///
/// Three static kinds rather than one configurable widget: a configurable
/// widget needs AppIntents metadata that only Xcode's build pipeline
/// generates, and this project builds with SwiftPM, so its configuration UI
/// would silently fail to appear. Separate entries in the widget gallery give
/// the same choice with nothing that can quietly break.
@main
struct AILimitsWidgetBundle: WidgetBundle {
    var body: some Widget {
        OverviewWidget()
        ClaudeCodeWidget()
        CodexWidget()
    }
}

/// Everything at once. Small shows whichever window is closest to running
/// out, since that is the one about to stop the work.
struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ai-limits-overview", provider: SnapshotTimelineProvider()) { entry in
            OverviewView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName(Text("AI Limits"))
        .description(Text("Usage windows for every connected AI CLI."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// A single provider, for people who only care about one.
//
// Two concrete types rather than one parameterised by provider: `Widget`
// requires `init()`, so a widget cannot carry a stored property. The shared
// builder below keeps that from turning into duplicated configuration.

struct ClaudeCodeWidget: Widget {
    var body: some WidgetConfiguration { providerConfiguration(for: .claude) }
}

struct CodexWidget: Widget {
    var body: some WidgetConfiguration { providerConfiguration(for: .codex) }
}

// Deliberately not @MainActor: `Widget.body` is main-actor isolated on newer
// SDKs and nonisolated on macOS 14's, and a nonisolated function can be called
// from either.
private func providerConfiguration(for provider: ProviderID) -> some WidgetConfiguration {
    StaticConfiguration(
        kind: "ai-limits-\(provider.rawValue)",
        provider: SnapshotTimelineProvider()
    ) { entry in
        SingleProviderView(
            allowances: entry.snapshot?.allowances(of: provider) ?? [],
            name: provider.displayName
        )
        .containerBackground(for: .widget) { WidgetBackground() }
    }
    .configurationDisplayName(Text(provider.displayName))
    .description(Text("Usage windows for \(provider.displayName)."))
    .supportedFamilies([.systemSmall, .systemMedium])
}
