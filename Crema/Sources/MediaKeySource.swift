/// Event source for physical media-key presses (volume, screen and keyboard
/// brightness). Unavailable while the Accessibility permission is missing —
/// the app degrades gracefully and keeps running without key capture.
protocol MediaKeySource: Sendable {
    /// Single-consumer stream of key presses. A finished stream means the
    /// source became unavailable — availability is state, not a fatal error.
    var updates: AsyncStream<MediaKey> { get }
    func isAvailable() async -> Bool
}
