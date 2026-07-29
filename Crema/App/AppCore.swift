import AppKit
import Foundation
import os
import SwiftUI

// The composition root wires every source, actuator, observer, and cross-object
// seam in one place — cohesive, but past the 500-line warning (like Coordinator
// and the suppressor, which opt out the same way).
// swiftlint:disable file_length

/// Composition root: builds and retains the app's object graph for the whole
/// app lifetime. The default path (Debug and Release) runs the real system
/// sources — volume (Core Audio), both brightnesses, and the now-playing
/// fallback chain (adapter → JXA) with the routing media controller. Debug can
/// swap in the demo sources via a flag.
@MainActor
final class AppCore {
    /// Sources + actuators wired into the Coordinator, plus the brightness
    /// sources the media-key router pokes (nil when running on demo sources).
    private struct SystemGraph {
        let nowPlayingSource: any NowPlayingSource
        let systemHUDSource: any SystemHUDSource
        let nowPlayingController: any NowPlayingController
        let volumeController: any VolumeController
        let screenBrightnessController: any ScreenBrightnessController
        let keyboardBrightnessController: any KeyboardBrightnessController
        let screenBrightnessSampler: (any ManuallySampledSource)?
        let keyboardBrightnessSampler: (any ManuallySampledSource)?
        /// Poked at a volume scale boundary, where the Core Audio write is a
        /// no-op and emits no echo; nil on demo sources.
        let volumeSampler: (any ManuallySampledSource)?
        /// Read-side borders for the OSD suppressor (a consumed key needs the
        /// current value to step from); nil on demo sources.
        let screenBrightnessBackend: (any BrightnessBackend)?
        let keyboardBrightnessBackend: (any BrightnessBackend)?
    }

    let coordinator: Coordinator
    // The collaborators below are wiring detail, private so no second consumer
    // can appear: mediaKeys.updates is a single-consumer AsyncStream — another
    // `for await` would silently split events with the router — and preferences
    // must be written through this core's setters only.
    private let windowManager: WindowManager
    private let preferences: Preferences
    let permissionMonitor: AccessibilityPermissionMonitor
    let nowPlayingMonitor: NowPlayingMonitor
    /// Menu signal for domains whose native-OSD suppression stayed
    /// unrecoverable long enough to escalate — a failed apply suspends only its
    /// own domain, not all three. (docs/DECISIONS.md: per-domain-suspension)
    let osdSuppressionMonitor = OSDSuppressionMonitor()
    private let mediaKeys: any MediaKeySource
    /// Zero-latency brightness HUD via the tap; nil when on demo sources.
    private let mediaKeyRouter: MediaKeyHUDRouter?
    /// Native-OSD suppression (opt-in): nil when the graph lacks the
    /// real borders (demo sources) or the key source cannot consume — the
    /// Settings toggle then persists the wish but nothing engages.
    let osdSuppressor: (any NativeOSDSuppressor)?
    /// Lock-aware engagement policy for the suppressor: suspends suppression
    /// while the screen is locked or off-console (native OSD restored), and
    /// re-engages on return iff the preference is on. Nil alongside a nil
    /// suppressor — nothing to lock-guard.
    private let suppressionLockController: SuppressionLockController?
    /// Launch-at-login control (SMAppService behind a protocol).
    let loginItem: any LoginItemManaging
    #if DEBUG
    /// Present only when running on the demo sources (CremaUseDemoSources).
    let demo: DemoEngine?
    /// Debug-only side-channel that logs the adapter's raw JSON lines for
    /// inspection, independent of the real now-playing chain wired into the
    /// Coordinator (CremaObserveAdapter flag).
    private var adapterObserver: MediaRemoteAdapterProcess?
    private var adapterObserverTermination: NSObjectProtocol?
    #endif

