/// Fans several SystemHUDSources into one stream, so the Coordinator consumes a
/// single injected source while volume + both brightnesses run independently.
final class MergedSystemHUDSource: SystemHUDSource, @unchecked Sendable {
    let updates: AsyncStream<SystemHUD>

    private let sources: [any SystemHUDSource]
    private var forwarders: [Task<Void, Never>] = []

    init(_ sources: [any SystemHUDSource]) {
        self.sources = sources
        var continuation: AsyncStream<SystemHUD>.Continuation!
        updates = AsyncStream { continuation = $0 }
        let sink = continuation!
        for source in sources {
            forwarders.append(Task {
                for await hud in source.updates {
                    sink.yield(hud)
                }
            })
        }
    }

    deinit {
        forwarders.forEach { $0.cancel() }
    }

    func isAvailable() async -> Bool {
        for source in sources where await source.isAvailable() {
            return true
        }
        return false
    }
}
