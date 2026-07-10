import CoreGraphics
import Testing
@testable import Crema

/// The provenance-aware "freeze the outgoing geometry while hidden" contract: a
/// hidden surface holds the last-visible layout's rect (and, on Card, its
/// radius/width discipline), so every fade-out sits on the rect it is leaving —
/// no snap to a compact silhouette behind a fading HUD, no mirror shrink on
/// dismissal. Pinned as pure functions, no view and no environment.
struct SurfaceEmptyGeometryTests {
    private let sizes = SurfaceStateSizes(
        compact: CGSize(width: 280, height: 64),
        expanded: CGSize(width: 280, height: 132),
        hud: CGSize(width: 210, height: 42)
    )

    // MARK: - Card

    @Test func cardEmptyAfterHudHoldsTheHudRectAndRadius() {
        let kind = CardView.effectiveLayoutKind(layout: .empty, lastVisible: .hud)
        #expect(kind == .hud)
        #expect(CardView.surfaceSize(for: kind, in: sizes, showsControls: true) == sizes.hud)
        #expect(CardView.surfaceCornerRadius(for: kind) == CardMetrics.hudSystemCornerRadius)
    }

    @Test func cardEmptyAfterExpandedHoldsTheExpandedRectAndCardRadius() {
        let kind = CardView.effectiveLayoutKind(layout: .empty, lastVisible: .expanded)
        #expect(kind == .expanded)
        #expect(CardView.surfaceSize(for: kind, in: sizes, showsControls: true) == sizes.expanded)
        #expect(CardView.surfaceCornerRadius(for: kind) == CardMetrics.cornerRadius)
    }

    @Test func cardInitialEmptyFallsBackToCompact() {
        // lastVisible defaults to .compact before anything has shown.
        let kind = CardView.effectiveLayoutKind(layout: .empty, lastVisible: .compact)
        #expect(kind == .compact)
        #expect(CardView.surfaceSize(for: kind, in: sizes, showsControls: true) == sizes.compact)
        #expect(CardView.surfaceCornerRadius(for: kind) == CardMetrics.cornerRadius)
    }

    @Test func cardVisibleLayoutsPresentThemselves() {
        #expect(CardView.effectiveLayoutKind(layout: .hud, lastVisible: .compact) == .hud)
        #expect(CardView.effectiveLayoutKind(layout: .compact, lastVisible: .hud) == .compact)
        #expect(CardView.effectiveLayoutKind(layout: .expanded, lastVisible: .hud) == .expanded)
    }

    @Test func cardViewOnlyExpandedDropsTheControlsSection() {
        let full = CardView.surfaceSize(for: .expanded, in: sizes, showsControls: true)
        let trimmed = CardView.surfaceSize(for: .expanded, in: sizes, showsControls: false)
        #expect(trimmed.height == full.height - CardMetrics.controlsSectionHeight)
        #expect(trimmed.width == full.width)
    }

    // MARK: - Classic

    @Test func classicEmptyAfterHudHoldsTheHudRect() {
        let kind = ClassicView.effectiveLayoutKind(layout: .empty, lastVisible: .hud)
        #expect(kind == .hud)
        #expect(ClassicView.surfaceSize(for: kind, in: sizes, showsControls: true) == sizes.hud)
    }

    @Test func classicEmptyAfterExpandedHoldsTheExpandedRect() {
        let kind = ClassicView.effectiveLayoutKind(layout: .empty, lastVisible: .expanded)
        #expect(kind == .expanded)
        #expect(ClassicView.surfaceSize(for: kind, in: sizes, showsControls: true) == sizes.expanded)
    }

    @Test func classicInitialEmptyFallsBackToCompact() {
        let kind = ClassicView.effectiveLayoutKind(layout: .empty, lastVisible: .compact)
        #expect(kind == .compact)
        #expect(ClassicView.surfaceSize(for: kind, in: sizes, showsControls: true) == sizes.compact)
    }

    @Test func classicViewOnlyExpandedDropsTheControlsSection() {
        let full = ClassicView.surfaceSize(for: .expanded, in: sizes, showsControls: true)
        let trimmed = ClassicView.surfaceSize(for: .expanded, in: sizes, showsControls: false)
        #expect(trimmed.height == full.height - ClassicMetrics.controlsSectionHeight)
        #expect(trimmed.width == full.width)
    }

    // MARK: - Notch (freezes the drop AND the flare; HUD is immune by construction)

    @Test func notchEmptyAfterExpandedHoldsTheExpandedRectAndFlare() {
        let kind = NotchView.effectiveLayoutKind(layout: .empty, lastVisible: .expanded)
        #expect(kind == .expanded)
        #expect(NotchView.surfaceSize(for: kind, in: sizes, showsControls: true) == sizes.expanded)
        // The expanded outline's wider radii must persist under the fade, not snap
        // back to the compact flare behind it.
        let shape = NotchView.shape(for: kind)
        #expect(shape.topRadius == NotchMetrics.expandedTopRadius)
        #expect(shape.bottomRadius == NotchMetrics.expandedBottomRadius)
    }

    @Test func notchEmptyAfterHudHoldsTheHudRectAndCompactFlare() {
        // HUD shares the compact frame and the compact (unflared) shape by
        // construction — the by-construction-immune path stays byte-identical.
        let kind = NotchView.effectiveLayoutKind(layout: .empty, lastVisible: .hud)
        #expect(kind == .hud)
        #expect(NotchView.surfaceSize(for: kind, in: sizes, showsControls: true) == sizes.hud)
        let shape = NotchView.shape(for: kind)
        #expect(shape.topRadius == NotchMetrics.compactTopRadius)
        #expect(shape.bottomRadius == NotchMetrics.compactBottomRadius)
    }

    @Test func notchInitialEmptyFallsBackToCompact() {
        let kind = NotchView.effectiveLayoutKind(layout: .empty, lastVisible: .compact)
        #expect(kind == .compact)
        #expect(NotchView.surfaceSize(for: kind, in: sizes, showsControls: true) == sizes.compact)
        let shape = NotchView.shape(for: kind)
        #expect(shape.topRadius == NotchMetrics.compactTopRadius)
        #expect(shape.bottomRadius == NotchMetrics.compactBottomRadius)
    }

    @Test func notchVisibleLayoutsPresentThemselves() {
        #expect(NotchView.effectiveLayoutKind(layout: .hud, lastVisible: .compact) == .hud)
        #expect(NotchView.effectiveLayoutKind(layout: .compact, lastVisible: .hud) == .compact)
        #expect(NotchView.effectiveLayoutKind(layout: .expanded, lastVisible: .hud) == .expanded)
    }

    @Test func notchViewOnlyExpandedDropsTheControlsSection() {
        let full = NotchView.surfaceSize(for: .expanded, in: sizes, showsControls: true)
        let trimmed = NotchView.surfaceSize(for: .expanded, in: sizes, showsControls: false)
        #expect(trimmed.height == full.height - NotchMetrics.controlsSectionHeight)
        #expect(trimmed.width == full.width)
    }
}