    private let accessibilityPermission = AXAccessibilityPermission()
    /// The now-playing chain (real graph only); stopped on quit so its Perl
    /// process dies with the app.
    private let nowPlayingChain: ChainedNowPlayingSource?
    private var screenObservation: NSObjectProtocol?
    private var terminationObservation: NSObjectProtocol?
    /// Display/system wake observers that reinstall the media-key tap: a
    /// display-sleep/wake can leave the tap enabled with a valid port yet
    /// silently not delivering, and it fires no unlock edge for the lock-edge
    /// reinstall to see — these close that gap. Retained for the app lifetime
    /// alongside the tap. (docs/DECISIONS.md: J7-estado-do-outro-lado)
    private var wakeObservations: [NSObjectProtocol] = []
    private var onboardingWindow: NSWindow?

    // The composition root wires every source, actuator, and observer; long by nature.
    // swiftlint:disable:next function_body_length
    init(loginItem: (any LoginItemManaging)? = nil) {
        let preferences = Preferences()
        self.preferences = preferences
        // Constructed here, not as a default argument: SMAppServiceLoginItem is
        // @MainActor and a default argument is evaluated in a nonisolated context.
        self.loginItem = loginItem ?? SMAppServiceLoginItem()

        permissionMonitor = AccessibilityPermissionMonitor(permission: accessibilityPermission)
        permissionMonitor.start()
        // Kept as the concrete type too: the unlock-edge tap reinstall needs to
        // call `reinstallTap()`, which is not on the MediaKeySource protocol.
        let tapSource = CGEventTapMediaKeySource(permission: accessibilityPermission)
        mediaKeys = tapSource

        let nowPlayingMonitor = NowPlayingMonitor()
        self.nowPlayingMonitor = nowPlayingMonitor
        // The chain reports its active state off-main; hop to the monitor.
        let onNowPlayingActive: @Sendable (Bool) -> Void = { active in
            Task { @MainActor in nowPlayingMonitor.setActive(active) }
        }

        let graph: SystemGraph
        let chain: ChainedNowPlayingSource?
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "CremaUseDemoSources") {
            let demo = DemoEngine()
            self.demo = demo
            chain = nil
            graph = Self.makeDemoGraph(demo)
        } else {
            self.demo = nil
            let builtChain = Self.makeNowPlayingChain(onActiveChange: onNowPlayingActive)
            chain = builtChain
            graph = Self.makeRealGraph(
                nowPlayingSource: builtChain,
                nowPlayingController: RoutingNowPlayingController(activeChannel: { builtChain.activeCommandChannel() })
            )
        }
        #else
        let builtChain = Self.makeNowPlayingChain(onActiveChange: onNowPlayingActive)
        chain = builtChain
        graph = Self.makeRealGraph(
            nowPlayingSource: builtChain,
            nowPlayingController: RoutingNowPlayingController(activeChannel: { builtChain.activeCommandChannel() })
        )
        #endif
        nowPlayingChain = chain

        coordinator = Coordinator(
            nowPlayingSource: graph.nowPlayingSource,
            systemHUDSource: graph.systemHUDSource,
            nowPlayingController: graph.nowPlayingController,
            volumeController: graph.volumeController,
            screenBrightnessController: graph.screenBrightnessController,
            keyboardBrightnessController: graph.keyboardBrightnessController,
            // Seed the live behavior from the persisted Settings.
            ignoresBrowserMedia: !preferences.includesBrowserMedia,
            reactiveNowPlaying: preferences.reactiveNowPlaying
        )

        // Route the chain's active-source-ended signal into the Coordinator so
        // a dead source's stale snapshot is dropped rather than resurrected;
        // wired here because the Coordinator is built after the chain (rationale
        // on the seam). (docs/DECISIONS.md: ghost-discard)
        if let chain {
            Self.wireActiveSourceEnded(from: chain, to: coordinator)
        }

