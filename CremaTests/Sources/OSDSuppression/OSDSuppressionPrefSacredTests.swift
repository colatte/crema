import Foundation
import Testing
@testable import Crema

/// The persisted opt-in is sacred — no failure path writes it (docs/DECISIONS.md:
/// pref-sacred). Each of the four documented triggers (throwing apply, failed
/// verification, unreadable read, deadline timeout) is fired through the real
/// suppressor wired the way AppCore wires it: the menu mirror on the escalation
/// hook first, the real lock controller over it. A failed apply suspends its own
/// domain; the channel then stays unreadable, so the recovery probe escalates the
/// domain through that hook to the menu — the furthest any failure travels — and
/// the opt-in is never WRITTEN on the way. Counted as writes, not read back as a
/// value: a path that rewrites the same `true` is still a path that owns the pref.
///
/// Not the shared OSDSuppressorLockHarness: it replaces the escalation hook with a
/// counter, so whatever production hangs on that hook never runs there.
@MainActor
struct OSDSuppressionPrefSacredTests {

    @Test func throwingApplyLeavesThePrefUntouched() async throws {
        let h = try ProductionWiredSuppression()
        h.screen.applyThrows = true
        h.keys.press(.screenBrightnessUp)

        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })
        #expect(h.suppressor.isEngaged)          // domain-scoped, not a global disengage
        h.screen.value = nil
        #expect(await h.escalates(.screenBrightness))
        #expect(h.prefWritesSinceOptIn == 0)     // pref never rewritten
        #expect(h.prefs.suppressesNativeOSD)
    }

    @Test func failedVerificationLeavesThePrefUntouched() async throws {
        let h = try ProductionWiredSuppression()
        h.volume.writeIsDead = true   // write "succeeds" but the value never moves
        h.keys.press(.volumeUp)

        #expect(await eventually { h.suppressor.suspendedDomains.contains(.volume) })
        h.volume.value = nil
        #expect(await h.escalates(.volume))
        #expect(h.prefWritesSinceOptIn == 0)
        #expect(h.prefs.suppressesNativeOSD)
        #expect(h.suppressor.isEngaged)
    }

    @Test func unreadableReadLeavesThePrefUntouched() async throws {
        let h = try ProductionWiredSuppression()
        h.keyboard.value = nil
        h.keys.press(.keyboardBrightnessUp)

        #expect(await eventually { h.suppressor.suspendedDomains.contains(.keyboardBrightness) })
        #expect(await h.escalates(.keyboardBrightness))
        #expect(h.prefWritesSinceOptIn == 0)
        #expect(h.prefs.suppressesNativeOSD)
    }

    @Test func deadlineTimeoutLeavesThePrefUntouched() async throws {
        let h = try ProductionWiredSuppression()
        h.screen.applyHangs = true
        h.keys.press(.screenBrightnessUp)
        await h.clock.waitForSleep(delay: OSDTest.deadline)
        h.clock.advance(delay: OSDTest.deadline)

        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })
        h.screen.value = nil
        #expect(await h.escalates(.screenBrightness))
        #expect(h.prefWritesSinceOptIn == 0)
        #expect(h.prefs.suppressesNativeOSD)
        #expect(h.suppressor.isEngaged)
    }
}

/// The suppressor in AppCore's order: mirror wired to the escalation hook, then
/// the lock controller built and started over the opted-in preferences.
@MainActor
private final class ProductionWiredSuppression {
    let keys = MockMediaKeyConsuming()
    let volume = MockOSDVolumeChannel()
    let screen = MockOSDChannel()
    let keyboard = MockOSDChannel()
    /// Probe backoff and write deadline; reads sleep on `readClock`, never
    /// advanced, so a probe's read never times out under the hammer below.
    let clock = TestSleepClock()
    let readClock = TestSleepClock()
    let lock = MockScreenLockSource(safe: true)
    let ephemeral = EphemeralDefaults()
    let defaults: WriteCountingDefaults
    let prefs: Preferences
    let monitor = OSDSuppressionMonitor()
    let suppressor: MediaKeyInterceptionOSDSuppressor
    let controller: SuppressionLockController
    private let optInWrites: Int

    init() throws {
        defaults = try #require(WriteCountingDefaults(suiteName: ephemeral.suiteName))
        prefs = Preferences(defaults: defaults)
        prefs.suppressesNativeOSD = true
        suppressor = MediaKeyInterceptionOSDSuppressor(
            keys: keys, volume: volume, screen: screen, keyboard: keyboard,
            screenBrightnessTarget: { .builtIn },
            clock: clock, readClock: readClock
        )
        AppCore.wireSuspensionMirror(from: suppressor, to: monitor)
        controller = SuppressionLockController(suppressor: suppressor, lockSource: lock, preferences: prefs)
        controller.start()
        optInWrites = defaults.writes(forKey: Preferences.suppressesNativeOSDKey)
    }

    /// Writes of the opt-in after the user's own, the one this setup made.
    var prefWritesSinceOptIn: Int {
        defaults.writes(forKey: Preferences.suppressesNativeOSDKey) - optInWrites
    }

    /// Runs the backoff, one parked probe at a time, until the probe, failing on
    /// every read, escalates the domain to the menu through the wired hook.
    func escalates(_ domain: OSDSuppressionDomain) async -> Bool {
        for _ in 0...OSDTest.escalation {
            if monitor.longSuspendedDomains.contains(domain) { return true }
            await clock.waitForSleep()   // the probe's backoff is parked
            clock.advance()
        }
        return await eventually { monitor.longSuspendedDomains.contains(domain) }
    }
}

/// UserDefaults that counts every write per key, so a test can tell "never
/// written" apart from "written back to the same value".
private final class WriteCountingDefaults: UserDefaults {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func writes(forKey key: String) -> Int { lock.withLock { counts[key, default: 0] } }

    override func set(_ value: Any?, forKey defaultName: String) {
        note(defaultName)
        super.set(value, forKey: defaultName)
    }

    override func set(_ value: Bool, forKey defaultName: String) {
        note(defaultName)
        super.set(value, forKey: defaultName)
    }

    override func removeObject(forKey defaultName: String) {
        note(defaultName)
        super.removeObject(forKey: defaultName)
    }

    private func note(_ key: String) { lock.withLock { counts[key, default: 0] += 1 } }
}
