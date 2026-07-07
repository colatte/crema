import SwiftUI

/// Tags a crossfade branch with its stable layout identity (a constant per
/// branch, so a removal-frozen ghost keeps the tag it was built with).
/// HuggingWidthClamp uses it to pick the measurement driver.
struct SurfaceBranch: LayoutValueKey {
    static let defaultValue: String? = nil
}

/// Width clamp that hugs its content. SwiftUI's flexible frame with both
/// bounds resolves to the clamped proposal and ignores the child — under the
/// fixed window's proposal that made a [floor, ceiling] frame a constant
/// ceiling, silently defeating the adaptive width. This layout measures the
/// child at its ideal width (nil proposal) and sizes to that clamped to
/// [floor, ceiling]; at placement it proposes the resolved bounds, so
/// flexible rows (spacers pinning a trailing element, full-width headers)
/// expand to the real surface edges instead of leaving the block floating at
/// its intrinsic width with arbitrary margins. Measuring at a concrete width
/// would read those same flexible rows back as the proposal and pin the hug
/// at the ceiling. Nil bounds pass the proposal through untouched (the
/// fixed-size states).
///
/// The subviews are the surface's crossfading branches, all placed centered
/// and overlapping (a ZStack in layout terms) — but only the branch tagged
/// `activeBranch` drives the measurement. An outgoing ghost mid-fade would
/// otherwise hold the width at the union of both branches and, on removal,
/// drop it as an unanimated snap — no animation value changes at that instant.
struct HuggingWidthClamp: Layout {
    var minWidth: CGFloat?
    var maxWidth: CGFloat?
    var activeBranch: String?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = driver(in: subviews) else { return .zero }
        let size = child.sizeThatFits(measurement(from: proposal))
        var width = size.width
        if let maxWidth { width = min(width, maxWidth) }
        if let minWidth { width = max(width, minWidth) }
        return CGSize(width: width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for child in subviews {
            child.place(
                at: CGPoint(x: bounds.midX, y: bounds.midY),
                anchor: .center,
                proposal: ProposedViewSize(bounds.size)
            )
        }
    }

    private func driver(in subviews: Subviews) -> LayoutSubviews.Element? {
        guard let activeBranch else { return subviews.first }
        return subviews.first { $0[SurfaceBranch.self] == activeBranch } ?? subviews.first
    }

    private func measurement(from proposal: ProposedViewSize) -> ProposedViewSize {
        guard maxWidth != nil else { return proposal }
        return ProposedViewSize(width: nil, height: proposal.height)
    }
}
