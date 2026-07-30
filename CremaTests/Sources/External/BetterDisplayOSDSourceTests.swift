import Foundation
import Testing
@testable import Crema

/// The border that carries BetterDisplay's OSD notification into the domain
/// stream. The real DistributedNotificationCenter never enters a test — the
/// source takes a resolver, and a payload is fed the way one would arrive.
///
/// Which means the PRODUCTION resolver (`resolveTarget`) is not exercised here, and
/// a mutation re-adding a branch to it survives this suite. That is deliberate
/// rather than a hole to plug: it enumerates displays through CoreGraphics, which a
/// unit test may not touch, and after the scoping fix it makes no decision left to
/// pin — it is one call to `ScreenTranslation.displayUUID(for:)`. The decision that
/// used to live there was `CGDisplayIsBuiltin` collapsing the built-in into "no
/// display named", and that is exactly the bug the field found: the bar drawn on
/// every panel instead of the one the neighbour named.
@MainActor
struct BetterDisplayOSDSourceTests {

    @MainActor
    final class Collector {
        private(set) var values: [SystemHUD] = []
        private var task: Task<Void, Never>?
        init(_ stream: AsyncStream<SystemHUD>) {
            task = Task { @MainActor [weak self] in
                for await value in stream { self?.values.append(value) }
            }
        }

        func stop() { task?.cancel(); task = nil }
    }

    private func makeSource() -> BetterDisplayOSDSource {
        BetterDisplayOSDSource(target: { $0 == 1 ? .display(DisplayUUID(rawValue: "BUILT-IN")) : nil })
    }

