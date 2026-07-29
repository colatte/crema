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
    private var gate: KeyOriginBrightnessGate
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

        var continuation: AsyncStream<SystemHUD>.Continuation!
        updates = AsyncStream(bufferingPolicy: .bufferingNewest(4)) { continuation = $0 }
        self.continuation = continuation

        gate = KeyOriginBrightnessGate(
            window: keyActivityWindow,
            now: now,
            baseline: backend.read().map(BrightnessConversion.normalize)
        )

        guard backend.isAvailable else { return }
        // clock/interval captured by value so the sleep never retains self —
        // a strong ref parked across the await would make deinit unreachable
        // while the task it cancels is the very thing keeping self alive.
        pollTask = Task { [weak self, clock, pollInterval] in
            while !Task.isCancelled {
                try? await clock.sleep(for: pollInterval)
                self?.emitIfChanged(keyDriven: false)
            }
        }
    }

    deinit {
        pollTask?.cancel()
        continuation.finish()
    }

    func isAvailable() async -> Bool { backend.isAvailable }

    /// A brightness key for this channel drove this (the media-key router, or
    /// the suppressor's post-apply poke): arm the gate and read now.
    func sample() {
        emitIfChanged(keyDriven: true)
    }

    /// Another source reported this channel's level (BetterDisplay's OSD
    /// notification): the key's window is spent so the armed poll does not draw a
    /// second, hardware-only reading over it.
    func standDown() {
        lock.lock()
        gate.standDown()
        lock.unlock()
    }

    private func emitIfChanged(keyDriven: Bool) {
        guard let raw = backend.read() else { return }
        let value = BrightnessConversion.normalize(raw)
        lock.lock()
        let emit = gate.register(value, keyDriven: keyDriven)
        lock.unlock()
        guard emit else { return }
        continuation.yield(SystemHUD(kind: kind, value: value))
    }
}
