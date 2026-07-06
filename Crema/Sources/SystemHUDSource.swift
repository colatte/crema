/// Event source for system HUD changes (volume, screen/keyboard brightness).
protocol SystemHUDSource: Sendable {
    /// Single-consumer stream of domain updates. A finished stream means the
    /// source became unavailable — availability is state, not a fatal error.
    var updates: AsyncStream<SystemHUD> { get }
    func isAvailable() async -> Bool
}
