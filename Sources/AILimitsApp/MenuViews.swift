import AppKit
import LimitKit

/// The views that make up the menu bar dropdown.
///
/// These are drawn rather than written. Menu rows built from `NSMenuItem`
/// titles have to be disabled to stop them looking clickable, and macOS greys
/// disabled items out — so a bar made of block characters arrived on screen
/// as dead grey text, which is exactly what a broken reading looks like.
/// Custom views keep full colour and let the bar be an instrument.

extension NSColor {
    /// Resolves a reading's colour for the appearance it will be drawn in.
    static func ink(_ ink: Presentation.Ink, for appearance: NSAppearance) -> NSColor {
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let resolved = isDark ? ink.lifted : ink
        return NSColor(
            srgbRed: resolved.red, green: resolved.green, blue: resolved.blue, alpha: 1
        )
    }
}

/// A usage bar with a notch at the point where the reading turns critical.
///
/// The notch is the difference between a strip that changes colour and a
/// gauge you can read: it shows how close the allowance is to trouble
/// without anyone having to interpret the number.
final class BarView: NSView {
    var percent: Double = 0 { didSet { needsDisplay = true } }

    private let height: CGFloat = 7

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: height) }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
        let radius = height / 2

        NSColor.labelColor.withAlphaComponent(0.13).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        let severity = Presentation.severity(forUsedPercent: percent)
        let fillWidth = track.width * CGFloat(percent / 100)
        if fillWidth > 0 {
            NSColor.ink(Presentation.ink(for: severity), for: effectiveAppearance).setFill()
            // Never narrower than it is tall, so a 1% reading is still a mark
            // on the gauge rather than an invisible sliver.
            let fill = NSRect(
                x: track.minX, y: track.minY,
                width: max(fillWidth, height), height: track.height
            )
            NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
        }

        // Drawn from the label colour, so it contrasts against the track on a
        // light desktop and a dark one alike — a notch tinted like the panel
        // disappears into the track in dark mode. It sits on top of the fill
        // so it stays readable once the reading has passed it.
        let notchX = track.minX + track.width * CGFloat(Presentation.criticalThreshold / 100)
        NSColor.labelColor.withAlphaComponent(0.45).setFill()
        NSRect(x: notchX, y: track.minY, width: 1.5, height: track.height).fill()
    }
}

/// One window: what it is, how much is gone, and when it comes back.
final class WindowRowView: NSView {
    init(window: LimitWindow, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 34))

        let label = Self.text(window.label, size: 11, color: .secondaryLabelColor)
        let percent = Self.text(
            "\(Int(window.usedPercent.rounded()))%",
            size: 11.5, weight: .semibold, color: .labelColor, tabular: true
        )
        percent.alignment = .right

        let bar = BarView()
        bar.percent = window.usedPercent

        let reset = Self.text(
            Presentation.resetPhrase(for: window), size: 10.5, color: .tertiaryLabelColor
        )

        for view in [label, percent, bar, reset] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.widthAnchor.constraint(equalToConstant: 58),

            percent.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            percent.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            percent.widthAnchor.constraint(equalToConstant: 38),

            bar.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            bar.trailingAnchor.constraint(equalTo: percent.leadingAnchor, constant: -10),
            bar.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            bar.heightAnchor.constraint(equalToConstant: 7),

            reset.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            reset.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 3),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    static func text(
        _ string: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor,
        tabular: Bool = false
    ) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.font = tabular
            ? .monospacedDigitSystemFont(ofSize: size, weight: weight)
            : .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }
}

/// An allowance's name, its plan, and — when the reading is not current —
/// when it was taken.
final class AllowanceHeaderView: NSView {
    init(allowance: ProviderSnapshot, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))

        let title = WindowRowView.text(
            allowance.title, size: 12.5, weight: .semibold, color: .labelColor
        )

        let detail: String
        if allowance.isStale(threshold: Presentation.stalenessThreshold) {
            detail = "at \(Self.time.string(from: allowance.sourceUpdatedAt))"
        } else {
            detail = allowance.planLabel ?? ""
        }
        let subtitle = WindowRowView.text(detail, size: 10.5, color: .tertiaryLabelColor)
        subtitle.alignment = .right

        for view in [title, subtitle] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            subtitle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            subtitle.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

/// Shown when nothing has reported yet. An empty menu should say what to do,
/// not just be empty.
final class EmptyStateView: NSView {
    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 40))

        let title = WindowRowView.text(
            "Nothing to report yet", size: 12.5, weight: .semibold, color: .labelColor
        )
        let detail = WindowRowView.text(
            "Connect Claude Code below, or run Codex.", size: 11, color: .secondaryLabelColor
        )

        for view in [title, detail] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
