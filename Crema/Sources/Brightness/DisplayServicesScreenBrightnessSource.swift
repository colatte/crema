import Foundation

/// Screen-brightness source. Emits a `.screenBrightness` SystemHUD when the
/// level changes because of a key — never for the ambient-light sensor
/// (auto-brightness), which moves the same value and would otherwise flicker
/// the HUD on its own.
///
/// The origin decision lives in the shared KeyOriginBrightnessGate; this source
/// owns the border (the DisplayServices backend, the poll, the stream). The
/// tap fires on a brightness key in both modes — suppression on (the tap
/// consumes) and off (the tap still observes) — and calls `sample()`, which
/// arms the gate's window. The poll exists because the spike found no
/// change-notification API, and it is also the path that catches the value a
/// beat after the key (the OS/consumer applies it just after the tap fires).
final class DisplayServicesScreenBrightnessSource: SystemHUDSource, ManuallySampledSource, @unchecked Sendable {
    let updates: AsyncStream<SystemHUD>

    private let continuation: AsyncStream<SystemHUD>.Continuation
    private let backend: any ScreenBrightnessBackend
    private let clock: any SleepClock
    private let pollInterval: Double
    private let lock = NSLock()
    private var gate: KeyOriginBrightnessGate
    private var pollTask: Task<Void, Never>?

    init(
        backend: any ScreenBrightnessBackend = DisplayServicesBridge(),
        clock: any SleepClock = ContinuousSleepClock(),
        pollInterval: Double = 0.5,
        keyActivityWindow: Double = 1.5,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
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
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await self.clock.sleep(for: self.pollInterval)
                self.emitIfChanged(keyDriven: false)
            }
        }
    }

    deinit {
        pollTask?.cancel()
        continuation.finish()
    }

    func isAvailable() async -> Bool { backend.isAvailable }

    /// A brightness key drove this (the media-key router, or the suppressor's
    /// post-apply poke): arm the gate and read now.
    func sample() {
        emitIfChanged(keyDriven: true)
    }

    private func emitIfChanged(keyDriven: Bool) {
        guard let raw = backend.read() else { return }
        let value = BrightnessConversion.normalize(raw)
        lock.lock()
        let emit = gate.register(value, keyDriven: keyDriven)
        lock.unlock()
        guard emit else { return }
        continuation.yield(SystemHUD(kind: .screenBrightness, value: value))
    }
}
