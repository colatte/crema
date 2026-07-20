import Testing
@testable import Crema

/// The settle re-read fix for H-CONSUMER-NIL, driven through the REAL
/// `DistributedNotificationScreenLockSource` over an injected session reader and
/// an injected clock — no real CoreGraphics lock APIs, no real notifications.
///
/// The bug: on a plain unlock there is a single `screenIsUnlocked` edge; if its
/// authoritative re-read catches a still-transiently-locked session dictionary,
/// the reconciler deduplicates the return-to-safe (it matches the last emitted
/// state) and, with no later edge, the source stays latched at `unsafe` forever.
/// Downstream that strands the suppressor disengaged: the tap observes every key
/// (Crema HUD) but never swallows (native OSD too), permanently, across all
/// domains, until a clean lock cycle or relaunch.
///
/// The fix: `handleEdge` reconciles the edge immediately AND schedules a short
/// backoff of extra authoritative re-reads. A re-read that sees the settled
/// truth emits the transition the stale edge missed; a re-read that confirms the
/// current truth is deduped (silent). These tests inject an edge by calling
/// `handleEdge()` directly (what a delivered notification does) and control the
/// session reading through the box, so the race is deterministic.
@MainActor
struct DistributedNotificationScreenLockSourceTests {

    /// Mutable session state the injected reader reflects — a test flips these to
    /// model the dictionary settling between the edge and a settle re-read.
    @MainActor
    final class SessionBox {
        var locked: Bool
        var onConsole: Bool
        init(locked: Bool, onConsole: Bool) {
            self.locked = locked
            self.onConsole = onConsole
        }
    }

    /// Collects everything the source emits on `updates` — the stream the
    /// controller consumes, so proving the transition reaches it is the point.
    @MainActor
    final class EmitCollector {
        private(set) var values: [Bool] = []
        private var task: Task<Void, Never>?
        init(_ stream: AsyncStream<Bool>) {
            task = Task { @MainActor [weak self] in
                for await value in stream { self?.values.append(value) }
            }
        }

        func stop() { task?.cancel(); task = nil }
    }

    @MainActor
    private func makeSource(_ box: SessionBox, clock: TestSleepClock)
    -> DistributedNotificationScreenLockSource {
        DistributedNotificationScreenLockSource(
            clock: clock,
            sessionReader: { (locked: box.locked, onConsole: box.onConsole) }
        )
    }

    // MARK: - The fix, in isolation

