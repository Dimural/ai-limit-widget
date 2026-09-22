import LimitKit
import SwiftUI
import WidgetKit

/// Shared look for every widget size.
///
/// Two rules run through all of it. Numbers are never shown as more current
/// than they are — stale data is dimmed and dated rather than presented as
/// live. And severity is never carried by colour alone: the percentage and the
/// bar say the same thing, so the widget reads correctly in monochrome and to
/// anyone who does not distinguish the hues.
enum WidgetPalette {
    static func color(for severity: Presentation.Severity) -> Color {
        switch severity {
        case .comfortable: return .green
        case .warning: return .yellow
        case .critical: return .orange
        case .exhausted: return .red
        }
    }
}

/// A window's usage as a labelled bar: `5-hour ███████░░░ 68%`.
struct WindowRow: View {
    let window: LimitWindow
    var showsCountdown = true

    private var severity: Presentation.Severity {
        Presentation.severity(forUsedPercent: window.usedPercent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(window.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            }

            UsageBar(percent: window.usedPercent, color: WidgetPalette.color(for: severity))

            if showsCountdown, let resetsAt = window.resetsAt {
                ResetCountdown(resetsAt: resetsAt)
            }
        }
    }
}

struct UsageBar: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: max(geometry.size.width * percent / 100, percent > 0 ? 3 : 0))
            }
        }
        .frame(height: 5)
    }
}

/// A live countdown that ticks every second without costing a timeline reload:
/// WidgetKit renders this text itself once the entry is on screen.
struct ResetCountdown: View {
    let resetsAt: Date

    var body: some View {
        Group {
            if resetsAt > Date() {
                Text(timerInterval: Date()...resetsAt, countsDown: true)
            } else {
                Text("resetting")
            }
        }
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.tertiary)
    }
}

/// One provider: its name, plan, and every window it reports.
struct ProviderCard: View {
    let provider: ProviderSnapshot
    var windowLimit = Int.max

    private var isStale: Bool {
        provider.isStale(threshold: Presentation.stalenessThreshold)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(provider.provider.displayName)
                    .font(.caption.weight(.semibold))
                if let plan = provider.planLabel {
                    Text(plan)
                        .font(.system(size: 8, weight: .medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            ForEach(Array(provider.windows.prefix(windowLimit).enumerated()), id: \.offset) { _, window in
                WindowRow(window: window)
            }

            if isStale {
                Text("as of \(provider.sourceUpdatedAt, format: .dateTime.hour().minute())")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
        }
        // Dimming is the honest signal that these numbers are not live.
        .opacity(isStale ? 0.55 : 1)
    }
}

/// Shown before any provider has reported, so an empty widget explains itself
/// instead of looking broken.
struct EmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI Limits")
                .font(.caption.weight(.semibold))
            Text("No usage data yet. Open the menu bar app to connect Claude Code, or run Codex.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
