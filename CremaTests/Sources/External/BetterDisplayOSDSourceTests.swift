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
        BetterDisplayOSDSource(isBuiltInDisplay: { $0 == 1 })
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

    @Test func theNameSubscribedToIsTheCurrentOneOnly() {
        // BetterDisplay 4.2.2+ publishes every OSD event under both the current
        // and the legacy prefix; observing both would double each one.
        #expect(BetterDisplayOSDSource.notificationName == "pro.betterdisplay.BetterDisplay.osd")
    }
}
