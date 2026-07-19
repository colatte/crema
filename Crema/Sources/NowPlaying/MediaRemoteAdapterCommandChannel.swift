import Foundation

/// Sends media commands through the adapter (one-shot perl per command). The
/// adapter's `send` calls MRMediaRemoteSendCommand, which returns false when the
/// platform blocks the write; the adapter then exits non-zero — so a non-zero
/// exit here is the reliable signal that commands are unavailable on this macOS.
/// The exit code only covers delivery: a skip sent to media that prohibits it
/// (radio, live) is delivered, ignored by the app, and exits 0 — that case is
/// gated upstream by the stream's prohibitsSkip metadata (NowPlaying.supportsSkip),
/// never by this channel.
struct MediaRemoteAdapterCommandChannel: NowPlayingCommandChannel {
    let paths: MediaRemoteAdapterPaths

    /// kMRATogglePlayPause / kMRANextTrack / kMRAPreviousTrack (per the
    /// adapter's command table).
    private static let togglePlayPauseCommandID = 2
    private static let nextTrackCommandID = 4
    private static let previousTrackCommandID = 5

    func togglePlayPause() async throws {
        try await run(["send", "\(Self.togglePlayPauseCommandID)"])
    }

    func nextTrack() async throws {
        try await run(["send", "\(Self.nextTrackCommandID)"])
    }

    func previousTrack() async throws {
        try await run(["send", "\(Self.previousTrackCommandID)"])
    }

    func seek(to seconds: Double) async throws {
        // The adapter's seek takes microseconds and rejects negatives.
        let microseconds = Int((max(0, seconds) * 1_000_000).rounded())
        try await run(["seek", "\(microseconds)"])
    }

    private func run(_ command: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script, paths.framework] + command
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // Interactive: a stuck send (the MediaRemote XPC never returning) must
        // not park the command forever — the user re-taps first. A timeout
        // reports -1, degrading the controls exactly like a non-zero exit
        // (audit A6).
        let status = await runChildProcess(process, timeout: 5, clock: ContinuousSleepClock(), failureValue: Int32(-1)) { finished, _ in
            finished.terminationStatus
        }
        guard status == 0 else { throw NowPlayingCommandError.commandFailed }
    }
}
