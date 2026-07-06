import AppKit
import Foundation
import os
import SwiftUI

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
        /// Read-side borders for the OSD-suppression spike (a consumed key
        /// needs the current value to step from); nil on demo sources.
        let screenBrightnessBackend: (any ScreenBrightnessBackend)?
        let keyboardBrightnessBackend: (any KeyboardBrightnessBackend)?
    }

    let coordinator: Coordinator
    let windowManager: WindowManager
    let preferences: Preferences
    let permissionMonitor: AccessibilityPermissionMonitor
    let nowPlayingMonitor: NowPlayingMonitor
    let mediaKeys: any MediaKeySource
    /// Zero-latency brightness HUD via the tap; nil when on demo sources.
    let mediaKeyRouter: MediaKeyHUDRouter?
    /// Native-OSD suppression (opt-in): nil when the graph lacks the
    /// real borders (demo sources) or the key source cannot consume — the
    /// Settings toggle then persists the wish but nothing engages.
    let osdSuppressor: (any NativeOSDSuppressor)?
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
    private var onboardingWindow: NSWindow?

    init(loginItem: (any LoginItemManaging)? = nil) {
        let preferences = Preferences()
        self.preferences = preferences
        // Constructed here, not as a default argument: SMAppServiceLoginItem is
        // @MainActor and a default argument is evaluated in a nonisolated context.
        self.loginItem = loginItem ?? SMAppServiceLoginItem()

        permissionMonitor = AccessibilityPermissionMonitor(permission: accessibilityPermission)
        permissionMonitor.start()
        mediaKeys = CGEventTapMediaKeySource(permission: accessibilityPermission)

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
        screenObservation = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                windowManager.updateScreens(ScreenTranslation.describeAll())
            }
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

        if let consuming = mediaKeys as? any MediaKeyConsuming,
           let screenBackend = graph.screenBrightnessBackend,
           let keyboardBackend = graph.keyboardBrightnessBackend {
            osdSuppressor = MediaKeyInterceptionOSDSuppressor(
                keys: consuming,
                volume: CoreAudioOSDVolumeChannel(controller: graph.volumeController),
                screen: ScreenBrightnessOSDChannel(backend: screenBackend, controller: graph.screenBrightnessController),
                keyboard: KeyboardBrightnessOSDChannel(backend: keyboardBackend, controller: graph.keyboardBrightnessController)
            )
        } else {
            osdSuppressor = nil
        }

        presentAccessibilityOnboardingIfFirstLaunch()

        // Degradation made visible: a failed apply already disengaged the
        // suppressor (native HUD restored); flipping the persisted preference
        // makes the Settings toggle reflect it instead of lying "on".
        osdSuppressor?.onAutoDisengage = { [preferences] in
            preferences.suppressesNativeOSD = false
        }
        // Post-apply poke: the router's key-time sample shows the HUD with
        // the pre-apply value (with the key consumed, the app's write lands
        // after it) — this second sample refreshes it to the applied value.
        if let screenSampler = graph.screenBrightnessSampler,
           let keyboardSampler = graph.keyboardBrightnessSampler {
            osdSuppressor?.onApplied = { key in
                switch key {
                case .screenBrightnessUp, .screenBrightnessDown:
                    screenSampler.sample()
                case .keyboardBrightnessUp, .keyboardBrightnessDown:
                    keyboardSampler.sample()
                case .volumeUp, .volumeDown, .mute:
                    break   // Core Audio is event-driven
                }
            }
        }
        // The preference persists across launches: suppression is a real
        // opt-in feature, and its reversibility never depends on state — the
        // tap dies with the process.
        if preferences.suppressesNativeOSD {
            osdSuppressor?.setEngaged(true)
        }

        #if DEBUG
        startAdapterObservationIfRequested()
        #endif
    }

    /// Persists the opt-in and engages/disengages the suppressor. Called by the
    /// Settings toggle.
    func setNativeOSDSuppression(_ enabled: Bool) {
        preferences.suppressesNativeOSD = enabled
        osdSuppressor?.setEngaged(enabled)
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
        let screenSource = DisplayServicesScreenBrightnessSource(backend: screenBridge)

        let keyboardBridge = CoreBrightnessKeyboardBridge()
        let keyboardSource = CoreBrightnessKeyboardBrightnessSource(backend: keyboardBridge)

        return SystemGraph(
            nowPlayingSource: nowPlayingSource,
            systemHUDSource: MergedSystemHUDSource([volumeSource, screenSource, keyboardSource]),
            nowPlayingController: nowPlayingController,
            volumeController: CoreAudioVolumeController(),
            screenBrightnessController: DisplayServicesScreenBrightnessController(backend: screenBridge),
            keyboardBrightnessController: CoreBrightnessKeyboardBrightnessController(backend: keyboardBridge),
            screenBrightnessSampler: screenSource,
            keyboardBrightnessSampler: keyboardSource,
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
                commandChannel: MediaRemoteAdapterCommandChannel(paths: paths)
            ))
        }

        candidates.append(NowPlayingCandidate(
            isAvailable: { await JXANowPlayingSource.probeAvailability() },
            makeSource: { JXANowPlayingSource() },
            commandChannel: JXACommandChannel()
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

        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.colatte.crema",
            category: "NowPlaying"
        )
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
