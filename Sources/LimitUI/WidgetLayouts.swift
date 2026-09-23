import LimitKit
import SwiftUI
import WidgetKit

/// The widget's layouts, kept out of the extension target so the menu bar
/// app can render them to an image for review. A widget that only exists
/// inside a system extension cannot be looked at without a person looking
/// at a desktop.


public struct OverviewView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: Snapshot?

    public init(snapshot: Snapshot?) { self.snapshot = snapshot }

    public var body: some View {
        if let snapshot, !snapshot.providers.isEmpty {
            switch family {
            case .systemSmall: BusiestView(snapshot: snapshot)
            default: AllAllowancesView(snapshot: snapshot)
            }
        } else {
            EmptyState()
        }
    }
}

/// Small size: one reading, large enough to take in without looking directly
/// at it — the window closest to running out, and when it comes back.
public struct BusiestView: View {
    @Environment(\.colorScheme) private var colorScheme
    let snapshot: Snapshot

    private var busiest: (allowance: ProviderSnapshot, window: LimitWindow)? {
        snapshot.providers
            .compactMap { allowance in allowance.tightestWindow.map { (allowance, $0) } }
            .max { $0.1.usedPercent < $1.1.usedPercent }
    }

    public init(snapshot: Snapshot) { self.snapshot = snapshot }

    public var body: some View {
        if let busiest {
            VStack(alignment: .leading, spacing: 0) {
                Text(busiest.allowance.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 2)

                Text("\(Int(busiest.window.usedPercent.rounded()))%")
                    .font(.system(size: 44, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(
                        Color(
                            Presentation.ink(
                                for: Presentation.severity(forUsedPercent: busiest.window.usedPercent)
                            ),
                            dark: colorScheme == .dark
                        )
                    )
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text("\(busiest.window.label) window")
                    .font(.system(size: 11, weight: .medium))

                Spacer(minLength: 6)

                UsageBar(percent: busiest.window.usedPercent, height: 8)

                if let resetsAt = busiest.window.resetsAt {
                    ResetCountdown(resetsAt: resetsAt).padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyState()
        }
    }
}

/// Medium size: every allowance, stacked. Rows rather than columns, because
/// Codex can report a separate allowance per model and a third column would
/// squeeze the bars out of legibility.
public struct AllAllowancesView: View {
    let snapshot: Snapshot

    /// Three allowances is a full card. Past that the least pressing
    /// readings are the ones worth dropping — `providers` arrives with the
    /// tightest first.
    private var visible: [ProviderSnapshot] { Array(snapshot.providers.prefix(3)) }

    /// Two windows each fits comfortably for one or two allowances. For three
    /// there is only room for the tightest, and the other window's figure
    /// moves up to the header line rather than disappearing.
    private var windowsPerAllowance: Int { visible.count > 2 ? 1 : 2 }

    public init(snapshot: Snapshot) { self.snapshot = snapshot }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(visible) { allowance in
                AllowanceBlock(allowance: allowance, windowLimit: windowsPerAllowance)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

public struct SingleProviderView: View {
    @Environment(\.widgetFamily) private var family
    let allowances: [ProviderSnapshot]
    let name: String

    public init(allowances: [ProviderSnapshot], name: String) {
        self.allowances = allowances
        self.name = name
    }

    public var body: some View {
        if allowances.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(size: 12.5, weight: .semibold))
                Text("Not reporting yet.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if family == .systemSmall, let first = allowances.first {
            AllowanceBlock(allowance: first, windowLimit: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(allowances.prefix(3)) { allowance in
                    AllowanceBlock(allowance: allowance, windowLimit: 2)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
