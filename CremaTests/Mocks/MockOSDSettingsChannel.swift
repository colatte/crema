@testable import Crema

/// Test double for a neighbour's feedback switches: an in-memory value per
/// switch, every request recorded in order, and the three ways a real neighbour
/// lets a caller down — silence, a no, and a yes that does not take.
@MainActor
final class MockOSDSettingsChannel: OSDSettingsChannel {
    enum Call: Equatable {
        case read(NeighbourOSDSetting)
        case write(NeighbourOSDSetting, Bool)
    }

    var values: [NeighbourOSDSetting: Bool]
    private(set) var calls: [Call] = []
    /// While set, every request fails this way and changes nothing.
    var failure: OSDSettingsError?
    /// The neighbour accepts writes and applies none of them.
    var ignoresWrites = false
    /// Runs as each write arrives, before it lands: where a test looks at what the
    /// caller had already persisted when the request left.
    var onWrite: ((NeighbourOSDSetting, Bool) -> Void)?

    init(_ values: [NeighbourOSDSetting: Bool]) {
        self.values = values
    }

    var writes: [Call] {
        calls.filter { call in
            guard case .write = call else { return false }
            return true
        }
    }

    func read(_ setting: NeighbourOSDSetting) async throws(OSDSettingsError) -> Bool {
        calls.append(.read(setting))
        if let failure { throw failure }
        return values[setting] ?? false
    }

    func write(_ setting: NeighbourOSDSetting, to value: Bool) async throws(OSDSettingsError) {
        calls.append(.write(setting, value))
        if let failure { throw failure }
        onWrite?(setting, value)
        if !ignoresWrites { values[setting] = value }
    }
}
