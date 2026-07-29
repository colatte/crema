import AppKit
import CoreGraphics
import Foundation
import os

/// Screen-brightness HUD events published by BetterDisplay.
///
/// Why it exists: BetterDisplay drives brightness from the same media keys Crema
/// taps, and only one of two chained taps is served first. When BetterDisplay
/// wins that race, Crema is never told the key was pressed and has nothing to
/// draw. Crema does not fight for the position (docs/DECISIONS.md:
/// media-key-chain-contention) — it listens to the OSD notification BetterDisplay
/// publishes for third-party HUDs, so the neighbour keeps the key and Crema keeps
/// the HUD, and the user keeps both features.
///
/// The two paths do not overlap: whoever is served first consumes the key and the
/// other app is never told it happened — verified on hardware, one side observing
/// the key exactly when the other was silent.
///
/// Inert when BetterDisplay is absent: nothing ever arrives, the stream stays open
/// and empty, and the merged source carries on with its other inputs. That is why
/// this needs no preference — there is no state to turn off, only an app that is
/// or is not publishing.
@MainActor
final class BetterDisplayOSDSource: SystemHUDSource {
    let updates: AsyncStream<SystemHUD>

    /// Only the current prefix is observed. BetterDisplay 4.2.2+ publishes each
    /// OSD event under BOTH this name and the legacy `com.betterdisplay…` one
    /// (confirmed on the wire), so subscribing to both would double every event;
    /// versions old enough to send only the legacy name predate 4.2.1.
    static let notificationName = "pro.betterdisplay.BetterDisplay.osd"

    private static let bundleID = "pro.betterdisplay.BetterDisplay"

    private let continuation: AsyncStream<SystemHUD>.Continuation
    private let isBuiltInDisplay: (Int) -> Bool
    /// Written only in `init` and read only in `deinit`, after every other access
    /// has ended — the lifecycle brackets rule out the concurrent access the
    /// attribute waives; a nonisolated deinit cannot see that bracket, and
    /// removeObserver is itself thread-safe.
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []

    private let logger = Logger.crema("External")

    /// A custom `isBuiltInDisplay` means a test drives the source through
    /// `handle(json:)` — the real DistributedNotificationCenter observer would only
    /// add non-deterministic noise (a stray brightness change during a run), so it
    /// is installed for the production resolver only. Same idiom as the screen-lock
    /// source's injected session reader.
    init(isBuiltInDisplay: ((Int) -> Bool)? = nil) {
        self.isBuiltInDisplay = isBuiltInDisplay ?? { CGDisplayIsBuiltin(CGDirectDisplayID($0)) != 0 }

        var cont: AsyncStream<SystemHUD>.Continuation!
        // Newest-bounded: a held brightness key emits once per step, and a
        // backlog of stale levels is worth less than the current one.
        updates = AsyncStream(bufferingPolicy: .bufferingNewest(4)) { cont = $0 }
        continuation = cont

        if isBuiltInDisplay == nil { installObserver() }
    }

    deinit {
        for observer in observers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        continuation.finish()
    }

    /// Whether BetterDisplay is running at all. Availability is informational
    /// here: the source is harmless when the app is absent, and the merged HUD
    /// source stays available through its other inputs either way.
    func isAvailable() async -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    /// The payload entry point — a delivered OSD notification funnels here.
    /// Internal so a test can feed a captured payload without a real notification.
    func handle(json: String) {
        guard let hud = BetterDisplayOSDTranslation.systemHUD(fromJSON: json, isBuiltInDisplay: isBuiltInDisplay)
        else { return }
        logger.debug("BetterDisplay OSD: brightness \(hud.value, format: .fixed(precision: 2), privacy: .public)")
        continuation.yield(hud)
    }

    private func installObserver() {
        let observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(Self.notificationName),
            object: nil,
            queue: .main
        ) { [weak self] note in
            // The payload rides in `object` as a JSON string, not in userInfo —
            // that is the published contract, and a dictionary would be wrong.
            guard let json = note.object as? String else { return }
            // Delivered on the main queue, so the MainActor is the current
            // executor — assume it rather than hop, which would reorder events.
            MainActor.assumeIsolated { self?.handle(json: json) }
        }
        observers.append(observer)
    }
}
