import Testing
@testable import Crema

/// The origin gate shared by both brightness HUD sources: a key change shows a
/// HUD, a sensor change (a poll with no recent key) does not. Pure and
/// deterministic — the source-level tests only prove the wiring.
///
/// `register` mutates, so each call is bound to a local before `#expect` (the
/// macro would otherwise capture the gate immutably).
///
/// Arming is its own call (`armKeyWindow()`, at key time on the key's thread)
/// because the reading it explains comes back later, off that thread. So the
/// tests about the WINDOW arm explicitly, and the ones about the keyDriven leg
/// alone — a changed key reading, the boundary refresh, de-dup — deliberately do
/// not: those must hold with no window open, or the two legs get silently welded
/// together.
struct KeyOriginBrightnessGateTests {

    @Test func aKeyDrivenReadingDoesNotArmTheWindowByItself() {
        // Recording is not arming. The window has to be stamped when the KEY
        // arrives, because the reading it explains comes back later from the
        // border's serial queue — a blocking private-API read never runs on the
        // caller's thread. If registering armed too, the window would start when
        // the read RETURNED, and a poll inside that shifted window would be read
        // as the user's press.
        var g = gate()
        let atKey = g.register(0.5, keyDriven: true)      // no window opened
        let atPoll = g.register(0.8, keyDriven: false)    // so this is a sensor
        #expect(!atKey)
        #expect(!atPoll)
    }

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
        g.armKeyWindow()                                  // the key arrived: window opens now
        let atKey = g.register(0.5, keyDriven: true)      // key observed, not applied yet
        let atPoll = g.register(0.8, keyDriven: false)    // applied, armed
        #expect(!atKey)
        #expect(atPoll)
    }

    @Test func standingDownSpendsTheWindowSoTheOtherAuthoritysReadingStands() {
        // The same suppression-off timing as above, but the key travelled on to a
        // neighbour that applies AND reports the change itself. This source must
        // not add its own reading on top: the two measure different things, and
        // the later one would win the HUD.
        var g = gate()
        g.armKeyWindow()                                  // the key arrived
        let atKey = g.register(0.5, keyDriven: true)
        g.standDown()                                     // the neighbour reported: spend it
        let atPoll = g.register(0.8, keyDriven: false)
        #expect(!atKey)
        #expect(!atPoll)
    }

    @Test func standingDownDoesNotDeafenTheNextKey() {
        var g = gate()
        g.standDown()
        let emitted = g.register(0.8, keyDriven: true)
        #expect(emitted)
    }

    @Test func aPollChangeAfterTheWindowExpiresIsSilent() {
        let now = ManualNow()
        var g = gate(now: now)
        g.armKeyWindow()                                  // arms until now + 1.5
        let atKey = g.register(0.5, keyDriven: true)
        now.advance(by: 2)
        let atPoll = g.register(0.8, keyDriven: false)    // window passed → sensor
        #expect(!atKey)
        #expect(!atPoll)
    }

    @Test func anEmitConsumesTheWindow() {
        var g = gate()
        g.armKeyWindow()
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
        g.armKeyWindow()                                  // the key arrived
        let atKey = g.register(0.5, keyDriven: true)      // no-op key: nothing to show
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

    @Test func aKeyDrivenNoOpAtTheMaxBoundaryStillEmits() {
        // Suppression-on, brightness pinned at max: the consumed key clamps to
        // 1.0 == before, but native flashes the full bar, so the key-driven
        // refresh emits even though the value did not move.
        var g = gate(baseline: 1.0)
        let emitted = g.register(1.0, keyDriven: true)
        #expect(emitted)
    }

    @Test func aKeyDrivenNoOpAtTheMinBoundaryStillEmits() {
        var g = gate(baseline: 0.0)
        let emitted = g.register(0.0, keyDriven: true)
        #expect(emitted)
    }

    @Test func aPollNoOpAtTheBoundaryStaysSilent() {
        // The ambient-sensor protection is pinned: a pure poll at a boundary
        // with an unchanged value never emits — only a key-driven read refreshes.
        var g = gate(baseline: 1.0)
        let emitted = g.register(1.0, keyDriven: false)
        #expect(!emitted)
    }

    @Test func aKeyDrivenNoOpMidScaleStaysSilent() {
        // Only the boundaries get the unchanged-value refresh: mid-scale the step
        // always moves the value, so an unchanged key read there is a redundant
        // poke and de-dups.
        var g = gate(baseline: 0.5)
        let emitted = g.register(0.5, keyDriven: true)
        #expect(!emitted)
    }

    @Test func aBoundaryBaselineFirstReadingStillBaselinesSilently() {
        // The launch value at a boundary baselines without emitting (previous is
        // nil); the boundary refresh needs a prior reading to compare against.
        var g = gate(baseline: nil)
        let baseline = g.register(1.0, keyDriven: true)
        let repress = g.register(1.0, keyDriven: true)
        #expect(!baseline)
        #expect(repress)
    }

    @Test func aNilBaselineFirstReadingIsSilent() {
        var g = gate(baseline: nil)
        let baseline = g.register(0.5, keyDriven: true)   // baselines without emitting
        let change = g.register(0.8, keyDriven: true)
        #expect(!baseline)
        #expect(change)
    }
}
