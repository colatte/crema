/// Splits the adapter's stdout byte stream into lines (one JSON object per
/// line). The pure `LineBuffer` is what the tests exercise; `lines(from:)`
/// drives it over an async byte sequence and finishes on EOF.
enum AdapterLineStream {
    /// Accumulates bytes and hands back complete lines. Newline-terminated;
    /// bare carriage returns are dropped so CRLF collapses to one line.
    struct LineBuffer {
        private var pending: [UInt8] = []

        /// Pushes one byte; returns a completed line when a newline is reached.
        mutating func push(_ byte: UInt8) -> String? {
            switch byte {
            case 0x0A:
                defer { pending.removeAll(keepingCapacity: true) }
                return String(decoding: pending, as: UTF8.self)
            case 0x0D:
                return nil
            default:
                pending.append(byte)
                return nil
            }
        }

        mutating func push(_ chunk: [UInt8]) -> [String] {
            chunk.compactMap { push($0) }
        }

        /// Any bytes left after the last newline (a final unterminated line).
        mutating func flush() -> String? {
            guard !pending.isEmpty else { return nil }
            defer { pending.removeAll() }
            return String(decoding: pending, as: UTF8.self)
        }
    }

    /// Consumes `bytes` and yields complete lines; the returned stream finishes
    /// when the byte sequence ends (EOF ⇒ finish, never a fatal error). A
    /// trailing unterminated line is emitted so nothing is lost at EOF.
    /// Per-byte iteration is a considered trade-off even with artwork fattening
    /// lines to ~500 KB: AsyncBytes buffers internally (the await is a fast
    /// path, not a suspension per byte), the work runs on the reader task off
    /// the main thread, and fat lines arrive per track change, not per tick —
    /// chunked pipe reading would buy little for the plumbing risk.
    static func lines<Bytes: AsyncSequence & Sendable>(from bytes: Bytes) -> AsyncStream<String>
    where Bytes.Element == UInt8 {
        AsyncStream { continuation in
            let task = Task {
                var buffer = LineBuffer()
                do {
                    for try await byte in bytes {
                        if let line = buffer.push(byte) {
                            continuation.yield(line)
                        }
                    }
                } catch {
                    // Read failure is unavailability, not fatal — just finish.
                }
                if let last = buffer.flush() {
                    continuation.yield(last)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
