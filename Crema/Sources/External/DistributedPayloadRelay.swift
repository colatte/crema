import Foundation

/// The ObjC target both BetterDisplay registrations hand to
/// `DistributedNotificationCenter`, forwarding the notification's JSON payload to
/// a MainActor handler.
///
/// It exists because the only registration that takes a suspension behaviour takes
/// a selector, and a selector needs an ObjC target — which neither owner can be
/// itself without dragging NSObject into an `@Observable` type and into an
/// actor-isolated `Sendable` one. Both channels of the neighbour's integration are
/// shaped alike (a JSON string in `object`), so the relay is written once and the
/// owners keep only their own handling.
@MainActor
final class DistributedPayloadRelay: NSObject {
    private let deliver: @MainActor (String) -> Void

    init(deliver: @escaping @MainActor (String) -> Void) {
        self.deliver = deliver
        super.init()
    }

    // nonisolated because the centre calls the selector from its own machinery;
    // the body then assumes the actor it is measured to be on, exactly as the
    // screen-lock source's selector observer does.
    @objc nonisolated func payloadArrived(_ note: Notification) {
        // The payload rides in `object` as a JSON string, not in `userInfo` — that
        // is the published contract on both of BetterDisplay's channels, and a
        // dictionary would be wrong.
        guard let json = note.object as? String else { return }
        // A distributed notification is delivered on the run loop of the thread that
        // registered, and both owners register from their MainActor `init` — so the
        // MainActor is the current executor and assuming it is what keeps events in
        // the order they arrived, where a hop would reorder them. Same assumption
        // the screen-lock source's selector observer makes.
        MainActor.assumeIsolated { deliver(json) }
    }
}
