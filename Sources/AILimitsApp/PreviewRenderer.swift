import AppKit
import LimitKit

/// Draws the menu's rows to a PNG.
///
/// This repo is meant to be worked on through an AI agent, which cannot see
/// the screen. Without this, the only way to check a spacing or colour change
/// is to ask a person to look — so a visual change either goes unverified or
/// costs a round trip. Rendering the real views to a file closes that loop:
/// the same code that draws the menu draws the picture.
///
/// Reached through `AILimits --render-preview <path>`, alongside
/// `--print-snapshot`. Both light and dark are drawn, side by side, because a
/// colour that works in one regularly fails in the other.
@MainActor
enum PreviewRenderer {
    private static let width: CGFloat = 288

    static func render(_ snapshot: Snapshot, to url: URL) throws {
        // Each appearance is drawn on its own, inside its own drawing
        // context. Composing both into one view and capturing once renders
        // everything in whichever appearance happens to be current, which
        // silently produced two identical dark panels.
        let shots = [NSAppearance(named: .aqua), NSAppearance(named: .darkAqua)]
            .compactMap { $0 }
            .compactMap { appearance -> NSBitmapImageRep? in
                var captured: NSBitmapImageRep?
                appearance.performAsCurrentDrawingAppearance {
                    let panel = panel(for: snapshot, appearance: appearance)
                    guard let rep = panel.bitmapImageRepForCachingDisplay(in: panel.bounds) else {
                        return
                    }
                    panel.cacheDisplay(in: panel.bounds, to: rep)
                    captured = rep
                }
                return captured
            }

        let gap: CGFloat = 16
        let totalWidth = shots.reduce(0) { $0 + $1.size.width } + gap * CGFloat(shots.count + 1)
        let totalHeight = (shots.map(\.size.height).max() ?? 0) + gap * 2

        let canvas = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        canvas.lockFocus()
        NSColor(white: 0.5, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight).fill()
        var x = gap
        for shot in shots {
            shot.draw(in: NSRect(
                x: x, y: totalHeight - gap - shot.size.height,
                width: shot.size.width, height: shot.size.height
            ))
            x += shot.size.width + gap
        }
        canvas.unlockFocus()

        guard let tiff = canvas.tiffRepresentation,
              let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }

    /// One appearance's worth of menu, on the background the menu sits on.
    private static func panel(for snapshot: Snapshot, appearance: NSAppearance) -> NSView {
        var rows: [NSView] = []
        if snapshot.providers.isEmpty {
            rows.append(EmptyStateView(width: width))
        }
        for allowance in snapshot.providers {
            rows.append(AllowanceHeaderView(allowance: allowance, width: width))
            rows += allowance.windows.map { WindowRowView(window: $0, width: width) }
        }

        let padding: CGFloat = 10
        let height = rows.reduce(padding * 2) { $0 + $1.frame.height }
        let panel = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        panel.appearance = appearance
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        panel.layer?.cornerRadius = 10

        var y = height - padding
        for row in rows {
            y -= row.frame.height
            row.setFrameOrigin(NSPoint(x: 0, y: y))
            panel.addSubview(row)
        }
        return panel
    }

    /// Stand-in readings that exercise every state the menu can show: a
    /// comfortable window, one past the notch, an exhausted one, a named
    /// Codex allowance, and a reading that is no longer current.
    static var sampleSnapshot: Snapshot {
        let now = Date()
        return Snapshot(
            generatedAt: now,
            providers: [
                ProviderSnapshot(
                    provider: .claude,
                    planLabel: "max",
                    windows: [
                        LimitWindow(label: "5-hour", usedPercent: 91, resetsAt: now.addingTimeInterval(7_400)),
                        LimitWindow(label: "Weekly", usedPercent: 24, resetsAt: now.addingTimeInterval(320_000)),
                    ],
                    sourceUpdatedAt: now
                ),
                ProviderSnapshot(
                    provider: .codex,
                    planLabel: "plus",
                    windows: [
                        LimitWindow(label: "5-hour", usedPercent: 100, resetsAt: now.addingTimeInterval(1_900)),
                        LimitWindow(label: "Weekly", usedPercent: 58, resetsAt: now.addingTimeInterval(500_000)),
                    ],
                    // Deliberately old, to show how a reading that is not
                    // current is labelled rather than faded out.
                    sourceUpdatedAt: now.addingTimeInterval(-3_600)
                ),
                ProviderSnapshot(
                    provider: .codex,
                    bucketName: "GPT-5.3-Codex-Spark",
                    planLabel: "plus",
                    windows: [
                        LimitWindow(label: "5-hour", usedPercent: 7, resetsAt: now.addingTimeInterval(9_000))
                    ],
                    sourceUpdatedAt: now
                ),
            ]
        )
    }
}

// MARK: - Widget layouts

import LimitUI
import SwiftUI

extension PreviewRenderer {
    /// Draws the desktop widget's layouts at their real sizes, light and dark.
    ///
    /// A widget only exists inside a system extension, so the only other way
    /// to see a change is to put it on a desktop and look. `ImageRenderer`
    /// draws the same views the extension does.
    ///
    /// `BusiestView` and `AllAllowancesView` are rendered directly rather than
    /// through `OverviewView`, because the widget family is not something a
    /// host can set from outside WidgetKit.
    static func renderWidgets(_ snapshot: Snapshot, to url: URL) throws {
        // macOS widget sizes, in points.
        let small = CGSize(width: 158, height: 158)
        let medium = CGSize(width: 338, height: 158)

        let shots: [NSImage] = [
            (small, ColorScheme.light), (medium, .light),
            (small, .dark), (medium, .dark),
        ].compactMap { size, scheme in
            image(of: card(snapshot, size: size, scheme: scheme), size: size)
        }

        try writeGrid(shots, columns: 2, to: url)
    }

    @ViewBuilder
    private static func card(_ snapshot: Snapshot, size: CGSize, scheme: ColorScheme) -> some View {
        ZStack {
            WidgetBackground()
            Group {
                if size.width < 200 {
                    BusiestView(snapshot: snapshot)
                } else {
                    AllAllowancesView(snapshot: snapshot)
                }
            }
            .padding(14)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, scheme)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private static func image(of view: some View, size: CGSize) -> NSImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.nsImage
    }

    private static func writeGrid(_ images: [NSImage], columns: Int, to url: URL) throws {
        let gap: CGFloat = 18
        let rows = Int(ceil(Double(images.count) / Double(columns)))
        let rowHeight = (images.map(\.size.height).max() ?? 0) + gap
        let rowWidth = stride(from: 0, to: images.count, by: columns)
            .map { images[$0..<min($0 + columns, images.count)].reduce(0) { $0 + $1.size.width + gap } }
            .max() ?? 0

        let canvas = NSImage(size: NSSize(width: rowWidth + gap, height: rowHeight * CGFloat(rows) + gap))
        canvas.lockFocus()
        NSColor(white: 0.5, alpha: 1).setFill()
        NSRect(origin: .zero, size: canvas.size).fill()

        var x = gap
        var y = canvas.size.height - gap
        for (index, image) in images.enumerated() {
            if index % columns == 0 {
                x = gap
                y -= image.size.height + (index == 0 ? 0 : gap)
            }
            image.draw(in: NSRect(x: x, y: y, width: image.size.width, height: image.size.height))
            x += image.size.width + gap
        }
        canvas.unlockFocus()

        guard let tiff = canvas.tiffRepresentation,
              let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }
}
