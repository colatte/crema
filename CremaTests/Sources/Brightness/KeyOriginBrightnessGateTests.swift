import Testing
@testable import Crema

/// The origin gate shared by both brightness HUD sources: a key change shows a
/// HUD, a sensor change (a poll with no recent key) does not. Pure and
/// deterministic — the source-level tests only prove the wiring.
///
/// `register` mutates, so each call is bound to a local before `#expect` (the
/// macro would otherwise capture the gate immutably).
struct KeyOriginBrightnessGateTests {

    private func gate(baseline: Double? = 0.5, window: Double = 1.5, now: ManualNow = ManualNow()) -> KeyOriginBrightnessGate {
        KeyOriginBrightnessGate(window: window, now: { now.now }, baseline: baseline)
    }

    @Test func aKeyDrivenChangeEmits() {
        var g = gate()
        let emitted = g.register(0.8, keyDriven: true)
        #expect(emitted)
    }

    @Test func aPollChangeWithNoKeyIsSilent() {
        var g = gate()
        let emitted = g.register(0.8, keyDriven: false)   // the sensor
        #expect(!emitted)
    }

    @Test func aPollChangeInsideTheArmedWindowEmits() {
        // Suppression-off timing: the key arms before the value applies, so the
        // key read finds no change; the poll a beat later, still armed, emits.
        var g = gate()
        let atKey = g.register(0.5, keyDriven: true)      // key observed, not applied yet
        let atPoll = g.register(0.8, keyDriven: false)    // applied, armed
        #expect(!atKey)
        #expect(atPoll)
    }

    @Test func aPollChangeAfterTheWindowExpiresIsSilent() {
        let now = ManualNow()
        var g = gate(now: now)
        let atKey = g.register(0.5, keyDriven: true)      // arms until now + 1.5
        now.advance(by: 2)
        let atPoll = g.register(0.8, keyDriven: false)    // window passed → sensor
        #expect(!atKey)
        #expect(!atPoll)
    }

    @Test func anEmitConsumesTheWindow() {
        var g = gate()
        let atKey = g.register(0.8, keyDriven: true)      // key HUD, window consumed
        let inTail = g.register(0.6, keyDriven: false)    // sensor in the tail → silent
        #expect(atKey)
        #expect(!inTail)
    }

    @Test func aNoOpKeyLeaksAtMostOneSensorChange() {
        // A key that changes nothing still arms (indistinguishable from a key
        // whose value has not applied); one following sensor change leaks, then
        // the emit consumes the window.
        var g = gate()
        let atKey = g.register(0.5, keyDriven: true)      // no-op key: arms only
        let leak = g.register(0.4, keyDriven: false)      // the one bounded leak
        let after = g.register(0.3, keyDriven: false)     // window consumed → silent
        #expect(!atKey)
        #expect(leak)
        #expect(!after)
    }

    @Test func aRedundantValueDoesNotEmit() {
        var g = gate()
        let first = g.register(0.8, keyDriven: true)
        let repeated = g.register(0.8, keyDriven: true)   // de-dup
        #expect(first)
        #expect(!repeated)
    }

    @Test func aNilBaselineFirstReadingIsSilent() {
        var g = gate(baseline: nil)
        let baseline = g.register(0.5, keyDriven: true)   // baselines without emitting
        let change = g.register(0.8, keyDriven: true)
        #expect(!baseline)
        #expect(change)
    }
}
