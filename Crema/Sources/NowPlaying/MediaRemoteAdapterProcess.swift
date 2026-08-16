import Foundation
import os

/// Long-running adapter stream process: spawns `/usr/bin/perl` on the vendored
/// script in `stream` mode and exposes the raw stdout as a line stream. This
/// step does not translate lines into NowPlaying — it only gets
/// the process up and the lines flowing so they can be observed.
///
/// stdout is read as an async byte sequence off the main thread (never
/// waitUntilExit / readDataToEndOfFile on main). EOF or process death finishes
/// the stream — unavailability is state, not a fatal error. The process is
/// terminated on stop()/deinit so quitting the app leaves no zombie.
final class MediaRemoteAdapterProcess: @unchecked Sendable {
    /// The interpreter the vendored bridge runs on, named once so the three
    /// places that spawn it (this stream, the availability probe, the command
    /// channel) cannot drift — and so the warning has one home.
    ///
    /// **This path is on notice from Apple, and has been since Catalina.** The
    /// 10.15 release notes, under Scripting Language Runtimes → Deprecations:
    /// "Scripting language runtimes such as Python, Ruby, and Perl are included
    /// in macOS for compatibility with legacy software. Future versions of macOS
    /// won't include scripting language runtimes by default." Still shipping as
    /// of macOS 26 (measured on this machine: 5.34.1), so nothing is broken
    /// today.
    ///
    /// The failure when it goes is quiet rather than loud, which is the part
    /// worth knowing: `run()` throws, the probe answers false forever, and the
    /// now-playing chain pins itself to the JXA fallback for the life of the
    /// install — no browser media, no artwork, and an Automation prompt where
    /// there was none. That is the chain's designed degradation working exactly
    /// as intended, so there is nothing to fix here; what there is, is a reason
    /// to recognise the shape fast when a macOS release finally does it.
    static let perlPath = "/usr/bin/perl"

    let rawLines: AsyncStream<String>

    private let continuation: AsyncStream<String>.Continuation
    private let process = Process()
    private let stdout = Pipe()
    private let lock = NSLock()
    private var readerTask: Task<Void, Never>?
    private var isTornDown = false

    private let logger = Logger.crema("NowPlaying")

    /// The default carries `--no-diff` because the only translation that exists
    /// cannot read anything else: in diff mode the adapter emits partial payloads
    /// under the same `"type":"data"` envelope (`diff` is a sibling BOOLEAN, not a
    /// value of `type`, so no envelope check filters them out), and
    /// `AdapterPayloadTranslation` reads a line with no title as "nothing
    /// playing" — the surface would vanish and return on every metadata change.
    /// A default that produces lines nothing can parse is a trap for the next
    /// construction, so it is not offered. Artwork stays off because the observed
    /// lines are meant to be readable; a source that wants covers asks.
    init(paths: MediaRemoteAdapterPaths, streamArguments: [String] = ["stream", "--no-diff", "--no-artwork"]) {
        var continuation: AsyncStream<String>.Continuation!
        rawLines = AsyncStream { continuation = $0 }
        self.continuation = continuation

        process.executableURL = URL(fileURLWithPath: Self.perlPath)
        process.arguments = [paths.script, paths.framework] + streamArguments
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        // If the consumer stops iterating early (without calling stop()), tear
        // down anyway so no Perl process is left running.
        continuation.onTermination = { [weak self] _ in self?.teardown() }
    }

    deinit {
        teardown()
        continuation.finish()
    }

    func start() {
        // Process death (EOF on the other side) also finishes the stream, in
        // case the reader has not yet drained.
        process.terminationHandler = { [continuation] _ in continuation.finish() }

        do {
            try process.run()
        } catch {
            logger.error("adapter process failed to start: \(error, privacy: .public)")
            continuation.finish()
            return
        }

        let bytes = stdout.fileHandleForReading.bytes
        let task = Task { [continuation] in
            for await line in AdapterLineStream.lines(from: bytes) {
                continuation.yield(line)
            }
            continuation.finish()
        }
        lock.lock(); readerTask = task; lock.unlock()
    }

    func stop() {
        teardown()
        continuation.finish()
    }

    /// Reachable concurrently — the reader Task's EOF (onTermination) and an
    /// external stop()/deinit can land at once. Capture and flip under the lock
    /// so the side effects run exactly once, matching the lock discipline the
    /// sibling now-playing sources use for this same race.
    private func teardown() {
        lock.lock()
        guard !isTornDown else { lock.unlock(); return }
        isTornDown = true
        let task = readerTask
        readerTask = nil
        lock.unlock()

        task?.cancel()
        if process.isRunning { process.terminate() }
    }
}
