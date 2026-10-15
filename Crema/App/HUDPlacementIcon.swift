import AppKit

/// The picture each place wears in the Position pop-up: a screen outline with
/// the HUD bar where the Card's own rule puts it (`StylePreview.hudBar(at:)`, on
/// the reference panel), so the icon cannot come to show a spot the HUD no longer
/// goes to. Drawn in code as a template image, so the menu tints it for light,
/// dark and the highlighted row alike.
///
/// The bar is magnified, and only in size: faithful, a 16 pt icon draws the HUD
/// under a point thick. Its place keeps the rule's share of the room around it,
/// so a corner stays a corner and a centre a centre once it is larger.
enum HUDPlacementIcon {
    /// A menu row's image height.
    static let height: CGFloat = 16
    static let lineWidth: CGFloat = 1
    static let magnification: CGFloat = 3.5
    /// What the bar keeps from the outline's inner edge, so it never merges with
    /// it: the rule's own margins are under half a point at this size.
    static let gap: CGFloat = 1.5
    static let screenCornerRadius: CGFloat = 2.5

    /// The canvas: the outline in the reference panel's proportions, its stroke
    /// inside the canvas.
    static let size = CGSize(
        width: ((height - lineWidth) * Thumbnail.referenceAspectRatio + lineWidth).rounded(.up),
        height: height
    )

    /// The outline's path, centred in the canvas, y down.
    static var screen: CGRect {
        let pathHeight = height - lineWidth
        let pathWidth = pathHeight * Thumbnail.referenceAspectRatio
        return CGRect(x: (size.width - pathWidth) / 2, y: lineWidth / 2, width: pathWidth, height: pathHeight)
    }

    /// Inside the outline's stroke: where the bar may go.
    static var interior: CGRect {
        screen.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
    }

    /// Where `placement`'s bar is drawn, in the canvas, y down.
    static func bar(for placement: HUDPlacement) -> CGRect {
        let unit = StylePreview.hudBar(at: placement)
        let reference = StylePreview.notchedReference.frame
        let inner = interior
        // One scale for both sides, so the bar keeps the real HUD's proportions.
        let scale = inner.height / reference.height * magnification
        let drawn = CGSize(width: unit.width * reference.width * scale, height: unit.height * reference.height * scale)
        let x = share(of: unit.minX, room: 1 - unit.width) * (inner.width - drawn.width)
        let y = share(of: unit.minY, room: 1 - unit.height) * (inner.height - drawn.height)
        return CGRect(
            x: inner.minX + min(max(x, gap), inner.width - gap - drawn.width),
            y: inner.minY + min(max(y, gap), inner.height - gap - drawn.height),
            width: drawn.width,
            height: drawn.height
        )
    }

    static func image(for placement: HUDPlacement) -> NSImage {
        let bar = bar(for: placement)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.set()
            let outline = NSBezierPath(roundedRect: screen, xRadius: screenCornerRadius, yRadius: screenCornerRadius)
            outline.lineWidth = lineWidth
            outline.stroke()
            let radius = min(bar.width, bar.height) / 2
            NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// How far along the room around it an edge sits, 0 at the start and 1 at the
    /// end; the middle when there is no room to share.
    private static func share(of offset: CGFloat, room: CGFloat) -> CGFloat {
        room > 0 ? offset / room : 0.5
    }
}
