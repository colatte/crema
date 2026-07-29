import Foundation

/// Sends media commands through the adapter (one-shot perl per command). The
/// adapter's `send` calls MRMediaRemoteSendCommand and exits non-zero when it
/// returns false, so the exit code is the signal this channel reports on.
///
/// A non-zero exit is not evidence that the platform blocks writes: measured on
/// macOS 26.5.2, `send` exits 0 and the player moves. Read it as "this command
/// did not land", nothing more.
///
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
        guard let microseconds = Self.microseconds(forSeek: seconds) else {
            throw NowPlayingCommandError.commandFailed
        }
        try await run(["seek", "\(microseconds)"])
    }

    /// The adapter's seek takes microseconds and rejects negatives. The number
    /// arrives from outside — the slider's range comes from player metadata —
    /// so the narrowing is guarded rather than assumed: `Int(Double)` traps on
    /// anything outside Int's range, and MediaRemote's live sentinel
    /// (LLONG_MAX microseconds) scaled back up lands exactly on 2^63. The
    /// sentinel is dropped upstream in `AdapterPayloadTranslation`; nil here is
    /// what keeps a bad number a failed command instead of a crashed app, no
    /// matter who hands it in.
    /// NaN is rejected rather than floored: `max(0, .nan)` is 0, which would
    /// turn an unusable number into a silent seek to the start of the track.
    static func microseconds(forSeek seconds: Double) -> Int? {
        guard seconds.isFinite else { return nil }
        return Int(exactly: (max(0, seconds) * 1_000_000).rounded())
    }

    private func run(_ command: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script, paths.framework] + command
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // Interactive: a stuck send (the MediaRemote XPC never returning) must
        // not park the command forever — the user re-taps first. A timeout
        // reports -1, degrading the controls exactly like a non-zero exit.
        let status = await runChildProcess(process, timeout: 5, clock: ContinuousSleepClock(), failureValue: Int32(-1)) { finished, _ in
            finished.terminationStatus
        }
        guard status == 0 else { throw NowPlayingCommandError.commandFailed }
    }
}
