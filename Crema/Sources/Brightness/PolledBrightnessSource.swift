import Foundation

/// Brightness source for one channel — screen or keyboard backlight — over the
/// injected BrightnessBackend. Emits its SystemHUD kind when the level changes
/// because of a key — never for the ambient-light sensor (auto-brightness on
/// the display; the auto-adjusting backlight, hardware-confirmed, on the
/// keyboard), which moves the same value and would otherwise flicker the HUD
/// on its own.
///
/// The origin decision lives in the shared KeyOriginBrightnessGate; this
/// source owns the border machinery (backend, poll, stream), which is
/// channel-independent and therefore exists exactly once — the per-technology
/// contact lives in the bridges behind BrightnessBackend. The tap fires on a
/// brightness key in both modes — suppression on (the tap consumes) and off
/// (the tap still observes) — and calls `sample()`, which arms the gate's
/// window. The poll exists because the spike found no change-notification API,
/// and it is also the path that catches the value a beat after the key (the
/// OS/consumer applies it just after the tap fires).
final class PolledBrightnessSource: SystemHUDSource, ManuallySampledSource, @unchecked Sendable {
    let updates: AsyncStream<SystemHUD>

    private let continuation: AsyncStream<SystemHUD>.Continuation
    private let kind: SystemHUD.Kind
    private let backend: any BrightnessBackend
    private let clock: any SleepClock
    private let pollInterval: Double
    private let lock = NSLock()
    /// Every `backend.read()` runs here and nowhere else. The read is a blocking
    /// private-API call — a dlsym'd DisplayServices entry point, or a round trip to
    /// the keyboard-backlight client, which re-enumerates the keyboard IDs on every
    /// call — and its callers are the MainActor (the suppressor's post-apply poke;
    /// the slider echo, once per drag frame) and the cooperative pool (the router
    /// task, the poll). Reading on the caller's thread put that call on both, and
    /// the volume sibling already paid for the lesson: inline, a stalled daemon
    /// froze HUD, now playing and menu on the HEALTHY path, once per key, while the
    /// key had already been swallowed (docs/DECISIONS.md: read-deadline-pool-rule,
    /// async-signature-is-not-a-suspension-point). Serial rather than the global
    /// pool so this channel's readings register in the order they were asked for;
    /// the price is explicit — a blocked read holds this channel's readings, which
    /// is the honest answer when the value itself is unknowable.
    private let queue: DispatchQueue
    private var gate: KeyOriginBrightnessGate
    /// Readings a key asked for that have not come back yet, and how many of those
    /// a `standDown()` has already spoken for. Needed because a reading now returns
    /// AFTER the call that asked for it: a key-driven reading emits on any change,
    /// window or not, so without this a neighbour reporting the same press while
    /// our reading was in flight would still get a second bar drawn over it on our
    /// own scale. That is the one thing plain ordering protected while the read ran
    /// on the caller's thread (docs/DECISIONS.md: betterdisplay-osd-source).
    private var pendingKeyReadings = 0
    private var spokenForKeyReadings = 0
    private var pollTask: Task<Void, Never>?

    init(
        kind: SystemHUD.Kind,
        backend: any BrightnessBackend,
        clock: any SleepClock = ContinuousSleepClock(),
        pollInterval: Double = 0.5,
        keyActivityWindow: Double = 1.5,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.kind = kind
        self.backend = backend
        self.clock = clock
        self.pollInterval = pollInterval
        queue = DispatchQueue(label: "com.colatte.crema.PolledBrightnessSource.\(kind)")

        var continuation: AsyncStream<SystemHUD>.Continuation!
        updates = AsyncStream(bufferingPolicy: .bufferingNewest(4)) { continuation = $0 }
        self.continuation = continuation

        // The launch baseline is the one reading that stays on the constructing
        // thread, deliberately: it happens once per process rather than once per
        // key, and that thread is already blocked harder by building the backend it
        // was handed (dlopen of a private framework; on the keyboard path,
        // instantiating the client and enumerating its IDs over that connection).
        // Hopping it would move nothing measurable off launch while making "the
        // launch value baselines silently" depend on whether the hop landed before
        // the first key.
        gate = KeyOriginBrightnessGate(
            window: keyActivityWindow,
            now: now,
            baseline: backend.read().map(BrightnessConversion.normalize)
        )

        startPollingIfAvailable()
    }

