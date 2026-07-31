#if DEBUG
import Foundation

/// Debug-only demo pipeline: fake sources/actuators driving the real
/// Coordinator → WindowManager → Styles end to end with no system APIs.
/// Development infrastructure — never compiled into Release.
@MainActor
final class DemoEngine {
    let media = DemoMediaSource()
    let hud = DemoHUDEngine()
}

/// Fake player: conforms to the same protocols the real now-playing sources do,
/// so the Coordinator cannot tell it apart from the adapter or the JXA fallback.
/// Lock-protected; ticks position once per second while playing.
final class DemoMediaSource: NowPlayingSource, NowPlayingController, @unchecked Sendable {
    let updates: AsyncStream<NowPlaying>

    private let continuation: AsyncStream<NowPlaying>.Continuation
    private let lock = NSLock()
    private var track: NowPlaying
    private var trackIndex = 0
    private var ticker: Task<Void, Never>?

    private static let library: [(title: String, artist: String, duration: Double)] = [
        ("Breathe", "Pink Floyd", 169),
        ("Paranoid Android", "Radiohead", 386),
        ("Ela Partiu", "Tim Maia", 199),
    ]

    init() {
        var continuation: AsyncStream<NowPlaying>.Continuation!
        updates = AsyncStream { continuation = $0 }
        self.continuation = continuation

        let first = Self.library[0]
        track = NowPlaying(title: first.title, artist: first.artist, isPlaying: false, position: 0, duration: first.duration)

        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    deinit {
        ticker?.cancel()
    }

    func isAvailable() async -> Bool { true }

    // MARK: NowPlayingController (the real command path)

    func togglePlayPause() async throws { demoTogglePlayPause() }

    func seek(to seconds: Double) async throws {
        mutate { $0.position = min(max(0, seconds), $0.duration ?? seconds) }
    }

    func nextTrack() async throws { step(by: 1) }

    func previousTrack() async throws { step(by: -1) }

    // MARK: Demo menu conveniences

    func demoTogglePlayPause() {
        mutate { $0.isPlaying.toggle() }
    }

    func demoNextTrack() {
        step(by: 1)
    }

    private func step(by offset: Int) {
        lock.lock()
        let count = Self.library.count
        trackIndex = ((trackIndex + offset) % count + count) % count
        let next = Self.library[trackIndex]
        track = NowPlaying(title: next.title, artist: next.artist, isPlaying: track.isPlaying, position: 0, duration: next.duration)
        let snapshot = track
        lock.unlock()
        continuation.yield(snapshot)
    }

    private func tick() {
        lock.lock()
        guard track.isPlaying else {
            lock.unlock()
            return
        }
        track.position += 1
        if let duration = track.duration, track.position >= duration {
            track.position = 0
        }
        let snapshot = track
        lock.unlock()
        continuation.yield(snapshot)
    }

    private func mutate(_ change: (inout NowPlaying) -> Void) {
        lock.lock()
        change(&track)
        let snapshot = track
        lock.unlock()
        continuation.yield(snapshot)
    }
}

/// Fake system levels: emits HUD events and loops actuator commands back as new
/// events, standing in for the echo the real borders get from Core Audio and the
/// brightness poll.
final class DemoHUDEngine: SystemHUDSource, VolumeController, ScreenBrightnessController, KeyboardBrightnessController, @unchecked Sendable {
    let updates: AsyncStream<SystemHUD>

    private let continuation: AsyncStream<SystemHUD>.Continuation
    private let lock = NSLock()
    private var levels: [SystemHUD.Kind: Double] = [
        .volume: 0.5,
        .screenBrightness: 0.7,
        .keyboardBrightness: 0.3,
    ]
    private var muted = false

    init() {
        var continuation: AsyncStream<SystemHUD>.Continuation!
        updates = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func isAvailable() async -> Bool { true }

    // MARK: Actuators (loopback: command → new HUD event)

    func setVolume(_ value: Double, on display: DisplayUUID?) async throws {
        emit(.volume, value: value, display: display)
    }

    func setMuted(_ muted: Bool, on display: DisplayUUID?) async throws {
        let value = lock.withLock {
            self.muted = muted
            return levels[.volume] ?? 0.5
        }
        continuation.yield(
            SystemHUD(kind: .volume, value: value, isMuted: muted, target: Self.target(.volume, display))
        )
    }

    func setBrightness(_ value: Double, on display: DisplayUUID?) async throws -> Double {
        emit(.screenBrightness, value: value, display: display)
        return value   // the demo writes nothing and coalesces nothing
    }

    func setBrightness(_ value: Double) async throws {
        emit(.keyboardBrightness, value: value, display: nil)
    }

    /// Simulates one media-key press: bumps the level (wrapping) and emits.
    func demoKeyPress(_ kind: SystemHUD.Kind) {
        lock.lock()
        var value = (levels[kind] ?? 0.5) + 0.1
        if value > 1 { value = 0 }
        levels[kind] = value
        let muted = self.muted
        lock.unlock()
        continuation.yield(
            SystemHUD(kind: kind, value: value, isMuted: kind == .volume ? muted : false, target: Self.target(kind, nil))
        )
    }

    /// A command carries the ACTUATION spelling, where nil means "my own panel", so
    /// the loopback has to put the role back the way the real producers state it —
    /// otherwise the demo bar would jump from the built-in panel to every screen
    /// mid-drag, which is the shipped bug this menu exists to reproduce without
    /// hardware (docs/DECISIONS.md: hud-target-is-a-role).
    private static func target(_ kind: SystemHUD.Kind, _ display: DisplayUUID?) -> SystemHUD.Target {
        guard kind == .screenBrightness else { return .noDisplay }
        return display.map { .display($0) } ?? .builtIn
    }

    private func emit(_ kind: SystemHUD.Kind, value: Double, display: DisplayUUID?) {
        lock.lock()
        levels[kind] = value
        let muted = self.muted
        lock.unlock()
        continuation.yield(
            SystemHUD(kind: kind, value: value, isMuted: kind == .volume ? muted : false, target: Self.target(kind, display))
        )
    }
}
#endif
