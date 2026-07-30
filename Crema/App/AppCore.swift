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
        /// Kept beyond the merge so the menu can say whether the neighbour is
        /// actually reporting; nil on demo sources.
        let betterDisplaySource: BetterDisplayOSDSource?
        /// Writes for bars the neighbour drew; nil on demo sources.
        let externalScreenBrightnessController: (any ScreenBrightnessController)?
    }

    let coordinator: Coordinator
    // The collaborators below are wiring detail, private so no second consumer can
    // appear: mediaKeys.updates is a single-consumer AsyncStream, and another
    // `for await` would silently split events with the router.
    //
    // `preferences` being private does NOT mean this core is the only writer — the
    // Settings view writes five of them straight through @AppStorage, and
    // Preferences exposes those raw keys on purpose for exactly that. The real
    // contract is the other way round: the persisted key is the source of truth,
    // @AppStorage does the writing, and a setter here exists to apply the LIVE
    // effect the write cannot. Which is why every new Settings control owes an
    // `.onChange` calling into this core — without it the value persists and
    // nothing happens until relaunch.
    private let windowManager: WindowManager
    private let preferences: Preferences
    let permissionMonitor: AccessibilityPermissionMonitor
    /// Automation (Apple Events) state for the Permissions row. NOT started at
    /// launch and never read by the menu: each pass is a blocking consent-daemon
    /// round trip per player, nothing outside that row depends on the answer (the
    /// JXA fallback finds out by trying), and a state the menu read would rebuild
    /// that menu — re-running the tap-chain read on `mediaKeyChainNotice()`, which
    /// zeroes every tap's latency counters system-wide. Settings starts and stops
    /// it with the tab; the intents live in AppCoreAutomation.swift.
    /// (docs/DECISIONS.md: automation-is-fallback-only)
    let automationMonitor = AutomationPermissionMonitor()
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
    /// Read only from the menu's content build, never on a poll — and that build is
    /// not the same thing as the user opening the menu, which is why the reading
    /// goes through the coalescing window below instead of happening once per
    /// rebuild (cost on `mediaKeyChainNotice()`).
    private let eventTapRegistry: any EventTapRegistry = LiveEventTapRegistry()
    /// That window. Non-observable by design: it is filled from inside a view body,
    /// and observed state written there would be mutation driven by rendering
    /// (rationale on the type).
    private let chainNoticeCache = MediaKeyChainNotice.Cache()
    /// Kept past the merge so the menu can report whether the neighbour's OSD
    /// integration is actually feeding us; nil on demo sources.
    private let betterDisplaySource: BetterDisplayOSDSource?
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
            externalScreenBrightnessController: graph.externalScreenBrightnessController,
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
        betterDisplaySource = graph.betterDisplaySource

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
        let screens = ScreenTranslation.describeAll()
        // Before the first panel roster: an install that predates the global
        // style declaration carries the user's choice only in per-display keys,
        // and adopting it after the roster would build every panel on the
        // shipped default and swap them a beat later.
        // (docs/DECISIONS.md: global-style-default)
        preferences.adoptDeclaredStyleFromOverrides(preferring: Self.styleAuthorityOrder(screens))
        windowManager.updateScreens(screens)

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
        // No center argument: the default IS the production one, so the wiring
        // cannot be pointed at a center nobody posts to by editing this line.
        wakeObservations = Self.wireWakeReinstall(reinstalling: tapSource)

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

        // The one moment the persisted login-item intent is reconciled against
        // reality: an item the user removed themselves is forgotten here, at a
        // lifecycle edge, because forgetting is a WRITE and the only other reader
        // of that verdict is a view body (rationale on reconcileLoginItemIntent).
        reconcileLoginItemIntent()

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
        Self.wireBrightnessEcho(to: coordinator, graph: graph)
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
    /// The two wake edges, named once. They are workspace notifications: they are
    /// posted on NSWorkspace's own center and never appear on
    /// `NotificationCenter.default`, so wiring them to the wrong center arms
    /// nothing — and arms it silently, since a tap that stopped delivering looks
    /// identical to an idle one from inside this process.
    static let wakeReinstallNames = [
        NSWorkspace.screensDidWakeNotification,
        NSWorkspace.didWakeNotification,
    ]

    static func wireWakeReinstall(
        center: NotificationCenter = NSWorkspace.shared.notificationCenter,
        reinstalling source: CGEventTapMediaKeySource
    ) -> [NSObjectProtocol] {
        wakeReinstallNames.map { name in
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

    /// The value the all-displays picker shows: what the leading display has
    /// DECLARED — the global declaration, unless that display still carries a
    /// legacy per-display override. Never what it draws: no geometry enters here,
    /// which is why a style-scoped control gates on `rendersAnywhere` instead
    /// (docs/DECISIONS.md: global-style-default).
    func currentStyle() -> Style {
        let leading = Self.styleAuthorityOrder(ScreenTranslation.describeAll()).first
        return leading.map { preferences.style(for: $0) } ?? preferences.declaredStyle
    }

    /// Whether any connected display RENDERS this style — the gate for
    /// style-scoped Settings controls, and deliberately not `currentStyle()`:
    /// that reports the declaration, and on a Mac without a notch the shipped
    /// default declares notch while every panel draws card, which left the
    /// Card-only indicator picker gray with the HUD it governs on screen
    /// (docs/DECISIONS.md: rendered-style-gates-settings).
    func rendersAnywhere(_ style: Style) -> Bool {
        windowManager.renders(style)
    }

    /// The "all displays" entry: declares the style globally and drops the
    /// per-display overrides, so a display connected LATER inherits it too —
    /// writing only the attached displays is what left a monitor plugged in
    /// afterwards on the shipped default while Settings promised "Applies to
    /// every display" (docs/DECISIONS.md: global-style-default). Panels are then
    /// swapped from the re-resolved styles; the core
    /// (Sources/Domain/Coordinator) is untouched.
    func setStyleEverywhere(_ style: Style) {
        preferences.declareStyleEverywhere(style)
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
    /// approval note instead of snapping off. Attempt and bookkeeping live in
    /// `applyLaunchesAtLogin`, where the write rule a test has to pin lives too.
    func setLaunchesAtLogin(_ enabled: Bool) -> (enabled: Bool, needsApproval: Bool) {
        Self.applyLaunchesAtLogin(
            enabled,
            to: loginItem,
            preferences: preferences,
            currentBuild: Self.currentBuild
        )
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

        // Wired unconditionally: with BetterDisplay absent the source never emits,
        // and with it present it is the ONLY brightness HUD Crema can draw for the
        // keys BetterDisplay takes first (docs/DECISIONS.md:
        // media-key-chain-contention). `standDown` covers the one press where both
        // could speak — suppression off, so Crema's tap observes the key and arms
        // its poll while the neighbour is the one that applies and reports.
        let betterDisplaySource = BetterDisplayOSDSource(onReport: { screenSource.standDown() })
        // The way back: BetterDisplay applies what a drag on ITS bar asks for, on
        // the same scale it reported. Wired unconditionally like the source — with
        // the app absent the command simply goes unanswered and the drag reports a
        // failed apply, which is what an unreachable actuator is.
        let betterDisplayBrightness = BetterDisplayScreenBrightnessController(
            channel: BetterDisplayCommandChannel(),
            displayID: BetterDisplayScreenBrightnessController.liveDisplayID
        )

        return SystemGraph(
            nowPlayingSource: nowPlayingSource,
            systemHUDSource: MergedSystemHUDSource([
                volumeSource, screenSource, keyboardSource, betterDisplaySource,
            ]),
            nowPlayingController: nowPlayingController,
            volumeController: CoreAudioVolumeController(),
            screenBrightnessController: DisplayServicesScreenBrightnessController(backend: screenBridge),
            keyboardBrightnessController: CoreBrightnessKeyboardBrightnessController(backend: keyboardBridge),
            screenBrightnessSampler: screenSource,
            keyboardBrightnessSampler: keyboardSource,
            volumeSampler: volumeSource,
            screenBrightnessBackend: screenBridge,
            keyboardBrightnessBackend: keyboardBridge,
            betterDisplaySource: betterDisplaySource,
            externalScreenBrightnessController: betterDisplayBrightness
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
            keyboardBrightnessBackend: nil,
            betterDisplaySource: nil,
            externalScreenBrightnessController: nil
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

// MARK: - Launch at login

@MainActor
extension AppCore {
    /// The attempt and its bookkeeping, standalone and static so a test pins the
    /// write rule without booting the graph (same reason as the reinstall seams).
    /// The SMAppService error is logged here: the snap-back tells the user it
    /// failed, the log says why — registration failures are a real field scenario
    /// under self-signed distribution, and the toggle alone cannot distinguish the
    /// causes.
    ///
    /// The intent, and the build it was recorded under, is written ONLY when the
    /// call did not throw. The build stamp is the discriminator the revocation
    /// warning rests on, so stamping a FAILED enable with the current build makes
    /// the next reading say "gone under the same build" and file the user's own
    /// request away as their own removal — the app then neither opens at login nor
    /// has anything left to say, which is precisely the silent loss the intent
    /// exists to catch. The failed one-click repair of a revoked registration is
    /// that path. A failed disable keeps the intent for the mirror reason: the
    /// registration it could not remove is still there.
    /// (docs/DECISIONS.md: login-item-intent, pref-sacred)
    ///
    /// A non-throwing call parked for approval still records — the user asked, and
    /// that is the fact worth remembering. The resulting status deliberately does
    /// NOT gate the write: BTM can lag the call, and reading a not-yet-settled
    /// status as failure would drop a real intent and blind the warning for good.
    static func applyLaunchesAtLogin(
        _ enabled: Bool,
        to loginItem: any LoginItemManaging,
        preferences: Preferences,
        currentBuild: String
    ) -> (enabled: Bool, needsApproval: Bool) {
        do {
            try loginItem.setEnabled(enabled)
            preferences.launchesAtLogin = enabled
            preferences.launchesAtLoginBuild = enabled ? currentBuild : nil
        } catch {
            Logger.crema("App").error("login-item registration failed: \(error, privacy: .public)")
        }
        return (loginItem.isEnabled || loginItem.requiresApproval, loginItem.requiresApproval)
    }

    /// What the menu bar should say about launch-at-login right now. Standalone and
    /// static so a test pins the read — including its purity — without booting the
    /// graph (same reason as the reinstall seams). Called from `menuStatus`, which
    /// takes the ONE `loginItem.status` reading the menu is allowed per rebuild and
    /// derives both this warning and the "opens at login" row from it; the read-only
    /// contract that governs it lives there.
    static func loginItemOutcome(
        preferences: Preferences,
        status: LoginItemStatus,
        currentBuild: String
    ) -> LoginItemReconciler.Outcome {
        LoginItemReconciler.outcome(
            intends: preferences.launchesAtLogin,
            recordedBuild: preferences.launchesAtLoginBuild,
            currentBuild: currentBuild,
            status: status
        )
    }

    /// Launch-time bookkeeping, called once from init: an intent the user revoked
    /// themselves in System Settings is forgotten, so a later build change cannot
    /// re-file their own removal as a macOS revocation and warn about it.
    ///
    /// A lifecycle seam rather than part of the menu's read, because forgetting is
    /// a write and that read is a view body. Nothing user-visible waits on it:
    /// `.userRemoved` already renders as silence, so running it at launch costs
    /// only the promptness of the bookkeeping — and every build change the warning
    /// could speak about arrives with a relaunch.
    func reconcileLoginItemIntent() {
        _ = Self.reconcileLoginItemIntent(
            preferences: preferences,
            status: loginItem.status,
            currentBuild: Self.currentBuild
        )
    }

    /// The write, standalone and static so a test pins it without booting the
    /// graph. It lives here and not in the reconciler so the decision stays pure:
    /// forgetting an intent the user themselves revoked is bookkeeping, not policy.
    static func reconcileLoginItemIntent(
        preferences: Preferences,
        status: LoginItemStatus,
        currentBuild: String
    ) -> LoginItemReconciler.Outcome {
        let outcome = Self.loginItemOutcome(
            preferences: preferences,
            status: status,
            currentBuild: currentBuild
        )
        if outcome == .userRemoved {
            preferences.launchesAtLogin = false
            preferences.launchesAtLoginBuild = nil
            Logger.crema("App").info("login item removed outside the app — intent cleared")
        }
        return outcome
    }

    /// The one-click repair behind the menu warning. Re-registering is only ever
    /// reachable from this explicit user action — never from the launch path.
    func reactivateLoginItem() {
        _ = setLaunchesAtLogin(true)
    }

    /// Deep-links to the pane that owns the approval macOS is waiting for.
    func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The build the app is running as — the generation stamp for the intent.
    /// Missing key is impossible in a built bundle; the empty fallback keeps the
    /// comparison total (and reads as "changed" against any recorded build).
    private static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }
}

// MARK: - Accessibility onboarding

/// Its own extension for the same reason the graph builders keep theirs — and it
/// is what holds the class body inside the type_body_length ceiling, which the
/// composition root leans on with every feature wired into it. In THIS file and
/// not another: `presentAccessibilityOnboardingIfFirstLaunch` is private and is
/// called from `init`, and SE-0169 grants that only to a same-file extension.
@MainActor
extension AppCore {
    /// Requests the permission (system prompt registers the app in the
    /// Accessibility list) and deep-links to the exact Settings pane.
    func requestAccessibilityAccess() {
        Self.requestAccessibility(accessibilityPermission, thenOpenSettings: {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        })
    }

    /// Standalone and static so a test pins the sequence without booting the
    /// graph (same reason as the login-item and wake seams). The ORDER is the
    /// contract, not a detail: the prompt is what registers the app in the
    /// Accessibility list, so opening the pane first — or without asking at all —
    /// lands the user on a list Crema is not in, with nothing to switch on.
    static func requestAccessibility(_ permission: any AccessibilityPermission, thenOpenSettings: () -> Void) {
        permission.requestAccess()
        thenOpenSettings()
    }

    func presentAccessibilityOnboarding() {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
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
        NSApp.activate()
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
}

// MARK: - Media-key chain

@MainActor
extension AppCore {
    /// The app that is fed the media keys before Crema, when there is one. Nil
    /// means nothing is positioned to take them from us — or that we have no tap
    /// to speak of, in which case the Accessibility warning already says so.
    ///
    /// Pull-based, read where the menu's content is built and never on a poll: the
    /// answer lives entirely outside our process and changes whenever any app
    /// installs a tap. The cost is real and worth stating plainly — each read resets
    /// the min/max latency counters of every tap in the system, neighbouring apps'
    /// included — and a SwiftUI body is rebuilt whenever SwiftUI invalidates it,
    /// which is not the same as the user opening the menu. So the number of READS is
    /// not allowed to follow the number of rebuilds: `Cache` collapses a burst of
    /// them into one reading and keeps the answer at most one window old, while the
    /// neighbour's delivered payload — a free local flag that can flip with no
    /// notification behind it — is part of the memo key rather than of its age.
    ///
    /// Losing the position is not a failure Crema repairs. Taking it back would
    /// mean out-inserting a neighbour forever, or moving to the HID location and
    /// silently stealing keys from every other app that wants them — so the app
    /// names who won and leaves the choice to the user, which is the only place
    /// it can be made (docs/DECISIONS.md: media-key-chain-contention).
    func mediaKeyChainNotice() -> MediaKeyChainNotice {
        chainNoticeCache.notice(betterDisplayIsFeedingUs: betterDisplaySource?.hasReported ?? false) { feeding in
            Self.mediaKeyChainNotice(
                registry: eventTapRegistry,
                ourPID: ProcessInfo.processInfo.processIdentifier,
                betterDisplayIsFeedingUs: feeding
            )
        }
    }

    /// The composition, standalone and static so a test pins it without booting
    /// the graph (same reason as the login-item seam).
    ///
    /// A delivered payload outranks the chain reading: once BetterDisplay is
    /// actually reporting, it holding the keys is the arrangement the user was
    /// told to make, not a fault. A contender the system has no display name for
    /// stays unnamed — a bare pid would be noise, and an unnamed warning is worse
    /// than none.
    static func mediaKeyChainNotice(
        registry: any EventTapRegistry,
        ourPID: pid_t,
        betterDisplayIsFeedingUs: Bool
    ) -> MediaKeyChainNotice {
        if betterDisplayIsFeedingUs { return .drawingFromBetterDisplay }
        let chain = MediaKeyChainReconciler.chain(
            ourPID: ourPID,
            mask: MediaKeyTranslation.systemDefinedMask,
            in: registry.entries()
        )
        guard case .precededBy(let pid) = chain else { return .quiet }
        // Named by bundle ID, never by the display name shown to the user: only
        // the neighbour we know how to cooperate with gets the actionable line.
        if registry.bundleID(forPID: pid) == BetterDisplayOSDSource.bundleID {
            return .betterDisplayAheadAndSilent
        }
        guard let name = registry.appName(forPID: pid) else { return .quiet }
        return .anotherAppAhead(name)
    }
}

// MARK: - Brightness echo

@MainActor
extension AppCore {
    /// Slider-driven brightness writes do not echo the way Core Audio volume does,
    /// so the Coordinator hands back what it applied and the loop is closed here —
    /// indicator follows, revert timer refreshes — exactly like the media-key
    /// router and the suppressor's post-apply poke. Absent on demo sources, where
    /// the demo HUD is already event-driven end to end.
    private static func wireBrightnessEcho(to coordinator: Coordinator, graph: SystemGraph) {
        guard let screenSampler = graph.screenBrightnessSampler,
              let keyboardSampler = graph.keyboardBrightnessSampler
        else { return }
        let betterDisplay = graph.betterDisplaySource
        coordinator.onBrightnessApplied = { applied in
            switch (applied.kind, applied.authority) {
            // A neighbour's bar is on its own scale, and it does not report back
            // what third parties ask it to set — so the echo is the value we just
            // wrote, never a re-read of the system's own.
            case (.screenBrightness, .betterDisplay): betterDisplay?.noteApplied(applied)
            case (.screenBrightness, .system): screenSampler.sample()
            case (.keyboardBrightness, _): keyboardSampler.sample()
            case (.volume, _): break   // volume echoes itself; never routed here
            }
        }
    }
}

// MARK: - Style authority

@MainActor
extension AppCore {
    /// Which display speaks for the all-displays picker, in order: the internal
    /// one first, then the rest as AppKit listed them (filter-concat, not
    /// `sorted`, whose instability could scramble the tail). One order for two
    /// readers on purpose — the value the picker shows and the legacy override an
    /// upgrade adopts as the declaration must belong to the same display, or the
    /// app would adopt a style the picker never displayed.
    static func styleAuthorityOrder(_ screens: [ScreenDescription]) -> [DisplayUUID] {
        (screens.filter(\.isInternal) + screens.filter { !$0.isInternal }).map(\.id)
    }
}

// MARK: - Menu bar

/// Extension in THIS file, not another: `menuStatus` reads `preferences`, which is
/// `private` — a cross-file extension cannot see it.
@MainActor
extension AppCore {
    /// What the menu shows, gathered in ONE reading of each fact so a rebuild never
    /// pays twice: `loginItem.status` crosses into Background Task Management, and
    /// the tap-chain reading carries the cost documented on `mediaKeyChainNotice()`.
    ///
    /// Read-only, and that is the contract rather than a habit: the caller is a
    /// SwiftUI view body, rebuilt whenever SwiftUI invalidates it — the app does not
    /// choose when, and it is not tied to the user opening the menu — so a write
    /// here would be domain mutation driven by rendering. The one write the
    /// login-item reading used to do (forgetting an intent the user revoked
    /// themselves) runs at a lifecycle edge instead (reconcileLoginItemIntent).
    ///
    /// `style` and `suppressionEnabled` come IN from the view: both are persisted
    /// preferences, and only an OBSERVED read (@AppStorage) rebuilds the menu when
    /// Settings changes them — read here, the block would keep asserting the old
    /// state until something unrelated invalidated it.
    func menuStatus(style: Style, suppressionEnabled: Bool) -> MenuStatus {
        let loginStatus = loginItem.status
        let chain = mediaKeyChainNotice()
        return MenuStatus(
            style: style,
            // What the displays DRAW, not only what the picker declared: on a Mac
            // with no slit the shipped default declares Notch while every panel
            // draws Card, and a lone "Style: Notch" beside a Card-shaped HUD is the
            // contradiction Settings already learned to name out loud.
            fallsBackToCard: style == .notch && !rendersAnywhere(.notch) && rendersAnywhere(.card),
            accessibilityGranted: permissionMonitor.isGranted,
            suppressionEnabled: suppressionEnabled,
            // The wish is not the fact: with no permission, or no suppressor in the
            // graph (demo sources), the preference persists and nothing engages —
            // the same gate the Settings toggle disables itself on.
            suppressionAvailable: osdSuppressor != nil && permissionMonitor.isGranted,
            suspendedDomains: osdSuppressionMonitor.longSuspendedDomains,
            chainNotice: chain,
            // The chain reading is passed IN rather than taken again: one build of
            // this menu owes exactly one CGGetEventTapList.
            brightnessTarget: Self.brightnessKeyTargetNotice(
                chain: chain,
                keysAreCaptured: permissionMonitor.isGranted,
                census: ScreenTranslation.activeDisplayCensus
            ),
            nowPlayingActive: nowPlayingMonitor.isActive,
            mediaCommandsAvailable: coordinator.commandsAvailable,
            loginOutcome: Self.loginItemOutcome(
                preferences: preferences,
                status: loginStatus,
                currentBuild: Self.currentBuild
            ),
            // Only the registration macOS honours: requiresApproval opens nothing
            // yet and has its own warning.
            loginRegistered: loginStatus == .enabled
        )
    }

    /// Which display Crema's screen brightness lands on. Standalone and static so a
    /// test pins the whole rule without booting the graph; the census is injected so
    /// every arrangement is a test case instead of a hardware trip.
    ///
    /// Three reasons to say nothing, and only two of them are contention.
    /// `.drawingFromBetterDisplay` is the load-bearing one and is NOT about
    /// position: it means the neighbour is reporting, and then the HUD slider really
    /// does write an external display through the neighbour's channel — the sentence
    /// would be FALSE, not merely unhelpful, so narrowing this guard to the two
    /// "someone is ahead" cases ships a lie. An app ahead of us may swallow the key
    /// before Crema ever sees it, and naming a target under the warning printed
    /// right above would contradict it. Without the Accessibility permission there
    /// is no tap at all, and that warning is the only true thing to say about the
    /// keys. The arrangement this costs is a neighbour reporting without being
    /// ahead: the keys are ours and we stay quiet — the same asymmetry the chain
    /// lines already accept, where a lost line costs a diagnostic and a false one
    /// misinforms (docs/DECISIONS.md: media-key-chain-contention).
    ///
    /// The census is consulted only after the gate, so a silenced menu asks the
    /// system nothing.
    ///
    /// A lone built-in panel says nothing: naming the target only informs where
    /// there is another screen the user could have been looking at. "No built-in
    /// panel in use" answers for both clamshell and a Mac that never had one — the
    /// brightness write degrades to false in both, because `DisplayServicesBridge`
    /// refuses to reach for whatever display happens to be main.
    static func brightnessKeyTargetNotice(
        chain: MediaKeyChainNotice,
        keysAreCaptured: Bool,
        census: () -> (hasBuiltIn: Bool, count: Int)
    ) -> BrightnessKeyTargetNotice {
        guard keysAreCaptured, chain == .quiet else { return .quiet }
        let displays = census()
        guard displays.hasBuiltIn else { return .noBuiltInDisplay }
        return displays.count > 1 ? .builtInAmongOthers : .quiet
    }
}
