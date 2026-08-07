import AppKit
import Testing
@testable import Crema

/// The presence rule as a table written independently of the `&&` chain it
/// checks — the rule's own expression would agree with any mutation of itself.
struct LockWidgetPresenceTests {

    @Test func allThreeAreRequired() {
        #expect(LockWidgetPresence.shouldPresent(enabled: true, locked: true, spaceAvailable: true))
    }

    @Test func theFeatureBeingOffOutranksEverything() {
        // Opt-in, born off. Nothing may put a window over a lock screen the user
        // never asked us to draw on.
        #expect(!LockWidgetPresence.shouldPresent(enabled: false, locked: true, spaceAvailable: true))
    }

    @Test func anUnlockedScreenGetsNothing() {
        #expect(!LockWidgetPresence.shouldPresent(enabled: true, locked: false, spaceAvailable: true))
    }

    @Test func withoutTheSpaceThereIsNoPointAndRealHarm() {
        // The window would render at the default level: invisible under the
        // shield, and sitting on the desktop the moment the user unlocks.
        #expect(!LockWidgetPresence.shouldPresent(enabled: true, locked: true, spaceAvailable: false))
    }

    private struct Row {
        let enabled: Bool
        let locked: Bool
        let space: Bool
        let present: Bool
    }

    @Test func theWholeTruthTable() {
        let rows = [
            Row(enabled: true, locked: true, space: true, present: true),
            Row(enabled: false, locked: true, space: true, present: false),
            Row(enabled: true, locked: false, space: true, present: false),
            Row(enabled: true, locked: true, space: false, present: false),
            Row(enabled: false, locked: false, space: true, present: false),
            Row(enabled: false, locked: true, space: false, present: false),
            Row(enabled: true, locked: false, space: false, present: false),
            Row(enabled: false, locked: false, space: false, present: false),
        ]
        #expect(rows.count == 8)   // every combination, none skipped
        for row in rows {
            #expect(
                LockWidgetPresence.shouldPresent(
                    enabled: row.enabled, locked: row.locked, spaceAvailable: row.space
                ) == row.present,
                "enabled=\(row.enabled) locked=\(row.locked) space=\(row.space)"
            )
        }
    }
}

/// The mirror's guarded write. Not ceremony: the source polls on a 30 s tail
/// forever, and an unchanged write to an `@Observable` property still rebuilds
/// every view reading it.
@MainActor
struct LockScreenMirrorTests {

    @Test func itStartsUnlocked() {
        // The conservative default is the one that draws nothing. A mirror born
        // locked would flash the surface at launch on every machine.
        #expect(!LockScreenMirror().isLocked)
    }

    @Test func itCarriesTransitionsBothWays() {
        let mirror = LockScreenMirror()
        mirror.report(locked: true)
        #expect(mirror.isLocked)
        mirror.report(locked: false)
        #expect(!mirror.isLocked)
    }
}

/// The presenter's lifecycle, over a fake panel factory and a recording space —
/// no real window, no real WindowServer.
@MainActor
struct LockScreenPresenterLifecycleTests {

    /// Counts what the presenter asked for. The real factory returns a
    /// `LockScreenPanel`, which owns an NSPanel; a test that built one would be
    /// testing AppKit.
    @MainActor
    final class FactorySpy {
        private(set) var builds = 0
        var refuses = false

        func make(
            _ screen: NSScreen,
            _ coordinator: Coordinator,
            _ space: any RaisedSpace,
            _ lowPower: LowPowerModeMirror,
            _ artwork: LockArtworkResolver
        ) -> LockScreenPanel? {
            builds += 1
            guard !refuses else { return nil }
            return LockScreenPanel(
                screen: screen, coordinator: coordinator, space: space,
                lowPower: lowPower, artwork: artwork
            )
        }
    }

    private func makePresenter(
        enabled: Bool,
        mirror: LockScreenMirror,
        spy: FactorySpy,
        space: RecordingRaisedSpace = RecordingRaisedSpace()
    ) -> (LockScreenPresenter, CoordinatorHarness) {
        let harness = CoordinatorHarness()
        let presenter = LockScreenPresenter(
            coordinator: harness.coordinator,
            lock: mirror,
            space: space,
            lowPower: LowPowerModeMirror(),
            artwork: LockArtworkResolver(lookup: MockArtworkLookup(), enabled: false),
            enabled: enabled,
            makePanel: spy.make
        )
        return (presenter, harness)
    }

    @Test func anUnlockedStartBuildsNothing() {
        let mirror = LockScreenMirror()
        let spy = FactorySpy()
        let (presenter, _) = makePresenter(enabled: true, mirror: mirror, spy: spy)
        presenter.start()
        // No window at all during ordinary use: the surface is born on the lock,
        // not kept hidden behind it.
        #expect(spy.builds == 0)
    }

    @Test func startingAlreadyLockedBuildsImmediately() {
        // Launching (or enabling) while the screen is already locked is a real
        // path — a relaunch after a crash, or the login item on a locked Mac.
        let mirror = LockScreenMirror()
        mirror.report(locked: true)
        let spy = FactorySpy()
        let (presenter, _) = makePresenter(enabled: true, mirror: mirror, spy: spy)
        presenter.start()
        #expect(spy.builds == 1)
    }

    @Test func theFeatureBeingOffBuildsNothingEvenLocked() {
        let mirror = LockScreenMirror()
        mirror.report(locked: true)
        let spy = FactorySpy()
        let (presenter, _) = makePresenter(enabled: false, mirror: mirror, spy: spy)
        presenter.start()
        #expect(spy.builds == 0)
    }

    @Test func enablingWhileLockedBuildsWithoutWaitingForTheNextLock() {
        // The Settings toggle has to take effect now. Waiting for the next lock
        // cycle is the class of bug the "every control owes an onChange into the
        // core" rule exists to prevent.
        let mirror = LockScreenMirror()
        mirror.report(locked: true)
        let spy = FactorySpy()
        let (presenter, _) = makePresenter(enabled: false, mirror: mirror, spy: spy)
        presenter.start()
        #expect(spy.builds == 0)

        presenter.setEnabled(true)
        #expect(spy.builds == 1)
    }

    @Test func disablingWhileLockedTakesTheSurfaceDownAtOnce() {
        let mirror = LockScreenMirror()
        mirror.report(locked: true)
        let spy = FactorySpy()
        let (presenter, _) = makePresenter(enabled: true, mirror: mirror, spy: spy)
        presenter.start()
        #expect(spy.builds == 1)

        presenter.setEnabled(false)
        // Turning it off with the surface up must remove it, not leave it until
        // the next unlock.
        presenter.setEnabled(true)
        #expect(spy.builds == 2, "a second build proves the first surface was actually torn down")
    }

    @Test func anUnavailableSpaceNeverBuilds() {
        let mirror = LockScreenMirror()
        mirror.report(locked: true)
        let spy = FactorySpy()
        let (presenter, _) = makePresenter(
            enabled: true, mirror: mirror, spy: spy, space: RecordingRaisedSpace(isAvailable: false)
        )
        presenter.start()
        // The presence rule refuses before the factory is ever asked — the panel
        // has its own guard, but paying for a window to throw it away is waste.
        #expect(spy.builds == 0)
    }
}
