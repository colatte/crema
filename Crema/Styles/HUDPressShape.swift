import CoreGraphics
import SwiftUI

/// The bar under a held key, drawn the way UIKit's fluid slider draws the iPhone's
/// volume HUD (docs/DECISIONS.md: the-bar-answers-the-press). Two answers stack:
/// the whole bar scales while the key is down, up for the key that raises the
/// level and down for the one that lowers it; and each press that finds the level
/// already at the end the key points to pushes the bar past that end, against a
/// resistance that grows, the bar drifting toward the push, so the far end travels
/// and the near one follows it.
///
/// Every constant is UIKit's, read decompiled from UIKitCore of iOS 26.1 (23B85):
/// the scales from `_UIFluidSliderDiscreteButtonDriverSettings`, the resistance
/// from `_UIFluidSliderDiscreteButtonDriver`, the drift and the squish from
/// `_UIFluidSliderSettings`. How far a bar may go past its end is not: the HUD's
/// own amount did not survive decompilation, so each bar names its ceiling from
/// the room it has (`CapsuleTrack.pressCeiling`, `CardMetrics.hudFilledPressCeiling`).
struct HUDPressShape: Equatable {
    /// Along the bar.
    var length: CGFloat
    /// Across the bar.
    var thickness: CGFloat
    /// How far the bar's centre moves along it, positive toward the full end.
    var shift: CGFloat

    nonisolated static let horizontalRaiseScale: CGFloat = 1.03
    nonisolated static let horizontalLowerScale: CGFloat = 0.96
    nonisolated static let verticalRaiseScale: CGFloat = 1.06
    nonisolated static let verticalLowerScale: CGFloat = 0.92
    /// The step a press adds past the end, as a share of the bar: a sixteenth.
    nonisolated static let stepsPerBar: CGFloat = 16
    nonisolated static let resistance: CGFloat = 0.55
    /// The share of the push the bar does not lengthen by; it drifts instead.
    nonisolated static let drift: CGFloat = 0.27
    nonisolated static let squishFactor: CGFloat = 0.92
    nonisolated static let squishPoints: CGFloat = 4

    /// The bar as it rests.
    nonisolated init(length: CGFloat, thickness: CGFloat) {
        self.length = length
        self.thickness = thickness
        shift = 0
    }

    /// The bar of `length` and `thickness` answering `press`, never pushed more
    /// than `ceiling` points past its end. Nil `press` is the bar at rest.
    nonisolated init(length: CGFloat, thickness: CGFloat, axis: Axis, press: HUDPress?, ceiling: CGFloat) {
        guard let press else {
            self.length = length
            self.thickness = thickness
            shift = 0
            return
        }
        let scale = Self.scale(raising: press.end == .end, axis: axis)
        let overflow = Self.overflow(steps: press.stepsPastEnd, length: length, ceiling: ceiling)
        // UIKit thins a bar by the larger of 8% and 4 pt, which would flatten a
        // 4 pt track to nothing; the gentler of the two keeps every bar drawn.
        let squished = max(Self.squishFactor * thickness, thickness - Self.squishPoints)
        let squish = ceiling > 0 ? overflow / ceiling : 0
        self.length = scale * (length + (1 - Self.drift) * overflow)
        self.thickness = scale * (thickness - squish * (thickness - squished))
        shift = scale * (Self.drift + 0.5) * overflow * (press.end == .end ? 1 : -1)
    }

    nonisolated static func scale(raising: Bool, axis: Axis) -> CGFloat {
        switch axis {
        case .horizontal: raising ? horizontalRaiseScale : horizontalLowerScale
        case .vertical: raising ? verticalRaiseScale : verticalLowerScale
        }
    }

    /// How far past its end `steps` presses push a bar of `length`, in points:
    /// the first press goes far, every next one less, never reaching `ceiling`.
    nonisolated static func overflow(steps: Int, length: CGFloat, ceiling: CGFloat) -> CGFloat {
        guard steps > 0, ceiling > 0 else { return 0 }
        let excess = CGFloat(steps) * length / stepsPerBar
        return ceiling * (1 - 1 / (1 + resistance * excess / ceiling))
    }

    /// The farthest an end of a bar of `length` travels past where it rests, the
    /// raising scale at its largest and the push at its ceiling: the room its
    /// surface must keep.
    nonisolated static func reach(length: CGFloat, axis: Axis, ceiling: CGFloat) -> CGFloat {
        let scale = scale(raising: true, axis: axis)
        return (scale - 1) * length / 2 + scale * ((1 - drift) / 2 + drift + 0.5) * ceiling
    }
}
