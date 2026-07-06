import Foundation

/// Keyboard-backlight source. Emits a `.keyboardBrightness` SystemHUD when the
/// level changes because of a key — never for the ambient-light sensor, which
/// auto-adjusts the backlight (hardware-confirmed on this Mac) and moves the
/// same value. Uses the identical origin logic as the screen source, via the
/// shared KeyOriginBrightnessGate: a key `sample()` arms a short window and the
/// poll emits only inside it.
final class CoreBrightnessKeyboardBrightnessSource: SystemHUDSource, ManuallySampledSource, @unchecked Sendable {
    let updates: AsyncStream<SystemHUD>

    private let continuation: AsyncStream<SystemHUD>.Continuation
    private let backend: any KeyboardBrightnessBackend
    private let clock: any SleepClock
    private let pollInterval: Double
    private let lock = NSLock()
    private var gate: KeyOriginBrightnessGate
    private var pollTask: Task<Void, Never>?

    init(
        backend: any KeyboardBrightnessBackend = CoreBrightnessKeyboardBridge(),
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

    /// A keyboard-brightness key drove this (the media-key router, or the
    /// suppressor's post-apply poke): arm the gate and read now.
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
        continuation.yield(SystemHUD(kind: .keyboardBrightness, value: value))
    }
}
