#if DEBUG
import AppKit
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

    /// Made-up tracks with covers drawn here: the demo is what the site's
    /// captures are taken from, and nothing in them may be somebody else's work.
    private static let library: [DemoTrack] = [
        DemoTrack(title: "Slow Mornings", artist: "Harbour Lights", duration: 221,
                  colors: [(0.24, 0.17, 0.36), (0.76, 0.41, 0.23), (0.96, 0.78, 0.52)]),
        DemoTrack(title: "Night Swim", artist: "Paper Planes", duration: 198,
                  colors: [(0.06, 0.16, 0.30), (0.12, 0.45, 0.55), (0.62, 0.86, 0.84)]),
        DemoTrack(title: "Golden Hour", artist: "Maré Alta", duration: 247,
                  colors: [(0.42, 0.13, 0.20), (0.86, 0.45, 0.33), (0.99, 0.84, 0.55)]),
    ]

    init() {
        var continuation: AsyncStream<NowPlaying>.Continuation!
        updates = AsyncStream { continuation = $0 }
        self.continuation = continuation

        track = Self.library[0].snapshot(isPlaying: false)

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

    func demoSetPlaying(_ playing: Bool) {
        mutate { $0.isPlaying = playing }
    }

    func demoSeek(to seconds: Double) {
        mutate { $0.position = seconds }
    }

    private func step(by offset: Int) {
        lock.lock()
        let count = Self.library.count
        trackIndex = ((trackIndex + offset) % count + count) % count
        track = Self.library[trackIndex].snapshot(isPlaying: track.isPlaying)
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

/// One made-up track and the cover drawn for it: three colours, a ground
/// gradient and two soft lights.
struct DemoTrack {
    let title: String
    let artist: String
    let duration: Double
    let colors: [(Double, Double, Double)]

    func snapshot(isPlaying: Bool) -> NowPlaying {
        NowPlaying(
            title: title, artist: artist, artworkData: cover(), isPlaying: isPlaying,
            position: 0, duration: duration
        )
    }

    private func cover() -> [UInt8]? {
        let side = 512
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let cg = colors.map { CGColor(red: $0.0, green: $0.1, blue: $0.2, alpha: 1) }
        let size = CGFloat(side)
        if let ground = CGGradient(colorsSpace: nil, colors: [cg[0], cg[1]] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(ground, start: .zero, end: CGPoint(x: size, y: size), options: [])
        }
        for (center, radius, color) in [
            (CGPoint(x: size * 0.32, y: size * 0.7), size * 0.42, cg[2]),
            (CGPoint(x: size * 0.78, y: size * 0.22), size * 0.38, cg[1]),
        ] {
            let clear = color.copy(alpha: 0) ?? color
            if let light = CGGradient(colorsSpace: nil, colors: [color, clear] as CFArray, locations: [0, 1]) {
                context.drawRadialGradient(light, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
            }
        }
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
        return [UInt8](data)
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
    private var route = AudioOutputRoute.builtInSpeakers

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
        let (value, route) = lock.withLock {
            self.muted = muted
            return (levels[.volume] ?? 0.5, self.route)
        }
        continuation.yield(
            SystemHUD(kind: .volume, value: value, isMuted: muted, target: Self.target(.volume, display), route: route)
        )
    }

    func setBrightness(_ value: Double, on display: DisplayUUID?) async throws -> Double {
        emit(.screenBrightness, value: value, display: display)
        return value   // the demo writes nothing and coalesces nothing
    }

    func setBrightness(_ value: Double) async throws {
        emit(.keyboardBrightness, value: value, display: nil)
    }

    /// Sets a level and emits it, as a press landing on that value would.
    func demoSet(_ kind: SystemHUD.Kind, to value: Double) {
        emit(kind, value: value, display: nil)
    }

    /// Simulates one media-key press: bumps the level (wrapping) and emits.
    func demoKeyPress(_ kind: SystemHUD.Kind) {
        lock.lock()
        var value = (levels[kind] ?? 0.5) + 0.1
        if value > 1 { value = 0 }
        levels[kind] = value
        lock.unlock()
        yield(kind, value: value, display: nil)
    }

    /// Moves the sound to the next kind of device, emitting nothing: like the
    /// real source, a device switch never pops the HUD, and the next volume
    /// press draws the new glyph.
    func demoSetOutputDevice(_ route: AudioOutputRoute) {
        lock.withLock { self.route = route }
    }

    func demoNextOutputDevice() {
        lock.withLock {
            let all = AudioOutputRoute.allCases
            let index = all.firstIndex(of: route) ?? 0
            route = all[(index + 1) % all.count]
        }
    }

    /// A command carries the ACTUATION spelling, where nil means "my own panel", so
    /// the loopback has to put the role back the way the real producers state it —
    /// otherwise the demo bar would jump from the built-in panel to every screen
    /// mid-drag, the bug this menu exists to reproduce without
    /// hardware (docs/DECISIONS.md: hud-target-is-a-role).
    private static func target(_ kind: SystemHUD.Kind, _ display: DisplayUUID?) -> SystemHUD.Target {
        guard kind == .screenBrightness else { return .noDisplay }
        return display.map { .display($0) } ?? .builtIn
    }

    private func emit(_ kind: SystemHUD.Kind, value: Double, display: DisplayUUID?) {
        lock.withLock { levels[kind] = value }
        yield(kind, value: value, display: display)
    }

    private func yield(_ kind: SystemHUD.Kind, value: Double, display: DisplayUUID?) {
        let (muted, route) = lock.withLock { (self.muted, self.route) }
        let isVolume = kind == .volume
        continuation.yield(
            SystemHUD(
                kind: kind,
                value: value,
                isMuted: isVolume ? muted : false,
                target: Self.target(kind, display),
                route: isVolume ? route : nil
            )
        )
    }
}
#endif
