import AppKit
import CoreGraphics
import Foundation
import Observation
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
@Observable
final class BetterDisplayOSDSource: SystemHUDSource {
    @ObservationIgnored let updates: AsyncStream<SystemHUD>

    /// Only the current prefix is observed. BetterDisplay 4.2.2+ publishes each
    /// OSD event under BOTH this name and the legacy `com.betterdisplay…` one
    /// (confirmed on the wire), so subscribing to both would double every event;
    /// versions old enough to send only the legacy name predate 4.2.1.
    static let notificationName = "pro.betterdisplay.BetterDisplay.osd"

    static let bundleID = "pro.betterdisplay.BetterDisplay"

    /// Whether BetterDisplay has actually published to us. Presence of the app
    /// proves nothing — its OSD notification integration is a setting the user
    /// switches on, and it can be off with the app running — so only a delivered
    /// payload is evidence the channel is live. Reset when the app goes away, so
    /// the claim never outlives what it was based on.
    ///
    /// Observable because the Settings line that shows it is read from a body
    /// SwiftUI has already built: a user who switches the neighbour's integration
    /// on with that window in front of them must see the line change there, not on
    /// the next open. Written only when it actually flips, since an unchanged write
    /// still rebuilds every view reading it.
    private(set) var hasReported = false

    @ObservationIgnored private let continuation: AsyncStream<SystemHUD>.Continuation
    @ObservationIgnored private let target: (Int) -> SystemHUD.Target?
    /// Called after each reported level, so the polled brightness source can spend
    /// the window a merely-observed key opened (see `ManuallySampledSource`).
    @ObservationIgnored private let onReport: @MainActor () -> Void
    /// Written only in `init` and read only in `deinit`, after every other access
    /// has ended — the lifecycle brackets rule out the concurrent access the
    /// attribute waives; a nonisolated deinit cannot see that bracket, and
    /// removeObserver is itself thread-safe. Out of observation like every field
    /// but `hasReported`, and here that is load-bearing: a generated accessor pair
    /// drops `nonisolated(unsafe)` and puts the registrar in the path of that
    /// nonisolated deinit.
    ///
    /// The OSD registration is a relay object rather than a token, because the
    /// suspension behaviour is only available on the selector-based registration
    /// (see `installObserver`); the center holds an observer unowned, so the deinit
    /// still has to name it.
    @ObservationIgnored private nonisolated(unsafe) var payloadRelay: DistributedPayloadRelay?
    @ObservationIgnored private nonisolated(unsafe) var workspaceObservers: [NSObjectProtocol] = []

    @ObservationIgnored private let logger = Logger.crema("External")

    /// A custom `target` means a test drives the source through `handle(json:)` —
    /// the real DistributedNotificationCenter observer would only add
    /// non-deterministic noise (a stray brightness change during a run), so it is
    /// installed for the production resolver only. Same idiom as the screen-lock
    /// source's injected session reader.
    init(
        target: ((Int) -> SystemHUD.Target?)? = nil,
        onReport: @escaping @MainActor () -> Void = {}
    ) {
        self.target = target ?? Self.resolveTarget
        self.onReport = onReport

        var cont: AsyncStream<SystemHUD>.Continuation!
        // Newest-bounded: a held brightness key emits once per step, and a
        // backlog of stale levels is worth less than the current one.
        updates = AsyncStream(bufferingPolicy: .bufferingNewest(4)) { cont = $0 }
        continuation = cont

        if target == nil { installObserver() }
    }

    deinit {
        if let payloadRelay {
            DistributedNotificationCenter.default().removeObserver(payloadRelay)
        }
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
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
        guard let hud = BetterDisplayOSDTranslation.systemHUD(fromJSON: json, target: target) else { return }
        if !hasReported {
            hasReported = true
            logger.info("BetterDisplay OSD integration is live — drawing screen brightness from it")
        }
        logger.debug("BetterDisplay OSD: brightness \(hud.value, format: .fixed(precision: 2), privacy: .public)")
        continuation.yield(hud)
        onReport()
    }

    /// BetterDisplay went away: whatever it told us stops being true, and the app
    /// must not keep claiming an integration that has no one on the other end.
    ///
    /// A neighbour that quits having never reported — its OSD integration switched
    /// off — is the common case, so the write is guarded: an unchanged one still
    /// invalidates every view reading the claim.
    func noteBetterDisplayTerminated() {
        if hasReported { hasReported = false }
    }

    /// Echoes a level Crema itself asked BetterDisplay to apply. Measured: the app
    /// publishes OSD notifications for changes IT originates, not for the ones
    /// third parties request — so without this echo a drag would leave the bar
    /// frozen at the old level and its revert timer unrefreshed. Deliberately does
    /// NOT count as `hasReported`: our own echo is not evidence that the
    /// neighbour's integration is switched on.
    func noteApplied(_ hud: SystemHUD) {
        continuation.yield(hud)
    }

    private func installObserver() {
        // Registered through the SELECTOR method, and only because it is the one
        // that takes a suspension behaviour. Every block-based cover defaults to
        // `NSNotificationSuspensionBehaviorCoalesce` (`NSDistributedNotificationCenter.h`:
        // "All other registration methods are covers of this one, with the default
        // for suspensionBehavior = NSNotificationSuspensionBehaviorCoalesce"), and
        // a coalesced registration is HELD while the centre is suspended — which
        // AppKit does on its own whenever the app is not active. Crema is an
        // LSUIElement accessory: it is essentially never active, so the brightness
        // bar was asking for the delivery mode that waits for a moment which may
        // never come. Whether it arrives anyway is then the POSTER's choice — the
        // same header says a `deliverImmediately:` post is received as if every
        // registrant had asked for immediate delivery — and the poster here is
        // another app, which is exactly why this side must not depend on it.
        // `.deliverImmediately` is the documented opt-out; the screen-lock edges
        // were moved off the block-based cover for the same reason.
        let relay = DistributedPayloadRelay { [weak self] json in self?.handle(json: json) }
        DistributedNotificationCenter.default().addObserver(
            relay,
            selector: #selector(DistributedPayloadRelay.payloadArrived(_:)),
            name: Notification.Name(Self.notificationName),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        payloadRelay = relay

        // The workspace edge, not BetterDisplay's own `.terminated` notification:
        // that one is documented as not sent on an unexpected quit, and a crash is
        // exactly when a stale "integration is live" claim would linger.
        let workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.bundleID else { return }
            MainActor.assumeIsolated { self?.noteBetterDisplayTerminated() }
        }
        workspaceObservers.append(workspaceObserver)
    }

    /// BetterDisplay reports the raw CGDirectDisplayID; the domain keys displays by
    /// UUID, so identity is resolved here at the border — through the same
    /// translation the panel roster uses, or the two would disagree about which
    /// screen is which and the bar would land on the wrong panel. Every display
    /// goes through it, the built-in included, and one whose UUID does not resolve
    /// is dropped: a bar for a screen the app cannot name is one it can neither
    /// place nor send a drag back to.
    private static func resolveTarget(_ displayID: Int) -> SystemHUD.Target? {
        ScreenTranslation.displayUUID(for: CGDirectDisplayID(displayID)).map { .display($0) }
    }
}
