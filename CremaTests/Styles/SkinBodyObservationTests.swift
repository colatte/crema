import Observation
import SwiftUI
import Testing
@testable import Crema

/// What a skin's own body subscribes to. Observation tracks per body and per
/// property, and `nowPlaying` is rewritten once a second, so a skin that reads the
/// live position in its own body re-evaluates whole — layout, branches, the
/// artwork slot — on every tick of an open player. The position belongs to the
/// scrubber row's own view (docs/STATE-FLOW.md: an expensive consumer goes in its
/// own View); the skin builds that view and never reads the tick itself.
@MainActor
struct SkinBodyObservationTests {

    private func body(of style: Style, coordinator: Coordinator) -> () -> Void {
        switch style {
        case .notch:
            let view = NotchView(coordinator: coordinator)
            return { _ = view.body }
        case .card:
            let view = CardView(coordinator: coordinator)
            return { _ = view.body }
        case .classic:
            let view = ClassicView(coordinator: coordinator)
            return { _ = view.body }
        }
    }

    @Test func theScrubberRowReadsThePositionFromNowPlayingNotFromState() async {
        let h = CoordinatorHarness()
        let row = LiveScrubberRow(coordinator: h.coordinator, enabled: true, onScrub: { _ in })
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 10))
        #expect(await eventually { row.position == 10 })

        let stateBefore = h.coordinator.state
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 11))
        #expect(await eventually { row.position == 11 })
        #expect(h.coordinator.state == stateBefore)
    }

    @Test(arguments: [Style.notch, .card, .classic])
    func aPositionTickLeavesTheExpandedSkinsBodyAlone(style: Style) async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 10))
        #expect(await eventually { h.coordinator.nowPlaying?.position == 10 })
        h.coordinator.hover(true, on: .both)
        guard case .nowPlaying(_, expanded: true) = h.coordinator.state else {
            Issue.record("the player did not open")
            return
        }

        let invalidated = Flag()
        let evaluate = body(of: style, coordinator: h.coordinator)
        withObservationTracking {
            evaluate()
        } onChange: {
            invalidated.value = true
        }

        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 11))

        // The barrier is the write itself: Observation calls onChange at willSet,
        // so once the new position is readable a tracked read has already fired.
        #expect(await eventually { h.coordinator.nowPlaying?.position == 11 })
        #expect(!invalidated.value)
    }
}
