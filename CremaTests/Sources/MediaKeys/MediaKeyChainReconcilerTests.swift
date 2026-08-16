import Foundation
import Testing
@testable import Crema

/// Who gets the media keys first. The stakes are asymmetric: a missed contender
/// costs a diagnostic line the user never sees, while a false one accuses a
/// neighbouring app of something it is not doing — so every rule here narrows
/// rather than widens (docs/DECISIONS.md: media-key-chain-contention).
struct MediaKeyChainReconcilerTests {

    private let us: pid_t = 100
    private let them: pid_t = 200

    private func chain(_ entries: [EventTapEntry]) -> MediaKeyChain {
        MediaKeyChainReconciler.chain(
            ourPID: us,
            mask: MediaKeyTranslation.systemDefinedMask,
            in: entries
        )
    }

    @Test func nothingInFrontMeansTheKeysAreOurs() {
        // The healthy shape observed on hardware: we inserted last, so we are
        // listed first, and the rival behind us gets what we pass along.
        #expect(chain([
            .contender(pid: us),
            .contender(pid: them),
        ]) == .ours)
    }

    @Test func aFilterTapInFrontTakesTheKeysBeforeWeSeeThem() {
        // The broken shape: the rival's tap was created after ours, head-inserted
        // ahead of it, and our callback never fires for the keys it swallows.
        #expect(chain([
            .contender(pid: them),
            .contender(pid: us),
        ]) == .precededBy(them))
    }

    @Test func aListenOnlyTapInFrontTakesNothing() {
        // Accessibility daemons watch the same events passively on every Mac. A
        // listener cannot swallow, so treating one as a contender would fire the
        // warning permanently, for everyone.
        let watcher = EventTapEntry(
            pid: them,
            isEnabled: true,
            canConsume: false,
            mask: MediaKeyTranslation.systemDefinedMask,
            precedesSessionTaps: false,
            followsSessionTaps: false,
            processBeingTapped: nil
        )
        #expect(chain([watcher, .contender(pid: us)]) == .ours)
    }

    @Test func aDisabledTapInFrontTakesNothing() {
        let dormant = EventTapEntry(
            pid: them,
            isEnabled: false,
            canConsume: true,
            mask: MediaKeyTranslation.systemDefinedMask,
            precedesSessionTaps: false,
            followsSessionTaps: false,
            processBeingTapped: nil
        )
        #expect(chain([dormant, .contender(pid: us)]) == .ours)
    }

    @Test func aTapWatchingOtherEventsIsNoRival() {
        // Mouse and keyboard taps are everywhere; only an overlap with our own
        // mask puts an app in the running for the same key.
        let mouseWatcher = EventTapEntry(
            pid: them,
            isEnabled: true,
            canConsume: true,
            mask: 1 << 5,
            precedesSessionTaps: false,
            followsSessionTaps: false,
            processBeingTapped: nil
        )
        #expect(chain([mouseWatcher, .contender(pid: us)]) == .ours)
    }

    @Test func withoutATapOfOursThereIsNothingToSay() {
        // Permission missing or install still pending: we are not in the chain,
        // so nobody is "ahead" of us and the Accessibility warning owns the story.
        #expect(chain([.contender(pid: them)]) == .unknown)
        #expect(chain([]) == .unknown)
    }

    @Test func aHIDTapIsAheadWhereverItIsListed() {
        // The one ordering the SDK actually promises: HID events reach the window
        // server before they reach a login session, so list position cannot save us.
        #expect(chain([
            .contender(pid: us),
            .contender(pid: them, atHIDLocation: true),
        ]) == .precededBy(them))
    }

    @Test func fromTheHIDLocationASessionTapNeverGetsAhead() {
        // The mirror of the rule above. Crema taps the session location today;
        // the rule is stated symmetrically so it stays true if that ever changes.
        #expect(chain([
            .contender(pid: them),
            .contender(pid: us, atHIDLocation: true),
        ]) == .ours)
    }

    @Test func theFirstContenderIsTheOneNamed() {
        // Two rivals ahead: the one that gets the key first is the one worth
        // naming — the second never sees it either.
        #expect(chain([
            .contender(pid: them),
            .contender(pid: 300),
            .contender(pid: us),
        ]) == .precededBy(them))
    }
}

/// The seam that turns the chain into the line the menu shows.
@MainActor
struct MediaKeyChainSeamTests {

    private func notice(
        _ registry: MockEventTapRegistry,
        betterDisplayIsFeedingUs: Bool = false
    ) -> MediaKeyChainNotice {
        AppCore.mediaKeyChainNotice(
            registry: registry,
            ourPID: 100,
            betterDisplayIsFeedingUs: betterDisplayIsFeedingUs
        )
    }

