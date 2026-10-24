/// Reads and writes a neighbour app's own feedback switches, so Crema can take
/// its indicator over while it replaces the system ones and hand it back after.
/// BetterDisplay's request channel is today's one conformer.
protocol OSDSettingsChannel: Sendable {
    /// The switch as the neighbour reports it now.
    func read(_ setting: NeighbourOSDSetting) async throws(OSDSettingsError) -> Bool
    /// A return means the neighbour accepted the write, not that the value took:
    /// the caller reads it back.
    func write(_ setting: NeighbourOSDSetting, to value: Bool) async throws(OSDSettingsError)
}

/// Why a neighbour's switch could not be read or written. Two cases because the
/// person reading about it has two different things to do.
enum OSDSettingsError: Error, Equatable {
    /// No answer inside the deadline: the neighbour is not running, is busy, or
    /// has its request channel switched off.
    case unanswered
    /// It answered, and the answer was no, or not an on/off.
    case refused
}
