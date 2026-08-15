import Foundation

/// Sends media commands via JXA app scripting (Spotify/Music) — the control
/// path for when the chain is on the JXA fallback. Like the JXA read, it only
/// reaches scriptable players and needs Automation permission; a failure (no
/// scriptable target or permission denied) throws, which degrades the controls.
struct JXACommandChannel: NowPlayingCommandChannel {
    func togglePlayPause() async throws {
        try await run(Self.control("app.playpause();"))
    }

    func seek(to seconds: Double) async throws {
        guard let position = Self.playerPosition(forSeek: seconds) else {
            throw NowPlayingCommandError.commandFailed
        }
        try await run(Self.control("app.playerPosition = \(position);"))
    }

    func nextTrack() async throws {
        try await run(Self.control("app.nextTrack();"))
    }

    func previousTrack() async throws {
        try await run(Self.control("app.previousTrack();"))
    }

    /// The seconds JXA's `playerPosition` is given, or nil for a number no player
    /// can be asked to seek to. The value arrives from outside — the slider's range
    /// comes from player metadata — so it is guarded rather than assumed, and NaN is
    /// rejected rather than floored: `max(0, .nan)` is 0, which would turn an
    /// unusable number into a silent seek to the start of the track instead of a
    /// failed command. Same guard, same reason, as the adapter channel's
    /// `microseconds(forSeek:)`; the infinities go with it, since neither survives
    /// interpolation into a JavaScript number literal.
    static func playerPosition(forSeek seconds: Double) -> Double? {
        guard seconds.isFinite else { return nil }
        return max(0, seconds)
    }

    /// Wraps a control statement so it runs against whichever of Spotify/Music
    /// is currently playing (the shared JXAPlayerScript preamble — the same
    /// player selection the read side uses), returning "true" on success.
    private static func control(_ statement: String) -> String {
        """
        (function() {
        \(JXAPlayerScript.preamble)
          return String(Boolean(withActivePlayer(function(app, state, isSpotify) {
            \(statement)
            return true;
          })));
        })();
        """
    }

    private func run(_ script: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        // Interactive: the user re-taps well before this, so a tight cap keeps a
        // stuck osascript from parking a command forever. A timeout returns nil,
        // which degrades the controls just like any other command failure below.
        let output = await runChildProcess(
            process,
            readingStdout: pipe,
            timeout: 5,
            clock: ContinuousSleepClock(),
            failureValue: nil
        ) { _, output in output }
        guard output == "true" else { throw NowPlayingCommandError.commandFailed }
    }
}
