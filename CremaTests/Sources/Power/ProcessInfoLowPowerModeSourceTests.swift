import Foundation
import Testing
@testable import Crema

/// The real `ProcessInfoLowPowerModeSource`, driven over an injected
/// NotificationCenter and an injected read — no real power-state notification, no
/// real `ProcessInfo` reading, so a machine that plugs in mid-run cannot decide a
/// verdict here.
///
/// The edge is a trigger and never a value, exactly as in the screen-lock source:
/// `NSProcessInfoPowerStateDidChange` is posted for every power-source change —
/// battery to wall power and back — and not only when the Low Power switch moves,
/// so a source that flipped its own state on each edge would report Low Power to a
/// user who merely unplugged the charger. Each edge therefore re-reads the
/// authoritative state and emits WHAT IT READ.
///
/// Posting through a private center is also what pins the subscription itself: the
/// observer is installed unconditionally, so a name constant that no longer matches
/// what the tests post delivers nothing, `next()` times out to nil, and the
/// assertion right after fails with this test's name (asserting the constant would
/// have proved nothing about what was subscribed to).
///
/// Residual, stated so nobody reads more into the suite: the initialiser's default
/// center IS the production one, and nothing here pins WHICH center that is.
@MainActor
struct ProcessInfoLowPowerModeSourceTests {

    /// The authoritative power state the injected read reflects, plus a count of
    /// how often it was actually consulted — the discriminator between a genuine
    /// re-read and a re-emission of whatever the source already held.
    @MainActor
    final class PowerStateBox {
        var isLowPower: Bool
        private(set) var reads = 0

        init(_ isLowPower: Bool) { self.isLowPower = isLowPower }

        func read() -> Bool {
            reads += 1
            return isLowPower
        }
    }

    private func makeSource(_ box: PowerStateBox, center: NotificationCenter) -> ProcessInfoLowPowerModeSource {
        ProcessInfoLowPowerModeSource(center: center, read: { box.read() })
    }

    @Test func theSeedIsAnAuthoritativeReadNotAnAssumedFalse() {
        // A Mac launched ALREADY in Low Power Mode posts no notification, so the
        // launch reading is the only thing standing between that user and bars
        // that pulse until they toggle the system setting off and on again.
        let box = PowerStateBox(true)
        let source = makeSource(box, center: NotificationCenter())

        #expect(source.isLowPower)
        #expect(box.reads == 1, "the seed was assumed rather than read")

        withExtendedLifetime(source) {}
    }

    @Test func anEdgeReReadsTheAuthoritativeStateAndEmitsWhatItRead() async {
        let box = PowerStateBox(false)
        let center = NotificationCenter()
        let source = makeSource(box, center: center)
        let updates = BoundedStreamIterator(source.updates)
        #expect(!source.isLowPower)

        box.isLowPower = true
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)

        #expect(await updates.next() == true, "the power-state edge never produced a reading")
        #expect(source.isLowPower)
        #expect(box.reads == 2, "the edge emitted without consulting the authoritative state")

        withExtendedLifetime(source) {}
    }

    @Test func anEdgeNeverFlipsTheStateOnItsOwn() async {
        // The common edge in the field: the charger comes out, the notification
        // fires, and Low Power Mode has not moved at all. A source that toggled —
        // or that trusted the edge instead of the reading — would freeze the
        // waveform of everyone who unplugs their Mac.
        let box = PowerStateBox(true)
        let center = NotificationCenter()
        let source = makeSource(box, center: center)
        let updates = BoundedStreamIterator(source.updates)

        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)

        #expect(await updates.next() == true, "the edge emitted nothing at all")
        #expect(source.isLowPower)
        #expect(box.reads == 2, "the edge answered from memory instead of re-reading")

        withExtendedLifetime(source) {}
    }
}
