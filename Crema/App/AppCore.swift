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
    /// The connected displays as the per-display Settings list reads them, kept in
    /// step with the panels because both are handed the SAME reading
    /// (`applyScreenRoster`). Its own observable because AppCore is not one — the
    /// shape the permission and suppression mirrors already use (docs/DECISIONS.md: one-screen-reading-per-edge).
    let displayRoster = DisplayRoster()
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
    /// Low Power Mode, in the two halves it needs: the system source and the mirror
    /// every panel carries into its view's environment. The mirror is its own
    /// observable because AppCore is not one — the shape the permission and
    /// suppression mirrors already use — and it is a REFERENCE the panels hold, so
    /// an engage/disengage reaches surfaces that were built long before it.
    private let lowPowerSource: any LowPowerModeSource = ProcessInfoLowPowerModeSource()
    private let lowPowerMirror = LowPowerModeMirror()
    /// The task consuming the source, retained for the app lifetime like the wake
    /// observers.
    private var lowPowerConsumption: Task<Void, Never>?
    /// Kept past the merge so the menu can report whether the neighbour's OSD
    /// integration is actually feeding us; nil on demo sources.
    private let betterDisplaySource: BetterDisplayOSDSource?
    /// The now-playing chain (real graph only); stopped on quit so its Perl
    /// process dies with the app.
    private let nowPlayingChain: ChainedNowPlayingSource?
    private var screenObservation: NSObjectProtocol?
    private var terminationObservation: NSObjectProtocol?
    /// Where a warning that offers its own fix wants the Settings window to land.
    /// Its own observable because AppCore is not one, the same shape the permission
    /// and suppression mirrors already use.
    let settingsNavigation = SettingsNavigation()
    /// The desk the Settings and tour style tiles stand on. Owned here, where it
    /// outlives every window: the panes seed it once per opening and the STORE is
    /// what remembers the decode, so reopening them costs no second read of the
    /// file.
    private let wallpaperTiles = WallpaperTileStore()
    /// Display/system wake observers that reinstall the media-key tap: a
    /// display-sleep/wake can leave the tap enabled with a valid port yet
    /// silently not delivering, and it fires no unlock edge for the lock-edge
    /// reinstall to see — these close that gap. Retained for the app lifetime
    /// alongside the tap. (docs/DECISIONS.md: J7-estado-do-outro-lado)
    private var wakeObservations: [NSObjectProtocol] = []
    private var onboardingWindow: NSWindow?
    private var welcomeTourWindow: NSWindow?

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

        // Low Power Mode reaches the surfaces as rendering context, through the
        // panels: one mirror for the whole app, handed to every panel the factory
        // builds — including the ones built later, on a hotplug or a style change.
        // Bound to a local so the escaping factory below captures the mirror and
        // never `self` — the idiom the roster and manager locals already use.
        let lowPowerMirror = self.lowPowerMirror
        lowPowerConsumption = Self.wireLowPowerMode(source: self.lowPowerSource, into: lowPowerMirror)

        windowManager = WindowManager(coordinator: coordinator, preferences: preferences) { screen, style, coordinator in
            NSPanelPresentationPanel(screen: screen, style: style, coordinator: coordinator, lowPower: lowPowerMirror)
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
        Self.applyScreenRoster(screens, to: windowManager, mirroring: displayRoster)

        let windowManager = self.windowManager
        let displayRoster = self.displayRoster
        screenObservation = Self.wireScreenParameterReinstall(reinstalling: tapSource) {
            Self.applyScreenRoster(ScreenTranslation.describeAll(), to: windowManager, mirroring: displayRoster)
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
                keyboard: KeyboardBrightnessOSDChannel(backend: keyboardBackend, controller: graph.keyboardBrightnessController),
                // The pointer rule's border, read fresh on the tap thread at each
                // press (rationale on the type). No default exists for this
                // argument, so no future construction can quietly aim every
                // brightness key at the built-in panel again.
                screenBrightnessTarget: BrightnessKeyTargetReading.target
            )
            osdSuppressor = suppressor
            // Surface long-suspended domains in the menu. The suppressor fires
            // this on escalation and on recovery; the monitor is pull-read by
            // CremaApp, so a transient suspension that heals never shows.
            Self.wireSuspensionMirror(from: suppressor, to: osdSuppressionMonitor)
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

        Self.presentWelcomeTourIfFirstLaunch(preferences: preferences) { self.presentWelcomeTour() }

        // The one moment the persisted login-item intent is reconciled against
        // reality: an item the user removed themselves is forgotten here, at a
        // lifecycle edge, because forgetting is a WRITE and the only other reader
        // of that verdict is a view body (rationale on reconcileLoginItemIntent).
        reconcileLoginItemIntent()

        // Each seam below is gated on exactly the samplers it takes. Widening one
        // gate to cover the group is how a graph that has brightness but no volume
        // sampler loses the hand-back stand-down and the echo as well — two seams
        // that never touch volume — with nothing failing to show it.
        if let screenSampler = graph.screenBrightnessSampler,
           let keyboardSampler = graph.keyboardBrightnessSampler {
            if let suppressor = osdSuppressor {
                // Post-apply poke: the router's key-time sample shows the HUD with
                // the pre-apply value (with the key consumed, the app's write lands
                // after it) — this second sample refreshes it to the applied value.
                if let volumeSampler = graph.volumeSampler {
                    Self.wireApplyPoke(
                        from: suppressor,
                        screen: screenSampler, keyboard: keyboardSampler, volume: volumeSampler
                    )
                }
                // The mirror of the poke above, for the press this app does NOT take:
                // the key goes to the system, which applies it and draws its own
                // indicator — so the local source spends its key window instead of
                // adding a second bar over it. Two reasons arrive here and both want the
                // same thing. The pointer is off the built-in panel, which only screen
                // brightness can be (docs/DECISIONS.md:
                // brightness-key-follows-the-pointer); or the channel reports no such
                // control, which any domain can hit (absent-capability-hands-the-key-back).
                // That second reason is why the BACKLIGHT stands down too: a Mac whose
                // keyboard enumerates late hands its key back until it answers, and the
                // poll that key arms would read the value macOS just moved and draw over
                // the native HUD. Volume needs nothing here — Core Audio is event-driven
                // and the router arms no poll for it.
                Self.wireHandbackStandDown(from: suppressor, screen: screenSampler, keyboard: keyboardSampler)
            }
            Self.wireBrightnessEcho(
                to: coordinator,
                screen: screenSampler,
                keyboard: keyboardSampler,
                neighbour: graph.betterDisplaySource
            )
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

    /// The mirror of the post-apply poke, for the press this app does NOT take.
    ///
    /// Standalone and static for the reason the other wiring statics are: reaching it
    /// through an instance means constructing `AppCore`, which boots the real system
    /// sources, so the production wiring itself was unreachable by any test — and the
    /// keyboard arm of this switch is exactly the kind of line that is deleted in
    /// silence, because the isolated halves each keep passing without it.
    static func wireHandbackStandDown(
        from suppressor: any NativeOSDSuppressor,
        screen: any ManuallySampledSource,
        keyboard: any ManuallySampledSource
    ) {
        suppressor.onHandedBackToTheSystem = { key in
            switch key {
            case .screenBrightnessUp, .screenBrightnessDown:
                screen.standDown()
            case .keyboardBrightnessUp, .keyboardBrightnessDown:
                keyboard.standDown()
            case .volumeUp, .volumeDown, .mute:
                break   // Core Audio is event-driven; the router arms no poll for it
            }
        }
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

    /// The two wake edges, named once. They are workspace notifications: they are
    /// posted on NSWorkspace's own center and never appear on
    /// `NotificationCenter.default`, so wiring them to the wrong center arms
    /// nothing — and arms it silently, since a tap that stopped delivering looks
    /// identical to an idle one from inside this process.
    static let wakeReinstallNames = [
        NSWorkspace.screensDidWakeNotification,
        NSWorkspace.didWakeNotification,
    ]

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
    /// The center carries the production default, so a test that omits it is
    /// posting where the app really listens. Its wake siblings take no center at
    /// all for the same reason, and the measured lesson behind that is recorded on
    /// them: a seam that lets the caller name the center pins the JOIN and says
    /// nothing about WHICH center is joined — screen parameters are posted by
    /// NSApplication on `.default`, and pointing this at NSWorkspace's center would
    /// leave a hotplug with neither a tap reinstall nor a panel for the new screen,
    /// with the suite green.
    static func wireScreenParameterReinstall(
        center: NotificationCenter = .default,
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

    /// Persists the opt-in and engages/disengages the suppressor — the single
    /// seam every switch over this preference writes through, wherever it is
    /// offered. Routed through the lock controller so a toggle-on while locked
    /// persists the wish but defers engagement to unlock; when there is no
    /// suppressor to control, the wish is still persisted.
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

    /// The value the all-displays picker seeds from: the DECLARATION, raw — the
    /// same key the menu's Style submenu binds, so the two surfaces of one
    /// declaration cannot disagree. It used to answer with the leading display's
    /// RESOLVED style, which let that display's own override show up selected in
    /// the tiles that speak for every screen — the tiles claimed a declaration
    /// nobody had made, one row above the row that already reported the override
    /// as this display's own (docs/DECISIONS.md: global-style-default). Never
    /// what any screen draws either: no geometry enters here, which is why a
    /// style-scoped control gates on `rendersAnywhere` instead.
    ///
    /// A one-line delegate to a pinned resolver: the rule is proven at
    /// `Preferences.declaredStyle(fromRawValue:)`, and this carries the same
    /// declared residual as every seam like it — a mutation that reroutes the
    /// delegation is not caught without constructing AppCore.
    func declaredStyle() -> Style {
        preferences.declaredStyle
    }

    /// Whether any connected display RENDERS this style — the gate for
    /// style-scoped Settings controls, and deliberately not `declaredStyle()`:
    /// that reports the declaration, and on a Mac without a notch the shipped
    /// default declares notch while every panel draws card, which left the
    /// Card-only indicator picker gray with the HUD it governs on screen
    /// (docs/DECISIONS.md: rendered-style-gates-settings).
    func rendersAnywhere(_ style: Style) -> Bool {
        windowManager.renders(style)
    }

    /// The picture for the style tiles, or nil for them to draw their own desk.
    /// Seeded at view construction — the deal those panes' other mirrors take
    /// (docs/internal/archive/CONTRACTS-AUDIT.md: S4): SwiftUI re-runs the seed
    /// per tab visit, the store's URL cache keeps that a dictionary hit, and a
    /// wallpaper changed with Settings open shows up on the next construction.
    func tileWallpaper() -> NSImage? {
        wallpaperTiles.backdrop()
    }

    /// The "all displays" entry: declares the style globally and drops the
    /// per-display overrides, so a display connected LATER inherits it too —
    /// writing only the attached displays is what left a monitor plugged in
    /// afterwards on the shipped default while Settings promised "Applies to
    /// every display" (docs/DECISIONS.md: global-style-default). Panels are then
    /// swapped from the re-resolved styles; the core
    /// (Sources/Domain/Coordinator) is untouched.
    func setStyleEverywhere(_ style: Style) {
        Self.declareStyleEverywhere(style, in: preferences, applyingTo: windowManager)
    }

    /// Extracted as a static for the reason the other five wiring statics were
    /// (`wireActiveSourceEnded`, the three `wire*Reinstall`, `reconcileLoginItemIntent`):
    /// reaching it through an instance means constructing `AppCore`, which boots the
    /// real system sources, so the behaviour was unreachable by any test. And this
    /// one line IS the regression — swapping it back for the old
    /// `for screen in describeAll() { setStyle(_:for:) }` restores a monitor plugged
    /// in later drawing the shipped default under a picker that promises "applies to
    /// every display", and leaves the whole suite green.
    ///
    /// Both collaborators are already constructible in a test without touching a
    /// system API (Preferences over ephemeral defaults; WindowManager over the fake
    /// panel factory), which is what makes the seam worth having. The residual is the
    /// same one the other five accept and is stated so nobody reads more into it: a
    /// mutation that removes the DELEGATION above is still not caught.
    static func declareStyleEverywhere(
        _ style: Style,
        in preferences: Preferences,
        applyingTo windowManager: WindowManager
    ) {
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
        let betterDisplaySource = Self.makeNeighbourSource(standingDown: screenSource)
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
/// not another: it reads `onboardingWindow`, a private stored property, and
/// SE-0169 grants that only to a same-file extension.
///
/// The window below is opened by the menu's grant action and by nothing else:
/// first launch belongs to the welcome tour, which walks this same permission as
/// one of its steps, so this is the manual path back to it rather than a
/// launch-time one. (`requestAccessibilityAccess` beside it is the shared ask,
/// called from Settings too.)
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

    private func closeAccessibilityOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
    }
}

// MARK: - Welcome tour

/// Same-file for the same reason as the extension above: `welcomeTourWindow` is a
/// private stored property, and the gate is called from `init`.
@MainActor
extension AppCore {
    /// The tour, once per install, and the two rules that decide who sees it.
    ///
    /// The flag is written BEFORE `present()` runs: a crash or a force quit in the
    /// middle of the tour must not re-arm it, and a window that comes back after
    /// every bad launch is worse than one that was missed. And nothing here asks
    /// about the Accessibility permission — the onboarding this replaces did, and
    /// skipped exactly the installs that already had it, which include every
    /// upgrade. An install that carries the grant is not one that was walked
    /// through anything; it is usually one whose first launch went worst.
    ///
    /// Standalone and static so a test pins both rules without booting the graph
    /// (the reason the other AppCore seams are statics): reaching it through an
    /// instance means constructing `AppCore`, which boots the real system sources.
    static func presentWelcomeTourIfFirstLaunch(preferences: Preferences, present: () -> Void) {
        guard !preferences.hasSeenWelcomeTour else { return }
        preferences.hasSeenWelcomeTour = true
        present()
    }

    /// Window built by the same recipe as the Accessibility onboarding above: a
    /// plain titled window outside the Settings scene, because an accessory app
    /// has no scene to open one into and `openSettings` is a no-op from here.
    /// `NSApp.activate()` and never `activate(ignoringOtherApps:)` — the app has
    /// no Dock tile, so it asks for the front the way the system offers it.
    ///
    /// The view holds this core and this core holds the window: a cycle whose far
    /// end is the composition root, which lives for the whole app either way.
    /// Closing by the title-bar box does not come through `closeWelcomeTour`
    /// (there is no delegate, exactly as with the Accessibility onboarding above),
    /// so the window stays retained — deliberately: the guard at the top then
    /// REUSES it, and a second presentation shows the same window instead of
    /// building a second one. `closeWelcomeTour` is the programmatic way out, for
    /// the buttons inside the view.
    func presentWelcomeTour() {
        if let welcomeTourWindow {
            welcomeTourWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let view = WelcomeTourView(core: self, dismiss: { [weak self] in self?.closeWelcomeTour() })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable]
        window.title = String(localized: "tour.window.title", defaultValue: "Welcome to Crema")
        window.isReleasedWhenClosed = false
        window.center()
        welcomeTourWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Leaving the tour by Skip or by the last button. The close box does not come
    /// through here (no delegate, as with the onboarding window above) and does not
    /// need to: nothing records a "finished", because the flag was committed before
    /// the window existed — leaving early and reaching the end are the same act.
    func closeWelcomeTour() {
        welcomeTourWindow?.close()
        welcomeTourWindow = nil
    }
}

// MARK: - Media-key chain

@MainActor
extension AppCore {
    /// Whether the neighbour has actually delivered a reading in this session.
    ///
    /// Read STRAIGHT off the source, never through `mediaKeyChainNotice()`, which
    /// carries the same flag but pays a `CGGetEventTapList` to answer — a call that
    /// resets the min/max latency counters of every tap on the machine, this app's
    /// neighbours included. Settings reads this from a Form body that SwiftUI
    /// rebuilds whenever it likes, so routing it through that cache would make a
    /// settings pane a periodic system-wide probe.
    ///
    /// Evidence and not presence, which is the whole reason this is a delivered
    /// payload rather than "is BetterDisplay running": the neighbour being open
    /// proves nothing about whether its OSD integration is switched on, and the
    /// claim dies with the app that made it (docs/DECISIONS.md: betterdisplay-osd-source).
    var betterDisplayIsReporting: Bool { betterDisplaySource?.hasReported ?? false }

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
    /// The neighbour's source, joined to the local screen source it must silence.
    ///
    /// A factory rather than a bare call because `onReport` carries a default of
    /// `{}` (BetterDisplayOSDSource.swift:64), so dropping the argument — or
    /// handing it the KEYBOARD source, the other one in scope — compiles in
    /// silence. What breaks is a whole press: with suppression off, Crema's tap
    /// merely OBSERVES the brightness key and arms its own poll while the
    /// neighbour is the one applying and reporting, so two bars draw for one press
    /// and the wrong value — our built-in-panel reading, on a different scale —
    /// lands last (docs/DECISIONS.md: betterdisplay-osd-source).
    ///
    /// The default belongs on the initialiser, not here: a source built with no
    /// local sibling to silence is a real construction, and the tests do it.
    static func makeNeighbourSource(
        target: ((Int) -> SystemHUD.Target?)? = nil,
        standingDown local: any ManuallySampledSource
    ) -> BetterDisplayOSDSource {
        BetterDisplayOSDSource(target: target, onReport: { local.standDown() })
    }

    /// The post-apply poke: with the key consumed, the app's own write lands AFTER
    /// the router's key-time sample, so the HUD would sit on the pre-apply value
    /// without this second sample. The mirror of `wireHandbackStandDown`, which
    /// covers the press this app does NOT take.
    ///
    /// Extracted for the reason its mirror was: deleting one arm of that switch
    /// left the whole suite green, measured. Volume is the arm that matters most
    /// and reads most deletable — its comment argues Core Audio echoes anyway,
    /// which is true everywhere EXCEPT the scale boundary, where a consumed key
    /// writes nothing and fires no echo. Folding it into `.mute` would make the
    /// app swallow a key and draw nothing, which "Nunca fazer" forbids outright.
    static func wireApplyPoke(
        from suppressor: any NativeOSDSuppressor,
        screen screenSampler: any ManuallySampledSource,
        keyboard keyboardSampler: any ManuallySampledSource,
        volume volumeSampler: any ManuallySampledSource
    ) {
        suppressor.onApplied = { key in
            switch key {
            case .screenBrightnessUp, .screenBrightnessDown:
                screenSampler.sample()
            case .keyboardBrightnessUp, .keyboardBrightnessDown:
                keyboardSampler.sample()
            case .volumeUp, .volumeDown:
                // A consumed key at the scale boundary is a no-op write that fires
                // no Core Audio echo; the sampler re-reads and emits there so the
                // HUD still shows (mid-scale the echo covers it, and the sampler
                // no-ops off the boundary — no double-fire).
                volumeSampler.sample()
            case .mute:
                break   // a real toggle: Core Audio always echoes it
            }
        }
    }

    /// The only path from the suppressor's escalation to the user: the menu's
    /// warning and its "try to reactivate now" button both hang off what the
    /// monitor holds. Fires on escalation AND on recovery, and both directions are
    /// load-bearing — a mirror that never fills leaves the user's keys quietly back
    /// with the system while the menu reports health, and one that never clears
    /// leaves a permanent false warning.
    ///
    /// The suppressor is captured weakly and RE-READ at fire time, never sampled
    /// into the closure: capturing `longSuspendedDomains` by value here would
    /// freeze the empty set at wiring time and the menu would never speak again —
    /// the exact edit a "simplify this weak capture" pass would make.
    static func wireSuspensionMirror(
        from suppressor: any NativeOSDSuppressor,
        to monitor: OSDSuppressionMonitor
    ) {
        suppressor.onSuspensionStateChange = { [weak suppressor] in
            monitor.update(suppressor?.longSuspendedDomains ?? [])
        }
    }

    /// Slider-driven brightness writes do not echo the way Core Audio volume does,
    /// so the Coordinator hands back what it applied and the loop is closed here —
    /// indicator follows, revert timer refreshes — exactly like the media-key
    /// router and the suppressor's post-apply poke. Absent on demo sources, where
    /// the demo HUD is already event-driven end to end.
    ///
    /// Takes the parts rather than the graph, and is not private, for one reason:
    /// `SystemGraph` is private, so a parameter of that type put this switch out of
    /// reach of `@testable` — the only wire* static that could not be called from a
    /// test. The nil-guard stays at the call site, where the optionality lives.
    static func wireBrightnessEcho(
        to coordinator: Coordinator,
        screen screenSampler: any ManuallySampledSource,
        keyboard keyboardSampler: any ManuallySampledSource,
        neighbour betterDisplay: BetterDisplayOSDSource?
    ) {
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

// MARK: - Low Power Mode

/// An extension and not the class body, for the reason the accessibility one
/// states: this is what holds the class body inside the `type_body_length`
/// ceiling the composition root leans on with every feature wired into it. It
/// needs nothing private — the seam takes both collaborators as parameters.
@MainActor
extension AppCore {
    /// Joins the Low Power Mode source to the mirror the panels carry into their
    /// views. The SEED is the load-bearing half and it runs BEFORE the stream is
    /// consumed: a Mac launched already in Low Power Mode posts no notification, so
    /// a wiring that only followed `updates` would leave the waveform pulsing until
    /// the user toggled the system setting off and on again — and seeding first also
    /// means no emission can slip through the gap between the two.
    ///
    /// Standalone and static for the reason the other wiring statics are: reaching
    /// it through an instance means constructing `AppCore`, which boots the real
    /// system sources, so this join would be unreachable by any test. Returns the
    /// consuming task the core retains — deliberately not discardable, so the
    /// retention is a decision at every call site; the mirror is captured weakly so
    /// a parked stream is never what keeps it alive.
    static func wireLowPowerMode(
        source: any LowPowerModeSource,
        into mirror: LowPowerModeMirror
    ) -> Task<Void, Never> {
        mirror.report(source.isLowPower)
        return Task { @MainActor [weak mirror, source] in
            for await lowPower in source.updates {
                guard let mirror else { return }
                mirror.report(lowPower)
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
            )
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

// MARK: - Displays and their per-display preferences

/// Extension in THIS file, not another, for the reason the menu-bar one gives:
/// every writer below reaches `preferences` and `windowManager`, both private, and
/// SE-0169 grants that only to a same-file extension. It also keeps the class body
/// inside the `type_body_length` ceiling the composition root leans on.
///
/// Each instance method is a one-line delegation to a static, the shape the other
/// seams here use: reaching the behaviour through an instance means constructing an
/// `AppCore`, which boots the real system sources, so a static is what makes it
/// reachable from a test at all — Preferences over ephemeral defaults and a
/// WindowManager over a fake panel factory are both constructible without touching
/// a system API. The residual is the standard one and is stated so nobody reads
/// more into it: a mutation that removes the DELEGATION itself is not caught.
@MainActor
extension AppCore {
    /// The one reading of the display border per edge, handed to both sides that
    /// have to agree about it: the panel roster and the per-display Settings list.
    ///
    /// It takes the already-read list rather than calling
    /// `ScreenTranslation.describeAll()` itself, and that parameter is what makes
    /// the single reading STRUCTURAL: two independent readings can differ — a
    /// display that left between them — and then Settings offers a row for a
    /// display no panel carries while a panel draws for one no row can reach. Two
    /// lists disagreeing about which screen is which is the class
    /// docs/DECISIONS.md: hud-target-is-a-role rules on, where the true sentence
    /// ends up describing the opposite behaviour.
    ///
    /// Panels first: the roster is what a view reads, and publishing it before the
    /// panels exist would offer a row whose writers reach a display the manager has
    /// not reconciled yet.
    static func applyScreenRoster(
        _ screens: [ScreenDescription],
        to windowManager: WindowManager,
        mirroring roster: DisplayRoster
    ) {
        windowManager.updateScreens(screens)
        roster.update(screens)
    }

    /// One display's own style — the override that outranks the declaration, for
    /// the display in front of the user.
    func setStyle(_ style: Style, for display: DisplayUUID) {
        Self.applyStyleOverride(style, on: display, in: preferences, applyingTo: windowManager)
    }

    /// Writes the per-display override and swaps that display's panel from the
    /// re-resolved styles. Deliberately NOT `declareStyleEverywhere`, which is the
    /// tempting shortcut because it also applies live: that one writes the global
    /// declaration and sweeps every override, so a pick made for one display would
    /// move the others and rewrite what the all-displays picker reports
    /// (docs/DECISIONS.md: global-style-default). `refreshStyles` re-resolves every
    /// display and rebuilds only the ones whose answer changed, so the untouched
    /// displays keep their live panels — and their hover monitors with them.
    static func applyStyleOverride(
        _ style: Style,
        on display: DisplayUUID,
        in preferences: Preferences,
        applyingTo windowManager: WindowManager
    ) {
        preferences.setStyle(style, for: display)
        windowManager.refreshStyles()
    }

    /// Returns one display to the declaration — the "follow the global choice"
    /// side of the same control.
    func clearStyle(for display: DisplayUUID) {
        Self.clearStyleOverride(on: display, in: preferences, applyingTo: windowManager)
    }

    /// Drops the override (inheriting IS the absence of the key — writing today's
    /// declaration into it would look identical now and then shadow the next
    /// declaration forever) and applies the re-resolved style at once, so the user
    /// is not left looking at the style they just cleared.
    static func clearStyleOverride(
        on display: DisplayUUID,
        in preferences: Preferences,
        applyingTo windowManager: WindowManager
    ) {
        preferences.clearStyle(for: display)
        windowManager.refreshStyles()
    }

    /// Whether this display shows the now-playing surface — on by default for the
    /// built-in panel, off elsewhere.
    func setShowsNowPlaying(_ shows: Bool, on display: DisplayUUID) {
        Self.applyShowsNowPlaying(shows, on: display, in: preferences, applyingTo: windowManager)
    }

    /// Writes the per-display flag and re-applies it through a frame pass, which
    /// already reads the preference for each panel. `refreshPresentation` and not
    /// `refreshStyles`: nothing about the window changes here — the flag is render
    /// context the panel carries into its view — and recreating a panel would tear
    /// down a live surface and re-arm its hover monitors for a value the view
    /// already reads.
    static func applyShowsNowPlaying(
        _ shows: Bool,
        on display: DisplayUUID,
        in preferences: Preferences,
        applyingTo windowManager: WindowManager
    ) {
        preferences.setShowsNowPlaying(shows, on: display)
        windowManager.refreshPresentation()
    }
}