    /// Arms the cadence, once, and only for a channel that answers.
    ///
    /// Called at launch AND at the first key this channel sees, because
    /// availability is not a launch-time constant: the keyboard backlight is
    /// enumerated over a connection that may not be up yet at a cold boot, and a
    /// channel that answered nothing at launch used to stay silent for the whole
    /// session. A key press is the evidence that the channel is alive — the same
    /// shape the suppressor uses when a user's press kicks a suspended domain's
    /// probe ahead of its backoff, and the reason this is not a retry timer:
    /// hardware that genuinely has no backlight is never polled at all, which is
    /// exactly what the original launch guard was protecting.
    private func startPollingIfAvailable() {
        lock.lock()
        let armed = pollTask != nil
        lock.unlock()
        // Availability asked OUTSIDE the lock: on the keyboard channel it is an
        // enumeration over a connection, and holding this lock across it would put
        // the gate — which `standDown()` takes from another thread, right behind a
        // key — behind an IPC round trip.
        guard !armed, backend.isAvailable else { return }
        lock.lock()
        defer { lock.unlock() }
        // Re-checked under the lock: two callers can pass the test above at once,
        // and the loser must not replace a running task with a second one that
        // nothing cancels.
        guard pollTask == nil else { return }
        // clock/interval captured by value so the sleep never retains self —
        // a strong ref parked across the await would make deinit unreachable
        // while the task it cancels is the very thing keeping self alive. The
        // reading below does retain self while it runs, exactly as the inline read
        // did; the difference that matters is that a reading returns and the sleep
        // is the one that parks indefinitely.
        pollTask = Task { [weak self, clock, pollInterval] in
            while !Task.isCancelled {
                try? await clock.sleep(for: pollInterval)
                await self?.pollOnce()
            }
        }
    }

    deinit {
        pollTask?.cancel()
        continuation.finish()
    }

    func isAvailable() async -> Bool { backend.isAvailable }

    /// A brightness key for this channel drove this (the media-key router, the
    /// suppressor's post-apply poke, or the slider echo): arm the gate here, read
    /// on `queue`. Arming is a timestamp, so it stays on the caller's thread — the
    /// window then measures from the key itself, and a `standDown()` arriving right
    /// behind the key acts on a window that is already open. Only the reading hops.
    func sample() {
        lock.lock()
        gate.armKeyWindow()
        pendingKeyReadings += 1
        lock.unlock()
        queue.async { [weak self] in
            self?.readAndRegister(keyDriven: true)
            // A key for this channel is the evidence that it exists, so it is also
            // the moment to arm a cadence that launch could not. Here and not in the
            // caller: this runs on the tap's own thread, and asking the backend
            // whether it is available enumerates over a connection — a blocking call
            // the tap thread must never make. `queue` is where this channel's
            // blocking reads already live.
            self?.startPollingIfAvailable()
        }
    }

    /// Another source reported this channel's level (BetterDisplay's OSD
    /// notification): the key's window is spent so the armed poll does not draw a
    /// second, hardware-only reading over it — AND every reading a key already
    /// asked for is spoken for too, because such a reading emits on any change
    /// whether the window is open or not, and it comes back from `queue` after this
    /// call rather than before it. Synchronous like the arm it undoes: both only
    /// touch state under the lock, so their order is the order of the two events.
    func standDown() {
        lock.lock()
        gate.standDown()
        spokenForKeyReadings = pendingKeyReadings
        lock.unlock()
    }

    /// Awaits the reading it queued instead of firing and forgetting, so at most
    /// one reading is ever in flight for this channel: otherwise a stalled read
    /// lets the cadence pile up work items that all land at once when it clears.
    /// The body cannot throw — `try?` only satisfies the shared helper's throwing
    /// signature.
    private func pollOnce() async {
        _ = try? await blockingCall(on: queue) { self.readAndRegister(keyDriven: false) }
    }

    /// Runs on `queue` only — where the read happens is the whole point of this
    /// seam (see `queue`), so a new poke belongs in `sample()`, never here.
    private func readAndRegister(keyDriven: Bool) {
        guard let raw = backend.read() else {
            // A failed read still retires the key's reading, or the count drifts
            // upward and a later standDown silences a press it never saw.
            if keyDriven {
                lock.lock()
                _ = retireKeyReadingLocked()
                lock.unlock()
            }
            return
        }
        let value = BrightnessConversion.normalize(raw)
        lock.lock()
        let attributed = keyDriven ? retireKeyReadingLocked() : false
        let emit = gate.register(value, keyDriven: attributed)
        lock.unlock()
        guard emit else { return }
        // The target comes from the backend, and it has to be stamped HERE rather
        // than anywhere downstream: the drag's confirming echo closes the loop by
        // re-sampling this source, not by re-publishing the applied value, so a
        // stamp added in the key router or the Coordinator would be undone one
        // frame later and the bar would jump from one screen to all of them inside
        // the gesture (docs/DECISIONS.md: hud-target-is-a-role).
        continuation.yield(SystemHUD(kind: kind, value: value, target: backend.target))
    }

    /// Consumes one outstanding key reading and answers whether it may still speak
    /// for its key. A `standDown()` that arrived while it was in flight already
    /// spoke for it — the neighbour drew that press — so it degrades to a plain
    /// reading rather than adding a bar on our own scale.
    private func retireKeyReadingLocked() -> Bool {
        pendingKeyReadings -= 1
        guard spokenForKeyReadings > 0 else { return true }
        spokenForKeyReadings -= 1
        return false
    }
}