    @Test func theAppAheadOfUsIsNamed() {
        let registry = MockEventTapRegistry(
            taps: [.contender(pid: 200), .contender(pid: 100)],
            names: [200: "Some Other App"],
            bundleIDs: [200: "com.example.other"]
        )
        #expect(notice(registry) == .anotherAppAhead("Some Other App"))
    }

    @Test func anUnnamedContenderIsNotAccused() {
        // A daemon with no localized name would surface as a blank or a bare pid;
        // silence beats an accusation the user cannot act on.
        let registry = MockEventTapRegistry(taps: [.contender(pid: 200), .contender(pid: 100)])
        #expect(notice(registry) == .quiet)
    }

    @Test func beingFirstSaysNothing() {
        let registry = MockEventTapRegistry(
            taps: [.contender(pid: 100), .contender(pid: 200)],
            names: [200: "Some Other App"],
            bundleIDs: [200: "com.example.other"]
        )
        #expect(notice(registry) == .quiet)
    }

    @Test func theNeighbourWeCanCooperateWithGetsTheActionableLine() {
        // Identified by bundle ID: the display name is localized and renamable,
        // and this line promises a specific setting exists to turn on.
        let registry = MockEventTapRegistry(
            taps: [.contender(pid: 200), .contender(pid: 100)],
            names: [200: "BetterDisplay"],
            bundleIDs: [200: BetterDisplayOSDSource.bundleID]
        )
        #expect(notice(registry) == .betterDisplayAheadAndSilent)
    }

    @Test func onceItReportsTheContentionIsTheArrangementNotAFault() {
        // Same chain as above — the neighbour still holds the keys — but now it
        // is feeding us, which is exactly what the previous line asked for.
        let registry = MockEventTapRegistry(
            taps: [.contender(pid: 200), .contender(pid: 100)],
            names: [200: "BetterDisplay"],
            bundleIDs: [200: BetterDisplayOSDSource.bundleID]
        )
        #expect(notice(registry, betterDisplayIsFeedingUs: true) == .drawingFromBetterDisplay)
    }

    @Test func aDeliveredPayloadOutranksTheChainReading() {
        // Even with nobody ahead of us: if the neighbour is reporting, that is
        // where the brightness bar comes from, and the menu says so.
        let registry = MockEventTapRegistry(taps: [.contender(pid: 100)])
        #expect(notice(registry, betterDisplayIsFeedingUs: true) == .drawingFromBetterDisplay)
    }
}

/// Two ways a neighbour listed ahead of us is innocent by the DOCUMENTED
/// pipeline, not by position — both of which the registry used to discard, so
/// both produced a false accusation against a named app.
///
/// This decision errs toward silence on purpose (`media-key-chain-contention`):
/// a missing line costs a diagnostic, a false line accuses somebody.
struct MediaKeyChainInnocenceTests {
    private let us: pid_t = 100
    private let them: pid_t = 200

    private func chain(_ entries: [EventTapEntry]) -> MediaKeyChain {
        MediaKeyChainReconciler.chain(
            ourPID: us,
            mask: MediaKeyTranslation.systemDefinedMask,
            in: entries
        )
    }

    @Test func anAnnotatedSessionTapIsBehindUsWhereverItIsLISTED() {
        // CGEventTapLocation is an ordered pipeline — HID, session, annotated
        // session (CGEventTypes.h) — so this one receives AFTER our session tap
        // no matter what index the registry hands it back at. It was being named
        // purely for being listed first.
        let downstream = EventTapEntry.contender(pid: them, atAnnotatedSessionLocation: true)
        #expect(chain([downstream, .contender(pid: us)]) == .ours)
    }

    @Test func aPerProcessTapOnlySeesItsOwnTarget() {
        // `processBeingTapped` is documented as "Zero if not a per-process tap",
        // and apps routinely tap themselves. Such a tap cannot be ahead of us
        // for the media keys whatever its mask says.
        let scoped = EventTapEntry.contender(pid: them, tapping: 999)
        #expect(chain([scoped, .contender(pid: us)]) == .ours)
        // Even at the HID point, which otherwise beats us unconditionally.
        let scopedHID = EventTapEntry.contender(pid: them, atHIDLocation: true, tapping: 999)
        #expect(chain([scopedHID, .contender(pid: us)]) == .ours)
    }

    @Test func aRealSessionWideRivalIsStillNamed() {
        // The clearing must not swallow the case the feature exists for.
        #expect(chain([.contender(pid: them), .contender(pid: us)]) == .precededBy(them))
    }
}