        // The tap feeds only the brightness sources (see MediaKeyHUDRouter);
        // absent on demo sources, where there is nothing to poke.
        if let screenSampler = graph.screenBrightnessSampler,
           let keyboardSampler = graph.keyboardBrightnessSampler {
            let router = MediaKeyHUDRouter(
                mediaKeys: mediaKeys,
                screenBrightness: screenSampler,
                keyboardBrightness: keyboardSampler
            )
            router.start()
            mediaKeyRouter = router
        } else {
            mediaKeyRouter = nil
        }

        windowManager = WindowManager(coordinator: coordinator, preferences: preferences) { screen, style, coordinator in
            NSPanelPresentationPanel(screen: screen, style: style, coordinator: coordinator)
        }

        coordinator.start()
        windowManager.start()
        windowManager.updateScreens(ScreenTranslation.describeAll())

        let windowManager = self.windowManager
        screenObservation = Self.wireScreenParameterReinstall(
            center: .default,
            reinstalling: tapSource
        ) {
            windowManager.updateScreens(ScreenTranslation.describeAll())
        }

        // Kill the adapter's Perl process on quit — deinit does not run reliably
        // on process exit, so stop the chain synchronously here.
        terminationObservation = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [chain] _ in
            chain?.stop()
        }

        // Recover the tap on display/system wake, independent of the lock edge and
        // of the suppressor. The ENABLED-but-deaf failure (tap valid and enabled
        // yet silently unregistered server-side, invisible to any local check)
        // also strikes after a plain display-sleep/wake with no lock — which fires
        // no unlock edge, so the SuppressionLockController hook below cannot see
        // it (docs/DECISIONS.md: J7-estado-do-outro-lado). reinstallTap is
        // convergent — safe to call repeatedly (it mints a fresh port each call but
        // preserves the consumer by construction) — and no-ops without permission,
        // so an extra trigger is safe; it also recovers plain observation (the
        // brightness HUD) when the suppressor is absent or the pref is off. Wired
        // on the concrete tap, which always exists, so wake recovery never depends
        // on the suppressor graph.
        wakeObservations = Self.wireWakeReinstall(
            center: NSWorkspace.shared.notificationCenter,
            reinstalling: tapSource
        )

        if let consuming = mediaKeys as? any MediaKeyConsuming,
           let screenBackend = graph.screenBrightnessBackend,
           let keyboardBackend = graph.keyboardBrightnessBackend {
            let suppressor = MediaKeyInterceptionOSDSuppressor(
                keys: consuming,
                volume: CoreAudioOSDVolumeChannel(controller: graph.volumeController),
                screen: ScreenBrightnessOSDChannel(backend: screenBackend, controller: graph.screenBrightnessController),
                keyboard: KeyboardBrightnessOSDChannel(backend: keyboardBackend, controller: graph.keyboardBrightnessController)
            )
            osdSuppressor = suppressor
            // Surface long-suspended domains in the menu. The suppressor fires
            // this on escalation and on recovery; the monitor is pull-read by
            // CremaApp, so a transient suspension that heals never shows.
            let monitor = osdSuppressionMonitor
            suppressor.onSuspensionStateChange = { [weak suppressor] in
                monitor.update(suppressor?.longSuspendedDomains ?? [])
            }
            // Suppression is only ever engaged through the lock controller, so a
            // locked/off-console context suspends it (native OSD restored) and
            // the lock path never touches the persisted opt-in.
            let lockController = SuppressionLockController(
                suppressor: suppressor,
                lockSource: DistributedNotificationScreenLockSource(),
                preferences: preferences
            )
            // Recover the ENABLED-but-deaf tap on the unlock edge: after a
            // lock/display-sleep/unlock the tap can keep a valid, enabled port
            // that silently stops delivering events, so reinstalling preventively
            // on unlock is the deterministic fix. Runs even with the pref off (the
            // deafness kills plain observation too). Pinned by
            // SuppressionUnlockReinstallSeamTests.
            // (docs/DECISIONS.md: J7-estado-do-outro-lado / preventive-reinstall)
            //
            // This hook is co-gated with the suppressor, but the real graph mints
            // router and suppressor together (makeRealGraph wires both), so
            // observation is never actually stranded here — and the wake-edge
            // reinstall above, tied to the tap not the suppressor, is the
            // unconditional path that would still cover a future
            // router-without-suppressor graph.
            Self.wireUnlockReinstall(from: lockController, to: tapSource)
            suppressionLockController = lockController
        } else {
            osdSuppressor = nil
            suppressionLockController = nil
        }

        presentAccessibilityOnboardingIfFirstLaunch()

        // Post-apply poke: the router's key-time sample shows the HUD with
        // the pre-apply value (with the key consumed, the app's write lands
        // after it) — this second sample refreshes it to the applied value.
        if let screenSampler = graph.screenBrightnessSampler,
           let keyboardSampler = graph.keyboardBrightnessSampler,
           let volumeSampler = graph.volumeSampler {
            osdSuppressor?.onApplied = { key in
                switch key {
                case .screenBrightnessUp, .screenBrightnessDown:
                    screenSampler.sample()
                case .keyboardBrightnessUp, .keyboardBrightnessDown:
                    keyboardSampler.sample()
                case .volumeUp, .volumeDown:
                    // A consumed key at the scale boundary is a no-op write that
                    // fires no Core Audio echo; the sampler re-reads and emits
                    // there so the HUD still shows (mid-scale the echo covers it,
                    // and the sampler no-ops off the boundary — no double-fire).
                    volumeSampler.sample()
                case .mute:
                    break   // a real toggle: Core Audio always echoes it
                }
            }
        }
        // Slider-driven brightness writes do not echo the way Core Audio volume
        // does, so the Coordinator asks us to poke the matching sampler after a
        // successful write — it re-reads and emits the applied value, closing the
        // HUD loop (indicator follows, revert timer refreshes) exactly like the
        // media-key router and the suppressor's post-apply poke. Absent on demo
        // sources, where the demo HUD is already event-driven end to end.
        if let screenSampler = graph.screenBrightnessSampler,
           let keyboardSampler = graph.keyboardBrightnessSampler {
            coordinator.onBrightnessApplied = { kind in
                switch kind {
                case .screenBrightness: screenSampler.sample()
                case .keyboardBrightness: keyboardSampler.sample()
                case .volume: break   // volume echoes itself; never routed here
                }
            }
        }
        // The preference persists across launches: suppression is a real
        // opt-in feature, and its reversibility never depends on state — the
        // tap dies with the process. start() engages to the correct initial
        // state (suspended when launched while locked; off unless the opt-in is
        // set) and begins consuming lock transitions.
        suppressionLockController?.start()

        #if DEBUG
        startAdapterObservationIfRequested()
        #endif
    }

    /// Wires the chain's ghost-discard seam: when its active source dies without
    /// the outer stream finishing, the Coordinator drops the stale snapshot
    /// rather than resurrect dead media. Standalone and static so the exact
    /// production wiring is pinned by a test — the isolated halves never exercise
    /// it. (docs/DECISIONS.md: ghost-discard)
    static func wireActiveSourceEnded(from chain: ChainedNowPlayingSource, to coordinator: Coordinator) {
        chain.setActiveSourceEndedHandler { [weak coordinator] in
            Task { @MainActor in coordinator?.activeNowPlayingSourceEnded() }
        }
    }

    /// Wires the wake pair (the 1st and 2nd reinstall triggers of the family —
    /// docs/DECISIONS.md: preventive-reinstall): display and system wake can
    /// leave the tap ENABLED-but-deaf, and a plain display-sleep/wake fires no
    /// lock edge, so the unlock seam below cannot cover it. Standalone and
    /// static so a seam test pins the join (post the notification → reinstall)
    /// through the exact production wiring; the injected center keeps the test
    /// isolated from the process's real workspace notifications. Delivered on
    /// the main queue so the reinstall runs on the tap's own thread —
    /// teardown/create never races a delivered event. Returns the observer
    /// tokens AppCore retains.
    static func wireWakeReinstall(
        center: NotificationCenter,
        reinstalling source: CGEventTapMediaKeySource
    ) -> [NSObjectProtocol] {
        [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak source] _ in
                source?.reinstallTap()
            }
        }
    }

    /// Wires the unlock-edge tap reinstall: on return from lock/off-console the
    /// controller fires `onUnlocked`, which physically reinstalls the media-key
    /// tap (fresh mach port, consumer preserved) before re-engaging suppression.
    /// Standalone and static so a seam test pins the exact production wiring —
    /// the isolated halves (the controller's edge, the source's reinstall) never
    /// exercise the join. A lock/display-sleep cycle can leave the tap enabled
    /// with a valid port yet silently unregistered server-side — no local check
    /// can see it, so reinstall preventively on this edge.
    /// (docs/DECISIONS.md: J7-estado-do-outro-lado)
    static func wireUnlockReinstall(from controller: SuppressionLockController, to source: CGEventTapMediaKeySource) {
        controller.onUnlocked = { [weak source] in source?.reinstallTap() }
    }

    /// Wires the display-topology observer: `didChangeScreenParameters` refreshes
    /// the panels (`onScreenChange`) and reinstalls the media-key tap. A display
    /// hotplug with no sleep fires only this notification — no wake, no lock/unlock
    /// edge — yet the WindowServer reconfiguration can re-route event delivery the
    /// same ENABLED-but-deaf way display-sleep/wake does (valid enabled port that
    /// silently stops delivering), so this is the 4th reinstall trigger of that
    /// family (docs/DECISIONS.md: J7-estado-do-outro-lado) — didWake, screensDidWake, and the
    /// unlock edge being the other three). reinstallTap is convergent, idempotent
    /// and permission-gated, so the extra trigger carries no risk and closes a gap
    /// no wake or lock edge would reach. Standalone and static so a seam test pins
    /// the reinstall trigger (post the notification → reinstall) without booting
    /// the whole graph. Returns the observer token AppCore retains.
    static func wireScreenParameterReinstall(
        center: NotificationCenter,
        reinstalling source: CGEventTapMediaKeySource,
        onScreenChange: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak source] _ in
            // Delivered on the main queue so the reinstall runs on the tap's own
            // thread — its teardown/create never races a delivered event, the same
            // reason the wake observers reinstall on `.main`.
            source?.reinstallTap()
            Task { @MainActor in onScreenChange() }
        }
    }

    /// Persists the opt-in and engages/disengages the suppressor. Called by the
    /// Settings toggle. Routed through the lock controller so a toggle-on while
    /// locked persists the wish but defers engagement to unlock; when there is
    /// no suppressor to control, the wish is still persisted.
    func setNativeOSDSuppression(_ enabled: Bool) {
        if let suppressionLockController {
            suppressionLockController.setPreferredSuppression(enabled)
        } else {
            preferences.suppressesNativeOSD = enabled
        }
    }

    /// The menu's "try to reactivate now" action: forces an immediate recovery
    /// probe of every suspended suppression domain, ahead of the backoff.
    func retryOSDSuppression() {
        osdSuppressor?.retrySuspendedNow()
    }

    // MARK: - Settings (live preference changes)

    /// The style of the main display — the value the all-displays picker shows.
    func currentStyle() -> Style {
        let screens = ScreenTranslation.describeAll()
        let id = screens.first(where: { $0.isInternal })?.id ?? screens.first?.id
        return id.map { preferences.style(for: $0) } ?? .notch
    }

    /// Applies one style to every connected display and swaps the panels — the
    /// core (Sources/Domain/Coordinator) is untouched. Per-display styling can
    /// layer on top later; this is the "all displays" entry.
    func setStyleEverywhere(_ style: Style) {
        for screen in ScreenTranslation.describeAll() {
            preferences.setStyle(style, for: screen.id)
        }
        windowManager.refreshStyles()
    }

    /// Quiet vs reactive now playing — persisted and applied to the live
    /// Coordinator at once.
    func setReactiveNowPlaying(_ reactive: Bool) {
        preferences.reactiveNowPlaying = reactive
        coordinator.setReactiveNowPlaying(reactive)
    }

    /// Include browser media or not — persisted and applied live (the
    /// Coordinator consumes the inverse).
    func setIncludesBrowserMedia(_ includes: Bool) {
        preferences.includesBrowserMedia = includes
        coordinator.setIgnoresBrowserMedia(!includes)
    }

    /// View-only vs full controls — persisted and re-applied to the panels
    /// (render context only; no window geometry changes).
    func setShowsPlaybackControls(_ shows: Bool) {
        preferences.showsPlaybackControls = shows
        windowManager.refreshPresentation()
    }

    /// The HUD level-indicator appearance (Card only) — persisted and re-applied
    /// to the panels (render context only; no window geometry changes).
    func setHUDIndicatorStyle(_ style: HUDIndicatorStyle) {
        preferences.hudIndicatorStyle = style
        windowManager.refreshPresentation()
    }

    /// Applies the launch-at-login intent and returns the real resulting state
    /// (the view stays an intent-reporter, like every other Settings control).
    /// `enabled` includes requires-approval so the toggle stays on with the
    /// approval note instead of snapping off. The SMAppService error is logged
    /// here: the snap-back tells the user it failed, the log says why —
    /// registration failures are a real field scenario under self-signed
    /// distribution, and the toggle alone cannot distinguish the causes.
    func setLaunchesAtLogin(_ enabled: Bool) -> (enabled: Bool, needsApproval: Bool) {
        do {
            try loginItem.setEnabled(enabled)
        } catch {
            Logger.crema("App").error("login-item registration failed: \(error, privacy: .public)")
        }
        return (loginItem.isEnabled || loginItem.requiresApproval, loginItem.requiresApproval)
    }

    // MARK: - Accessibility onboarding

    /// Requests the permission (system prompt registers the app in the
    /// Accessibility list) and deep-links to the exact Settings pane.
    func requestAccessibilityAccess() {
        accessibilityPermission.requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func presentAccessibilityOnboarding() {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = AccessibilityOnboardingView(
            monitor: permissionMonitor,
            openSettings: { [weak self] in self?.requestAccessibilityAccess() },
            dismiss: { [weak self] in self?.closeAccessibilityOnboarding() }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable]
        window.title = String(localized: "onboarding.title", defaultValue: "Crema needs Accessibility access")
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentAccessibilityOnboardingIfFirstLaunch() {
        guard !accessibilityPermission.isGranted(), !preferences.hasSeenAccessibilityOnboarding else { return }
        preferences.hasSeenAccessibilityOnboarding = true
        presentAccessibilityOnboarding()
    }

    private func closeAccessibilityOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    // MARK: - Graph builders

    /// The default graph: real system HUD sources + actuators, the now-playing
    /// fallback chain, and the routing media controller (commands follow the
    /// active backend). The screen/keyboard brightness sources are shared between
    /// the merged HUD stream and the media-key router (same instances, so a poke
    /// emits into the stream the Coordinator consumes).
    private static func makeRealGraph(
        nowPlayingSource: any NowPlayingSource,
        nowPlayingController: any NowPlayingController
    ) -> SystemGraph {
        let volumeSource = CoreAudioVolumeSource()

        let screenBridge = DisplayServicesBridge()
        let screenSource = PolledBrightnessSource(kind: .screenBrightness, backend: screenBridge)

        let keyboardBridge = CoreBrightnessKeyboardBridge()
        let keyboardSource = PolledBrightnessSource(kind: .keyboardBrightness, backend: keyboardBridge)

        return SystemGraph(
            nowPlayingSource: nowPlayingSource,
            systemHUDSource: MergedSystemHUDSource([volumeSource, screenSource, keyboardSource]),
            nowPlayingController: nowPlayingController,
            volumeController: CoreAudioVolumeController(),
            screenBrightnessController: DisplayServicesScreenBrightnessController(backend: screenBridge),
            keyboardBrightnessController: CoreBrightnessKeyboardBrightnessController(backend: keyboardBridge),
            screenBrightnessSampler: screenSource,
            keyboardBrightnessSampler: keyboardSource,
            volumeSampler: volumeSource,
            screenBrightnessBackend: screenBridge,
            keyboardBrightnessBackend: keyboardBridge
        )
    }

    /// The now-playing chain: adapter first (covers browsers), JXA fallback
    /// (Spotify/Music only), else off. Each candidate is a factory so the chain
    /// can rebuild a dead source on self-heal.
    private static func makeNowPlayingChain(onActiveChange: @escaping @Sendable (Bool) -> Void) -> ChainedNowPlayingSource {
        var candidates: [NowPlayingCandidate] = []

        if let paths = MediaRemoteAdapterPaths.inBundle() {
            let probe = MediaRemoteAdapterProbe(paths: paths)
            #if DEBUG
            let adapterDisabled = UserDefaults.standard.bool(forKey: "CremaDisableAdapter")
            #else
            let adapterDisabled = false
            #endif
            candidates.append(NowPlayingCandidate(
                isAvailable: { adapterDisabled ? false : await probe.isAvailable() },
                makeSource: { MediaRemoteAdapterNowPlayingSource(paths: paths) },
                commandChannel: MediaRemoteAdapterCommandChannel(paths: paths),
                label: "adapter"
            ))
        } else {
            // A missing vendored adapter (broken embed phase, stripped Resources)
            // silently reduces the chain to JXA while the menu still reads
            // "active" — this line is the only trace a field report can start from.
            Logger.crema("NowPlaying")
                .error("mediaremote-adapter resources missing from the bundle; now-playing chain degrades to JXA only")
        }

        candidates.append(NowPlayingCandidate(
            isAvailable: { await JXANowPlayingSource.probeAvailability() },
            makeSource: { JXANowPlayingSource() },
            commandChannel: JXACommandChannel(),
            label: "jxa"
        ))

        return ChainedNowPlayingSource(candidates: candidates, onActiveChange: onActiveChange)
    }

    #if DEBUG
    /// Debug-only graph on the demo engine — exercises the UI without hardware
    /// or real media. No samplers: demo HUDs come from menu buttons, not the tap.
    private static func makeDemoGraph(_ demo: DemoEngine) -> SystemGraph {
        SystemGraph(
            nowPlayingSource: demo.media,
            systemHUDSource: demo.hud,
            nowPlayingController: demo.media,
            volumeController: demo.hud,
            screenBrightnessController: demo.hud,
            keyboardBrightnessController: demo.hud,
            screenBrightnessSampler: nil,
            keyboardBrightnessSampler: nil,
            volumeSampler: nil,
            screenBrightnessBackend: nil,
            keyboardBrightnessBackend: nil
        )
    }

    /// With CremaObserveAdapter set, spawn the adapter stream and log every raw
    /// line so its output can be observed in Console. The Perl process is killed
    /// on app termination so no zombie survives.
    private func startAdapterObservationIfRequested() {
        guard UserDefaults.standard.bool(forKey: "CremaObserveAdapter"),
              let paths = MediaRemoteAdapterPaths.inBundle() else { return }

        let logger = Logger.crema("NowPlaying")
        let observer = MediaRemoteAdapterProcess(paths: paths)
        adapterObserver = observer

        Task {
            let available = await MediaRemoteAdapterProbe(paths: paths).isAvailable()
            logger.info("adapter observation: isAvailable=\(available, privacy: .public)")
            observer.start()
            for await line in observer.rawLines {
                logger.info("adapter » \(line, privacy: .public)")
            }
            logger.info("adapter stream finished (EOF/exit)")
        }

        adapterObserverTermination = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak observer] _ in
            observer?.stop()
        }
    }
    #endif
}
