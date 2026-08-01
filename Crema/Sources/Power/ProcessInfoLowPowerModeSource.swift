import Foundation

/// Real Low Power Mode source: `ProcessInfo.isLowPowerModeEnabled` for the truth,
/// `NSProcessInfoPowerStateDidChange` for the latency. The same split the
/// screen-lock source uses, and for the same reason — an edge never flips the
/// state on its own. Here the edge is even less of a value than a lock
/// notification: Apple posts it for every power-usage change, so unplugging the
/// charger delivers one with Low Power Mode untouched. A source that toggled on
/// each delivery would freeze the waveform of everyone who moves their Mac off the
/// desk. Every delivery re-reads and emits WHAT IT READ.
///
/// This class is the thin border: the reading, the observer, and nothing else.
@MainActor
final class ProcessInfoLowPowerModeSource: LowPowerModeSource {
    let updates: AsyncStream<Bool>
    private(set) var isLowPower: Bool

    private let continuation: AsyncStream<Bool>.Continuation
    /// The authoritative read, injectable so a test drives the state (and its
    /// edges, through the injected center) without the real ProcessInfo reading.
    private let read: @MainActor () -> Bool
    /// `nonisolated` so the deinit below can reach it to unregister: the center is
    /// itself Sendable and immutable here, unlike the observer token.
    private nonisolated let center: NotificationCenter
    // nonisolated(unsafe): written only while `init` runs and read only in
    // `deinit`, after every other access has ended — the lifecycle brackets rule
    // out the concurrent access the attribute waives; a nonisolated deinit cannot
    // see that bracket, and removeObserver is itself thread-safe.
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    /// The default center is the production one, so the app's construction carries
    /// no center argument at all and cannot be aimed elsewhere by editing a call
    /// site; a test injects a private center to stay isolated from a real
    /// power-state change landing mid-run. The observer is installed either way —
    /// unlike the screen-lock and neighbour sources, whose real observers would add
    /// noise a test cannot control — because a private center delivers nothing but
    /// what the test posts, and driving the real subscription is the only way to
    /// check it: which name was actually subscribed to is invisible from inside the
    /// process, where nothing arriving looks exactly like nobody posting.
    init(center: NotificationCenter = .default, read: (@MainActor () -> Bool)? = nil) {
        self.center = center
        let reader = read ?? { ProcessInfo.processInfo.isLowPowerModeEnabled }
        self.read = reader
        isLowPower = reader()

        var cont: AsyncStream<Bool>.Continuation!
        updates = AsyncStream { cont = $0 }
        continuation = cont

        observer = center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue, so the MainActor is the current
            // executor — assume it rather than hop (a hop would let two edges
            // reorder, and the later reading is the one worth keeping). The
            // guarantee is `queue: .main`'s own, live and undeprecated
            // (docs/DECISIONS.md: assumed-isolation-is-measured).
            MainActor.assumeIsolated { self?.handleEdge() }
        }
    }

    deinit {
        if let observer { center.removeObserver(observer) }
        continuation.finish()
    }

    /// The edge entry point — a delivered power-state notification funnels here.
    /// Private on purpose: the tests reach it by posting on the injected center,
    /// which is what makes them pin the subscription and not just this body.
    private func handleEdge() {
        let lowPower = read()
        isLowPower = lowPower
        continuation.yield(lowPower)
    }
}
