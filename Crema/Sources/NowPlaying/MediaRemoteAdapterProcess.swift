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
    let rawLines: AsyncStream<String>

    private let continuation: AsyncStream<String>.Continuation
    private let process = Process()
    private let stdout = Pipe()
    private let lock = NSLock()
    private var readerTask: Task<Void, Never>?
    private var isTornDown = false

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.colatte.crema",
        category: "NowPlaying"
    )

    /// `streamArguments` default omits artwork so the observed lines stay
    /// readable; the real source decides what it needs.
    init(paths: MediaRemoteAdapterPaths, streamArguments: [String] = ["stream", "--no-artwork"]) {
        var continuation: AsyncStream<String>.Continuation!
        rawLines = AsyncStream { continuation = $0 }
        self.continuation = continuation

        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
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