    /// The cravado race: the single unlock edge re-reads a still-locked session
    /// (deduped, no emit), and only the delayed settle re-read — after the dict
    /// settles to unlocked — emits the return-to-safe the edge missed.
    @Test func staleUnlockReadIsCorrectedByASettleReRead() async {
        let box = SessionBox(locked: false, onConsole: true)   // safe at launch
        let clock = TestSleepClock()
        let source = makeSource(box, clock: clock)
        let emit = EmitCollector(source.updates)

        // Lock: the edge reads locked → emit unsafe.
        box.locked = true
        source.handleEdge()
        #expect(await eventually { emit.values == [false] })
        #expect(!source.isSuppressionSafe)

        // Unlock, but the session dict has NOT settled yet — the edge still reads
        // locked, so the reconciler dedups and nothing emits.
        source.handleEdge()
        await settle()
        #expect(emit.values == [false])          // still no return-to-safe
        #expect(!source.isSuppressionSafe)

        // The dict settles to unlocked, and the settle re-read fires: it sees the
        // truth the edge missed and emits the return-to-safe. This is the fix.
        box.locked = false
        #expect(await eventually {
            clock.advance()
            return source.isSuppressionSafe
        })
        #expect(await eventually { emit.values == [false, true] })

        emit.stop()
        withExtendedLifetime(source) {}
    }

    /// The determinism guarantee: a skew that outlasts the finite backoff still
    /// recovers via the slow unbounded tail. Every backoff re-read (and the first
    /// tail reads) catch a still-locked dictionary — deduped, exactly the latch
    /// the finite backoff cannot break on its own — yet once the dictionary
    /// finally settles, a later tail read emits the return-to-safe the edge and
    /// the whole backoff missed. Pins that closure is deterministic, not just
    /// probable; a future shrink of the backoff or a real long skew would fail
    /// here instead of silently re-latching unsafe forever.
    @Test func skewBeyondTheFiniteBackoffStillRecoversViaTheTail() async {
        let box = SessionBox(locked: false, onConsole: true)   // safe at launch
        let clock = TestSleepClock()
        let source = makeSource(box, clock: clock)
        let emit = EmitCollector(source.updates)

        // Lock: the edge reads locked → emit unsafe.
        box.locked = true
        source.handleEdge()
        #expect(await eventually { emit.values == [false] })
        #expect(!source.isSuppressionSafe)

        // Unlock, but the session dict stays stale (still locked) far past the
        // finite backoff. Draining well beyond the three backoff delays exhausts
        // it and parks on the tail; every re-read is deduped, so the source stays
        // latched at unsafe — precisely the residual latch the tail must break.
        source.handleEdge()
        for _ in 0..<8 {
            clock.advance()
            await settle()
        }
        #expect(emit.values == [false])          // backoff exhausted, still no recovery
        #expect(!source.isSuppressionSafe)

        // The dict finally settles to unlocked, beyond the backoff window. The
        // next tail re-read sees the truth and emits the return-to-safe.
        box.locked = false
        #expect(await eventually {
            clock.advance()
            return source.isSuppressionSafe
        }, "the tail never re-read after the finite backoff — closure is not deterministic")
        #expect(await eventually { emit.values == [false, true] })

        emit.stop()
        withExtendedLifetime(source) {}
    }

    /// A steady state must stay silent: a spurious edge that re-reads the same
    /// truth, plus its whole settle chain, emit nothing (the reconciler dedups
    /// every re-read). This pins that the settle re-reads never manufacture a
    /// spurious flip.
    @Test func steadyStateEdgeAndSettleReReadsEmitNothing() async {
        let box = SessionBox(locked: false, onConsole: true)   // safe
        let clock = TestSleepClock()
        let source = makeSource(box, clock: clock)
        let emit = EmitCollector(source.updates)

        source.handleEdge()                       // a redundant safe edge
        for _ in 0..<6 {                          // drain the whole settle chain
            clock.advance()
            await settle()
        }
        #expect(emit.values.isEmpty)
        #expect(source.isSuppressionSafe)

        emit.stop()
        withExtendedLifetime(source) {}
    }

    /// A settle chain is restarted per edge, never stacked: after two rapid edges
    /// exactly one re-read chain is parked (the latest), so rapid lock→unlock
    /// bursts cannot pile up tasks.
    @Test func eachEdgeRestartsTheSettleChainWithoutStacking() async {
        let box = SessionBox(locked: false, onConsole: true)
        let clock = TestSleepClock()
        let source = makeSource(box, clock: clock)
        let emit = EmitCollector(source.updates)

        box.locked = true
        source.handleEdge()                       // lock edge → settle chain #1
        await clock.waitForSleep()
        box.locked = false
        source.handleEdge()                       // unlock edge → cancels #1, starts #2
        await clock.waitForSleep()
        #expect(clock.pendingSleeps == 1)         // only the latest chain is parked

        emit.stop()
        withExtendedLifetime(source) {}
    }

    // MARK: - End-to-end: the orphaned consumer is recovered

    /// The whole seam, the way the composition root joins it: a real tap source
    /// over an injectable tap border, the real suppressor, the real lock
    /// controller over the REAL lock source (injected reader/clock), and
    /// `AppCore.wireUnlockReinstall`. A stale unlock read that used to strand the
    /// consumer nil forever now recovers: the source's settle re-read emits the
    /// return-to-safe, the controller reinstalls + re-engages, and the tap
    /// swallows again. This is the pin that the orphan-consumer path is closed.
    @Test func staleUnlockReadRecoversTheConsumerEndToEnd() async {
        let ops = InjectableEventTapOperating()
        let tapClock = TestSleepClock()
        let source = CGEventTapMediaKeySource(
            permission: MockAccessibilityPermission(granted: true),
            clock: tapClock,
            tapOps: ops
        )
        await tapClock.waitForSleep()             // installed and parked on the poll

        let volume = MockOSDVolumeChannel()
        let screen = MockOSDChannel()
        let keyboard = MockOSDChannel()
        let suppressor = MediaKeyInterceptionOSDSuppressor(
            keys: source, volume: volume, screen: screen, keyboard: keyboard,
            clock: TestSleepClock(), readClock: TestSleepClock()
        )

        let box = SessionBox(locked: false, onConsole: true)   // safe at launch
        let lockClock = TestSleepClock()
        let lockSource = DistributedNotificationScreenLockSource(
            clock: lockClock,
            sessionReader: { (locked: box.locked, onConsole: box.onConsole) }
        )

        let defaults = EphemeralDefaults()
        let prefs = Preferences(defaults: defaults.defaults)
        prefs.suppressesNativeOSD = true
        let controller = SuppressionLockController(
            suppressor: suppressor, lockSource: lockSource, preferences: prefs
        )
        AppCore.wireUnlockReinstall(from: controller, to: source)
        controller.start()
        await settle()

        // Baseline: engaged and swallowing.
        #expect(suppressor.isEngaged)
        #expect(pressVolumeDown(ops) == true)

        // Lock (display sleep): disengage, consumer nil, keys pass through.
        box.locked = true
        lockSource.handleEdge()
        #expect(await eventually { !suppressor.isEngaged })
        #expect(pressVolumeDown(ops) == false)    // native OSD while locked

        // Physical wake reinstalls the tap (what AppCore's wake observers call);
        // the consumer is nil, and the reinstall cannot restore it on its own.
        source.reinstallTap()

        // Unlock, but the session dict is STALE (still locked): the edge dedups,
        // nothing re-engages yet — this is exactly where the bug latched forever.
        lockSource.handleEdge()
        await settle()
        #expect(!suppressor.isEngaged)
        #expect(pressVolumeDown(ops) == false)

        // The dict settles: the settle re-read emits the return-to-safe, the
        // controller reinstalls + re-engages, and the tap swallows again.
        box.locked = false
        #expect(await eventually {
            lockClock.advance()
            return suppressor.isEngaged
        }, "the stale unlock read never recovered — consumer stranded nil")
        #expect(pressVolumeDown(ops) == true)     // consuming again
        #expect(suppressor.suspendedDomains.isEmpty)

        controller.stop()
        withExtendedLifetime((source, lockSource)) {}
    }
}

/// data1 for a volume-down press: NX_KEYTYPE_SOUND_DOWN (1) in the high word,
/// 0x0A down / 0x0B up in the second byte (mirrors the repro suite's builder).
@MainActor
private func volumeDownData1(down: Bool) -> Int {
    (1 << 16) | ((down ? 0x0A : 0x0B) << 8)
}

/// A full volume-down press (down then up) through the current captured port;
/// returns the key-down swallow decision (the meaningful one).
@discardableResult
@MainActor
private func pressVolumeDown(_ ops: InjectableEventTapOperating) -> Bool? {
    let down = ops.deliver(data1: volumeDownData1(down: true))
    _ = ops.deliver(data1: volumeDownData1(down: false))
    return down
}
