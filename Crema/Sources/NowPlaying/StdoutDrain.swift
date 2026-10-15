import Foundation

/// Reads a child's stdout while it runs, and hands the whole of it over once
/// the child has exited.
///
/// Read only at exit, output past what the pipe buffers never arrives: "the size
/// of the buffer is determined by the underlying operating system" (Apple,
/// Pipe), a child writing past it blocks until someone reads, and a child that
/// never exits loses its whole reply to the deadline. The read is a blocking
/// one to end of file, so it runs on `DispatchQueue.global()` (see
/// `blockingCall`), started once the child has spawned so a spawn failure leaves
/// no reader parked on a pipe nobody writes.
///
/// `@unchecked Sendable`: `data` is written once on the reading thread before
/// `finished` is signalled, and read only after a wait on it.
final class StdoutDrain: @unchecked Sendable {
    private let handle: FileHandle
    private let finished = DispatchSemaphore(value: 0)
    private var data: Data?

    init(_ pipe: Pipe) {
        handle = pipe.fileHandleForReading
    }

    func start() {
        DispatchQueue.global().async { [self] in
            data = try? handle.readToEnd()
            finished.signal()
        }
    }

    /// Blocks until the child's stdout reaches end of file, which its exit
    /// brings; the text is trimmed of surrounding whitespace.
    func output() -> String? {
        finished.wait()
        return data
            .flatMap { String(data: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
