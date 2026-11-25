import Testing
@testable import Crema

/// A device that takes the write and publishes it late must not be treated as
/// one that refused it.
///
/// Apple documents the delay as the general case, not an exotic device:
/// `AudioObjectSetPropertyData` — "the value of the property should not be
/// considered changed until the HAL has called the listeners as many properties
/// values are changed asynchronously" (AudioHardware.h:302). An apply cycle that
/// reads back on the very next line takes an unmoved value for a failed write:
/// the domain suspends, the keys go back to the system, and the menu tells the
/// user Crema cannot change a volume it has just changed.
@MainActor
struct OSDLateWritePublicationTests {

    @Test func aWritePublishedOnTheSecondReadIsNotAFailure() async {
        let h = OSDSuppressorHarness()
        // The write lands; only the FIRST read-back still shows the old value.
        h.screen.publishesWriteLate = true

        // `onApplied` fires ONLY for a verified apply, which is the positive
        // signal this test needs. Waiting on `applied` instead would prove
        // nothing: the channel records the write BEFORE the read-back runs, so
        // the "not suspended" assertion would land before the verification it
        // is about — and a mutation that removes the second read would then
        // fail to turn this red.
        let verified = CounterBox()
        h.suppressor.onApplied = { _ in verified.count += 1 }
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { verified.count == 1 })
        #expect(h.screen.applied == [0.5 + OSDTest.step])
        // The whole point: no suspension, no handback, no menu warning.
        #expect(!h.suppressor.suspendedDomains.contains(.screenBrightness))
        #expect(h.suppressor.isEngaged)
    }

    @Test func aWriteThatNeverLandsStillSuspends() async {
        // The clearing must not launder a genuinely dead write. `writeIsDead`
        // leaves the value untouched forever, so the second read agrees with the
        // first and the failure survives — which is what keeps the second look
        // from being a way to stop noticing.
        let h = OSDSuppressorHarness()
        h.screen.writeIsDead = true
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })
    }
}

/// Proves the double models what it claims, independently of the suppressor —
/// a test double that silently does nothing makes every test above vacuous.
@MainActor
struct LateWriteDoubleTests {
    @Test func theFirstReadBackShowsTheOldValueAndTheSecondTheNew() async throws {
        let channel = MockOSDChannel()
        channel.value = 0.5
        channel.publishesWriteLate = true
        try await channel.apply(0.5625)
        #expect(channel.read() == 0.5, "the first read-back must still show the pre-write value")
        #expect(channel.read() == 0.5625, "the second must show the write")
    }
}
