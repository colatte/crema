import SwiftUI

/// The notch surface outline: a rounded rectangle whose bottom corners flare
/// more than its top (the signature "liquid dripping
/// from the hardware" look; the top meets the bezel, the base rounds off).
/// Radii are clamped so they never exceed the rect.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    /// Interpolate the radii when the surface morphs between compact and expanded.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let limit = min(rect.width, rect.height) / 2
        let top = min(max(0, topRadius), limit)
        let bottom = min(max(0, bottomRadius), limit)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addArc(
            center: CGPoint(x: rect.minX + top, y: rect.minY + top),
            radius: top, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - top, y: rect.minY + top),
            radius: top, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addArc(
            center: CGPoint(x: rect.maxX - bottom, y: rect.maxY - bottom),
            radius: bottom, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + bottom, y: rect.maxY - bottom),
            radius: bottom, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
