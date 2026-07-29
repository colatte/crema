import Testing
@testable import Crema

/// The position state machine, one case per transition: playback stays
/// monotonic, pause freezes at the last shown value (never 0), resume flows
/// immediately, and real seeks are obeyed.
struct PositionReconciliationTests {

    private func track(_ title: String = "Breathe", position: Double, playing: Bool = true) -> NowPlaying {
        NowPlaying(title: title, artist: "Pink Floyd", isPlaying: playing, position: position)
    }

    // MARK: Continuous playback (playing → playing)

    @Test func aSmallRegressionDuringPlaybackHoldsTheShownPosition() {
        #expect(PositionReconciliation.position(for: track(position: 41.75), replacing: track(position: 42.5)) == 42.5)
    }

    // MARK: Deliberate seek in flight (the scrubber's release)

    @Test func aPendingSeekLetsASubToleranceBackwardEchoLand() {
        // The precision micro-scrub: without the hint this regression (1.5 s,
        // under seekTolerance) reads as anchor jitter and is held — the pin
        // above. With the seek pending, the echo near the target is obeyed.
        #expect(PositionReconciliation.position(
            for: track(position: 41), replacing: track(position: 42.5), pendingSeek: 41
        ) == 41)
    }

    @Test func aPendingSeekUnfreezesThePausedHold() {
        // A backward scrub while paused: the plain rule freezes at the old
        // value (the dropped-0 heuristic); the echo of the user's own seek
        // must not be eaten by it.
        #expect(PositionReconciliation.position(
            for: track(position: 40, playing: false),
            replacing: track(position: 100, playing: false),
            pendingSeek: 40
        ) == 40)
    }

    @Test func aFarAnchorWhileTheSeekFliesIsHeld() {
        // Any anchor away from the target during the flight is the pre-seek
        // line still echoing — held, in either direction (a stale anchor sits
        // BEFORE a forward seek's target and AFTER a backward one's). The
        // caller bounds the hold with the hint's anchor budget.
        #expect(PositionReconciliation.position(
            for: track(position: 41.75), replacing: track(position: 42.5), pendingSeek: 10
        ) == 42.5)
        // The backward-seek case: re-anchored at 30, the stale 201 echoes in.
        #expect(PositionReconciliation.position(
            for: track(position: 201), replacing: track(position: 30), pendingSeek: 30
        ) == 30)
    }

    @Test func aPausedZeroIsALieNotAConfirmation() {
        // Sought to 2 s then paused: the pause payload's dropped-elapsed 0
        // falls inside the tolerance of a near-start target, but 0-while-
        // paused is the known lie the freeze exists for — held at the target.
        #expect(PositionReconciliation.position(
            for: track(position: 0, playing: false),
            replacing: track(position: 2, playing: false),
            pendingSeek: 2
        ) == 2)
        // Sought to the actual start: there the paused 0 IS the confirmation.
        #expect(PositionReconciliation.position(
            for: track(position: 0, playing: false),
            replacing: track(position: 42, playing: false),
            pendingSeek: 0
        ) == 0)
    }

    @Test func aRealBackwardSeekDuringPlaybackIsObeyed() {
        #expect(PositionReconciliation.position(for: track(position: 30), replacing: track(position: 42.5)) == 30)
    }

    @Test func aRegressionAtOrBeyondTheToleranceIsASeek() {
        #expect(PositionReconciliation.position(for: track(position: 40.5), replacing: track(position: 42.5)) == 40.5)
    }

    @Test func forwardMotionDuringPlaybackAlwaysWins() {
        #expect(PositionReconciliation.position(for: track(position: 43.5), replacing: track(position: 42.5)) == 43.5)
    }

    // MARK: Pause (playing → paused) — symptom 1

    @Test func pausingFreezesAtTheLastShownPositionNotZero() {
        // The pause payload reports 0 (or drops the elapsed key → 0); the
        // scrubber must hold where it was, not snap to the start.
        #expect(PositionReconciliation.position(for: track(position: 0, playing: false), replacing: track(position: 42.5)) == 42.5)
    }

    @Test func pausingAtTheRealStartShowsZero() {
        // Genuinely at 0: freezing there is correct.
        #expect(PositionReconciliation.position(for: track(position: 0, playing: false), replacing: track(position: 0)) == 0)
    }

    @Test func aStaleAnchorOnPauseDoesNotRewind() {
        #expect(PositionReconciliation.position(for: track(position: 41.75, playing: false), replacing: track(position: 42.5)) == 42.5)
    }

    @Test func seekingForwardWhilePausedMovesToTheNewPosition() {
        #expect(PositionReconciliation.position(for: track(position: 90, playing: false), replacing: track(position: 42.5, playing: false)) == 90)
    }

    @Test func aReEmissionWhilePausedHolds() {
        // Paused re-emissions carry the fixed pause anchor (it does not age);
        // they must not drift the frozen position.
        #expect(PositionReconciliation.position(for: track(position: 0, playing: false), replacing: track(position: 42.5, playing: false)) == 42.5)
    }

    // MARK: Resume (paused → playing) — symptom 2

    @Test func resumingFlowsImmediatelyFromTheAnchorWithoutHolding() {
        // No monotonic hold on resume: the anchor is the player's true
        // position and playback must run from it at once, not dwell for up to
        // the tolerance while the ticker catches up.
        #expect(PositionReconciliation.position(for: track(position: 42.2), replacing: track(position: 42.5, playing: false)) == 42.2)
    }

    @Test func resumingHonorsABackwardSeekMadeWhilePaused() {
        #expect(PositionReconciliation.position(for: track(position: 10), replacing: track(position: 42.5, playing: false)) == 10)
    }

    // MARK: Identity

    @Test func aDifferentTrackTakesItsOwnPosition() {
        #expect(PositionReconciliation.position(for: track("Time", position: 0), replacing: track(position: 42.5)) == 0)
        #expect(PositionReconciliation.position(for: track("Time", position: 41.75), replacing: track(position: 42.5)) == 41.75)
    }

    @Test func repeatOneRestartingTheSameTrackIsObeyed() {
        // Same identity, position drops to 0 mid-play: a restart, past the
        // tolerance, so it is taken rather than held.
        #expect(PositionReconciliation.position(for: track(position: 0), replacing: track(position: 168)) == 0)
    }

    @Test func noPreviousMeansTheAnchorWins() {
        #expect(PositionReconciliation.position(for: track(position: 41.75), replacing: nil) == 41.75)
    }
}
