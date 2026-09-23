import AppKit
import LimitKit

/// The glyph in the menu bar: a small cell that fills as the allowance goes.
///
/// Drawn rather than set in text, because the point of a menu bar item is to
/// be read without being looked at. A shape that fills up registers from the
/// corner of the eye; "34%" has to be read. The number still sits beside it
/// for when the exact figure matters.
enum MenuBarIcon {
    private static let size = NSSize(width: 9, height: 13)

    static func image(usedPercent: Double?, appearance: NSAppearance) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let outline = rect.insetBy(dx: 0.75, dy: 0.75)
            let radius: CGFloat = 2

            // The empty cell reads as a container, so a low reading still
            // looks like a gauge rather than a stray mark.
            NSColor.secondaryLabelColor.setStroke()
            let border = NSBezierPath(roundedRect: outline, xRadius: radius, yRadius: radius)
            border.lineWidth = 1
            border.stroke()

            guard let usedPercent else { return true }

            let inner = outline.insetBy(dx: 1.75, dy: 1.75)
            let filled = inner.height * CGFloat(min(max(usedPercent, 0), 100) / 100)
            guard filled > 0.5 else { return true }

            // Fills upward: a full cell means the allowance is gone.
            let severity = Presentation.severity(forUsedPercent: usedPercent)
            NSColor.ink(Presentation.ink(for: severity), for: appearance).setFill()
            NSBezierPath(
                roundedRect: NSRect(
                    x: inner.minX, y: inner.minY, width: inner.width, height: filled
                ),
                xRadius: 1, yRadius: 1
            ).fill()

            return true
        }
        image.isTemplate = false
        return image
    }
}
