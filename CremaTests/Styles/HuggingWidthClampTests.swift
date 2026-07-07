import AppKit
import SwiftUI
import Testing
@testable import Crema

/// Rendered-layout probes (headless sizeThatFits — layout math, not pixels).
/// The metric-only tests let an inert clamp ship once: SwiftUI's flexible
/// frame resolved to the clamped proposal, so every compact surface rendered at
/// the ceiling. These pin the child-driven behavior itself.
@MainActor
struct HuggingWidthClampTests {

    private let proposal = CGSize(width: 364, height: 40)

    private func width<V: View>(_ view: V) -> CGFloat {
        NSHostingController(rootView: view).sizeThatFits(in: proposal).width
    }

    @Test func sizesToTheChildNotTheProposal() {
        let clamp = HuggingWidthClamp(minWidth: 150, maxWidth: 280) {
            Color.red.frame(width: 200, height: 40)
        }
        #expect(width(clamp) == 200)
    }

    @Test func enforcesTheFloor() {
        let clamp = HuggingWidthClamp(minWidth: 150, maxWidth: 280) {
            Color.red.frame(width: 100, height: 40)
        }
        #expect(width(clamp) == 150)
    }

    @Test func enforcesTheCeiling() {
        let clamp = HuggingWidthClamp(minWidth: 150, maxWidth: 280) {
            Color.red.frame(width: 400, height: 40)
        }
        #expect(width(clamp) == 280)
    }

    @Test func flexibleContentMeasuresAtItsIdealNotTheProposal() {
        // Placement fills the resolved bounds, so branches carry flexible
        // frames and spacers — measurement must read their ideal width, or
        // the hug would resolve to the ceiling for every track.
        let clamp = HuggingWidthClamp(minWidth: 150, maxWidth: 280) {
            Color.red.frame(width: 200, height: 40).frame(maxWidth: .infinity)
        }
        #expect(width(clamp) == 200)
    }

    @Test func placementProposesTheResolvedBoundsToTheChild() async {
        // The other half of the semantics: measurement reads the ideal, but
        // layout must propose the clamped width — the spacing regression this
        // pins had the block floating centered at its intrinsic width inside
        // a floor-clamped surface, with arbitrary margins.
        final class Box: @unchecked Sendable { var width: CGFloat = 0 }
        let box = Box()
        let clamp = HuggingWidthClamp(minWidth: 150, maxWidth: 280) {
            Color.red
                .frame(width: 100, height: 40)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { box.width = $0 })
        }
        let controller = NSHostingController(rootView: clamp)
        controller.view.setFrameSize(controller.view.fittingSize)
        controller.view.layoutSubtreeIfNeeded()
        #expect(await eventually { box.width == 150 })   // fills the floor, not the 100 ideal
    }

    @Test func nilBoundsPassTheProposalThrough() {
        let clamp = HuggingWidthClamp(minWidth: nil, maxWidth: nil) {
            Color.red.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #expect(width(clamp) == proposal.width)
    }

    @Test func onlyTheActiveBranchDrivesTheMeasurement() {
        // The crossfade regression: a greedy outgoing ghost (the HUD's
        // slider, say) must not hold the hug at the ceiling while it fades —
        // nor snap the width, unanimated, when its removal completes.
        let clamp = HuggingWidthClamp(minWidth: 150, maxWidth: 280, activeBranch: "compact") {
            Color.red
                .frame(width: 200, height: 40)
                .layoutValue(key: SurfaceBranch.self, value: "compact")
            Color.blue
                .frame(maxWidth: .infinity, maxHeight: .infinity)   // the greedy ghost
                .layoutValue(key: SurfaceBranch.self, value: "hud")
        }
        #expect(width(clamp) == 200)
    }

    @Test func missingActiveBranchFallsBackToTheFirstSubview() {
        // Mid-transition edge: if the active branch is briefly absent, the
        // clamp must still size to something rather than collapse to zero.
        let clamp = HuggingWidthClamp(minWidth: 150, maxWidth: 280, activeBranch: "expanded") {
            Color.red
                .frame(width: 200, height: 40)
                .layoutValue(key: SurfaceBranch.self, value: "compact")
        }
        #expect(width(clamp) == 200)
    }
}
