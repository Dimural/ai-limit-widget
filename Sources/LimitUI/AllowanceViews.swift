import LimitKit
import SwiftUI
import WidgetKit

/// The pieces every widget size is built from.
///
/// Two rules run through all of it.
///
/// A reading is never dimmed to signal that it is not current. Fading a card
/// out makes it look broken, and these readings are not broken — they are
/// from a known moment, so the card says which moment in words and keeps its
/// contrast.
///
/// Severity is never carried by colour alone. The number, the bar's length
/// and its position against the warning notch all say the same thing, so the
/// widget reads correctly in monochrome and to anyone who does not separate
/// the hues.

extension Color {
    /// Built from the same numbers the menu bar uses, so the two can never
    /// disagree about what "nearly out" looks like.
    init(_ ink: Presentation.Ink, dark: Bool) {
        let resolved = dark ? ink.lifted : ink
        self.init(.sRGB, red: resolved.red, green: resolved.green, blue: resolved.blue)
    }
}

/// A usage bar with a notch where the reading turns critical.
///
/// The notch is what makes it an instrument rather than a strip that changes
/// colour: you can see how close the allowance is to trouble without reading
/// the number at all.
public struct UsageBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let percent: Double
    var height: CGFloat = 7

    private var fill: Color {
        Color(
            Presentation.ink(for: Presentation.severity(forUsedPercent: percent)),
            dark: colorScheme == .dark
        )
    }

    public init(percent: Double, height: CGFloat = 7) {
        self.percent = percent
        self.height = height
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.13))

                Capsule()
                    .fill(fill)
                    // Never narrower than it is tall, so a 1% reading still
                    // marks the gauge instead of vanishing.
                    .frame(width: max(geometry.size.width * percent / 100, percent > 0 ? height : 0))

                // From the label colour, not the background: a notch tinted
                // like the card vanishes into the track in dark mode.
                Rectangle()
                    .fill(.primary.opacity(0.45))
                    .frame(width: 1.5)
                    .offset(x: geometry.size.width * Presentation.criticalThreshold / 100)
            }
        }
        .frame(height: height)
    }
}

/// A live countdown that ticks every second without spending a timeline
/// reload — WidgetKit renders this text itself once the entry is on screen.
public struct ResetCountdown: View {
    let resetsAt: Date
    var size: CGFloat = 11

    public init(resetsAt: Date, size: CGFloat = 11) {
        self.resetsAt = resetsAt
        self.size = size
    }

    public var body: some View {
        Group {
            if resetsAt > Date() {
                Text(timerInterval: Date()...resetsAt, countsDown: true)
            } else {
                Text("resetting")
            }
        }
        .font(.system(size: size, weight: .regular))
        .monospacedDigit()
        .foregroundStyle(.tertiary)
    }
}

/// One window on one line: what it is, how much is gone, when it returns.
public struct WindowRow: View {
    let window: LimitWindow

    public init(window: LimitWindow) { self.window = window }

    public var body: some View {
        HStack(spacing: 8) {
            Text(window.label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)

            UsageBar(percent: window.usedPercent, height: 6)

            Text("\(Int(window.usedPercent.rounded()))%")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)

            if let resetsAt = window.resetsAt {
                ResetCountdown(resetsAt: resetsAt, size: 10.5)
                    .frame(width: 58, alignment: .trailing)
            }
        }
    }
}

/// One allowance: its name, its plan or the time its reading was taken, and
/// every window it reports.
public struct AllowanceBlock: View {
    let allowance: ProviderSnapshot
    var windowLimit = Int.max

    public init(allowance: ProviderSnapshot, windowLimit: Int = .max) {
        self.allowance = allowance
        self.windowLimit = windowLimit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(allowance.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            ForEach(allowance.windows.prefix(windowLimit), id: \.label) { window in
                WindowRow(window: window)
            }
        }
    }

    /// The most useful thing that fits on the header line, in order: when
    /// the reading was taken if it is no longer current; then any window this
    /// card had no room to draw, so its figure is not simply lost; then the
    /// plan. Never nothing, and never a dimmed card.
    private var detail: String {
        if allowance.isStale(threshold: Presentation.stalenessThreshold) {
            return "at \(allowance.sourceUpdatedAt.formatted(date: .omitted, time: .shortened))"
        }
        if let hidden = allowance.windows.dropFirst(windowLimit).first {
            return "\(hidden.label) \(Int(hidden.usedPercent.rounded()))%"
        }
        return allowance.planLabel ?? ""
    }
}

/// Shown before anything has reported. An empty widget should say what to do
/// rather than look broken.
public struct EmptyState: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Nothing to report yet")
                .font(.system(size: 12.5, weight: .semibold))
            Text("Open AI Limits in the menu bar to connect Claude Code, or run Codex.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A quiet vertical wash rather than a flat panel, so the widget sits on the
/// desktop as an object with a light source instead of a grey rectangle.
public struct WidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(white: 0.16), Color(white: 0.10)]
                : [Color(white: 1.0), Color(white: 0.93)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
