import Testing
@testable import Crema

/// The border that carries BetterDisplay's OSD notification into the domain
/// stream. The real DistributedNotificationCenter never enters a test — the
/// source takes a resolver, and a payload is fed the way one would arrive.
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
        BetterDisplayOSDSource(target: { $0 == 1 ? .builtIn : nil })
    }

    @Test func aDeliveredPayloadBecomesAHUDOnTheStream() async {
        let source = makeSource()
        let collector = Collector(source.updates)
        defer { collector.stop() }

        source.handle(json: #"{"controlTarget":"combinedBrightness","displayID":1,"maxValue":64,"systemIconID":1,"value":48}"#)

        #expect(await eventually { collector.values.count == 1 })
        #expect(collector.values.first?.kind == .screenBrightness)
        #expect(collector.values.first?.value == 0.75)
        #expect(collector.values.first?.display == nil)
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

    @Test func aReportedLevelTellsTheKeyDrivenSourceToStandDown() {
        // Suppression off: Crema's tap observed the key and armed the polled
        // source, but the neighbour is the one applying and reporting. Without
        // this hand-off both draw for one press.
        var standDowns = 0
        let source = BetterDisplayOSDSource(target: { $0 == 1 ? .builtIn : nil }, onReport: { standDowns += 1 })

        source.handle(json: #"{"controlTarget":"combinedBrightness","maxValue":64,"value":32}"#)
        source.handle(json: #"{"controlTarget":"contrast","maxValue":64,"value":32}"#)   // not ours

        #expect(standDowns == 1)
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

    @Test func theNameSubscribedToIsTheCurrentOneOnly() {
        // BetterDisplay 4.2.2+ publishes every OSD event under both the current
        // and the legacy prefix; observing both would double each one.
        #expect(BetterDisplayOSDSource.notificationName == "pro.betterdisplay.BetterDisplay.osd")
    }
}
