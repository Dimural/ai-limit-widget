import LimitKit
import SwiftUI
import WidgetKit

/// The desktop widgets.
///
/// Three static kinds rather than one configurable widget: a configurable
/// widget needs AppIntents metadata that only Xcode's build pipeline
/// generates, and this project builds with SwiftPM so the configuration UI
/// would silently fail to appear. Separate entries in the widget gallery give
/// the same choice with nothing that can quietly break.
@main
struct AILimitsWidgetBundle: WidgetBundle {
    var body: some Widget {
        OverviewWidget()
        ProviderWidget(provider: .claude)
        ProviderWidget(provider: .codex)
    }
}

/// Everything at once. Small shows whichever window is closest to running out,
/// which is the one about to stop you working.
struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ai-limits-overview", provider: SnapshotTimelineProvider()) { entry in
            OverviewView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("AI Limits")
        .description("Usage windows for every connected AI CLI.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// A single provider, for people who only care about one.
struct ProviderWidget: Widget {
    let provider: ProviderID

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "ai-limits-\(provider.rawValue)",
            provider: SnapshotTimelineProvider()
        ) { entry in
            SingleProviderView(
                provider: entry.snapshot?.provider(provider),
                name: provider.displayName
            )
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(provider.displayName)
        .description("Usage windows for \(provider.displayName).")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Views

struct OverviewView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: Snapshot?

    var body: some View {
        if let snapshot, !snapshot.providers.isEmpty {
            switch family {
            case .systemSmall: BusiestView(snapshot: snapshot)
            default: AllProvidersView(snapshot: snapshot)
            }
        } else {
            EmptyState()
        }
    }
}

/// Small size: the single window closest to running out, in full.
struct BusiestView: View {
    let snapshot: Snapshot

    private var busiest: (provider: ProviderSnapshot, window: LimitWindow)? {
        snapshot.providers
            .compactMap { provider in
                provider.tightestWindow.map { (provider, $0) }
            }
            .max { $0.1.usedPercent < $1.1.usedPercent }
    }

    var body: some View {
        if let busiest {
            VStack(alignment: .leading, spacing: 0) {
                Text(busiest.provider.provider.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("\(Int(busiest.window.usedPercent.rounded()))%")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(
                        WidgetPalette.color(
                            for: Presentation.severity(forUsedPercent: busiest.window.usedPercent)
                        )
                    )
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text(busiest.window.label)
                    .font(.caption2.weight(.medium))

                Spacer(minLength: 6)

                UsageBar(
                    percent: busiest.window.usedPercent,
                    color: WidgetPalette.color(
                        for: Presentation.severity(forUsedPercent: busiest.window.usedPercent)
                    )
                )

                if let resetsAt = busiest.window.resetsAt {
                    ResetCountdown(resetsAt: resetsAt).padding(.top, 3)
                }
            }
            .opacity(busiest.provider.isStale(threshold: Presentation.stalenessThreshold) ? 0.55 : 1)
        } else {
            EmptyState()
        }
    }
}

/// Medium size: every provider side by side.
struct AllProvidersView: View {
    let snapshot: Snapshot

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(snapshot.providers, id: \.provider) { provider in
                ProviderCard(provider: provider)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct SingleProviderView: View {
    @Environment(\.widgetFamily) private var family
    let provider: ProviderSnapshot?
    let name: String

    var body: some View {
        if let provider {
            ProviderCard(provider: provider, windowLimit: family == .systemSmall ? 2 : .max)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.caption.weight(.semibold))
                Text("Not connected yet.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
