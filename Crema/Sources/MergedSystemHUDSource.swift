/// Fans several SystemHUDSources into one stream, so the Coordinator consumes a
/// single injected source while volume + both brightnesses run independently.
///
/// @unchecked because `forwarders` is mutable: the invariant making it safe is
/// that it is written only in init and read only in deinit — never touched
/// concurrently. Adding any other access requires a lock.
final class MergedSystemHUDSource: SystemHUDSource, @unchecked Sendable {
    let updates: AsyncStream<SystemHUD>

    private let sources: [any SystemHUDSource]
    private var forwarders: [Task<Void, Never>] = []

    init(_ sources: [any SystemHUDSource]) {
        self.sources = sources
        var continuation: AsyncStream<SystemHUD>.Continuation!
        updates = AsyncStream { continuation = $0 }
        // The AsyncStream builder above ran synchronously, so continuation is set.
        // swiftlint:disable:next force_unwrapping
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
