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
        try await run(Self.control("app.playerPosition = \(max(0, seconds));"))
    }

    func nextTrack() async throws {
        try await run(Self.control("app.nextTrack();"))
    }

    func previousTrack() async throws {
        try await run(Self.control("app.previousTrack();"))
    }

    /// Wraps a control statement so it runs against whichever of Spotify/Music
    /// is currently playing, returning "true" on success.
    private static func control(_ statement: String) -> String {
        """
        (function() {
          function act(name) {
            try {
              const app = Application(name);
              if (!app.running()) return false;
              if (app.playerState() === 'stopped') return false;
              \(statement)
              return true;
            } catch (e) {
              return false;
            }
          }
          return String(act('Spotify') || act('Music'));
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
        // which degrades the controls just like any other command failure below
        // (audit A6).
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