    @Test func aDeliveredPayloadBecomesAHUDOnTheStream() async {
        let source = makeSource()
        let collector = Collector(source.updates)
        defer { collector.stop() }

        source.handle(json: #"{"controlTarget":"combinedBrightness","displayID":1,"maxValue":64,"systemIconID":1,"value":48}"#)

        #expect(await eventually { collector.values.count == 1 })
        #expect(collector.values.first?.kind == .screenBrightness)
        #expect(collector.values.first?.value == 0.75)
        #expect(collector.values.first?.display == DisplayUUID(rawValue: "BUILT-IN"))
    }

    @Test func aPayloadWithNoHUDOfOursNeverReachesTheStream() async {
        let source = makeSource()
        let collector = Collector(source.updates)
        defer { collector.stop() }

        source.handle(json: #"{"controlTarget":"volume","systemIconID":3,"maxValue":100,"value":50}"#)
        source.handle(json: #"{"controlTarget":"contrast","maxValue":64,"value":10}"#)
        source.handle(json: "garbage")
        // One good payload after the rejects proves the source stayed alive
        // rather than merely staying quiet.
        source.handle(json: #"{"controlTarget":"combinedBrightness","maxValue":64,"value":64}"#)

        #expect(await eventually { collector.values.count == 1 })
        #expect(collector.values.map(\.value) == [1])
    }

    @Test func aReportedLevelSilencesTheKeyDrivenSourceForThatPress() async {
        // Suppression off: Crema's tap OBSERVED the key and armed the polled
        // source, and the neighbour is the one that applies and reports. Without
        // the hand-off both draw for one press — and the polled one, arriving
        // later on the hardware scale, wins the bar with the wrong number.
        //
        // Asserted through the polled source's own stream rather than through a
        // call count: counting the closure only proves the closure was called,
        // which is true even when `standDown()` does nothing at all (its
        // protocol default is a no-op, so gutting the real one is not even a
        // compile error).
        let backend = FakeBrightnessBackend(value: 0.5)
        let clock = TestSleepClock()
        let polled = PolledBrightnessSource(
            kind: .screenBrightness, backend: backend, clock: clock, pollInterval: 0.5
        )
        let collector = Collector(polled.updates)
        defer { collector.stop() }

        let source = BetterDisplayOSDSource(
            target: { $0 == 1 ? .display(DisplayUUID(rawValue: "BUILT-IN")) : nil },
            onReport: { polled.standDown() }
        )

        polled.sample()                 // the observed key arms the window
        await clock.waitForSleep()
        source.handle(json: #"{"controlTarget":"combinedBrightness","maxValue":64,"value":32}"#)

        // The neighbour applied it: the hardware value moves a beat later, and
        // the armed poll would emit it on top of the bar already drawn.
        backend.value = 0.34
        clock.advance()
        await clock.waitForSleep()

        #expect(collector.values.isEmpty)
    }

    @Test func aReportedLevelAlsoSilencesTheKeysOwnReadingStillInFlight() async {
        // The same press as above, but the reading the key asked for is still in
        // flight when the neighbour reports — reachable because that reading no
        // longer runs on the caller's thread (a blocking private-API read must
        // never land there). A key-driven reading emits on any change, window or
        // not, so ordering alone stopped protecting this press: it has to come back
        // knowing it was spoken for, or it draws our hardware-scale bar on top of
        // the neighbour's — the exact double bar standDown exists to prevent
        // (docs/DECISIONS.md: betterdisplay-osd-source).
        let backend = FakeBrightnessBackend(value: 0.5)
        let clock = TestSleepClock()
        let polled = PolledBrightnessSource(
            kind: .screenBrightness, backend: backend, clock: clock, pollInterval: 0.5
        )
        let collector = Collector(polled.updates)
        defer { collector.stop() }

        let source = BetterDisplayOSDSource(
            target: { $0 == 1 ? .display(DisplayUUID(rawValue: "BUILT-IN")) : nil },
            onReport: { polled.standDown() }
        )

        let held = DispatchSemaphore(value: 0)
        backend.readGate = held
        defer { backend.readGate = nil; held.signal() }

        let started = backend.readsStarted
        let taken = backend.readCount
        polled.sample()                 // the observed key: its reading parks
        #expect(await backend.awaitReadStarted(after: started))

        source.handle(json: #"{"controlTarget":"combinedBrightness","maxValue":64,"value":32}"#)
        backend.value = 0.34            // the neighbour applied: the hardware moves

        backend.readGate = nil
        held.signal()                   // the key's reading returns now, seeing 0.34
        #expect(await backend.awaitRead(after: taken))

        // Proven by what comes next rather than by silence alone: a fresh key the
        // source can see must be the FIRST thing the stream ever yields — had the
        // spoken-for reading emitted, it would sit ahead of it.
        backend.value = 0.42
        polled.sample()
        #expect(await eventually { collector.values.count == 1 })
        #expect(collector.values.map(\.value) == [BrightnessConversion.normalize(0.42)])
    }

    @Test func onlyADeliveredPayloadCountsAsAWorkingIntegration() {
        // Presence of the app proves nothing: its OSD notification setting can be
        // off with BetterDisplay running, so the menu must not claim otherwise.
        let source = makeSource()
        #expect(!source.hasReported)

        source.handle(json: #"{"controlTarget":"contrast","maxValue":64,"value":32}"#)
        #expect(!source.hasReported)                     // arrived, but not ours to draw

        source.handle(json: #"{"controlTarget":"combinedBrightness","maxValue":64,"value":32}"#)
        #expect(source.hasReported)

        source.noteBetterDisplayTerminated()
        #expect(!source.hasReported)                     // the claim never outlives its source
    }

    /// The observer wired the way production wires it, driven by a real
    /// distributed notification.
    ///
    /// Asserting the name CONSTANT proves nothing about what the observer
    /// actually subscribed to — a mutation pointing it at the legacy prefix left
    /// the constant right, the suite green, and the integration deaf. And this is
    /// the one border where a wrong subscription is invisible from inside: the
    /// app cannot tell "nobody posted" from "we are not listening", which is
    /// exactly how two probe rounds were lost to a wildcard observer macOS never
    /// delivers.
    @Test func theInstalledObserverReceivesWhatBetterDisplayActuallyPosts() async {
        let source = BetterDisplayOSDSource()   // no injection: the real observer
        let collector = Collector(source.updates)
        defer { collector.stop() }

        // No displayID: the built-in screen, so this holds on any machine.
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(BetterDisplayOSDSource.notificationName),
            object: #"{"controlTarget":"combinedBrightness","maxValue":64,"value":16}"#,
            userInfo: nil,
            deliverImmediately: true
        )

        #expect(await eventually { collector.values.count == 1 })
        #expect(collector.values.first?.value == 0.25)
        #expect(collector.values.first?.authority == .betterDisplay)
    }

    @Test func theNameSubscribedToIsTheCurrentOneOnly() {
        // BetterDisplay 4.2.2+ publishes every OSD event under both the current
        // and the legacy prefix; observing both would double each one.
        #expect(BetterDisplayOSDSource.notificationName == "pro.betterdisplay.BetterDisplay.osd")
    }
}
