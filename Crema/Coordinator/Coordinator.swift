import Foundation
import Observation
import os

// This file holds the whole Coordinator: state machine + HUD priority + the
// display/linger/hover timers — cohesive, but large.
// swiftlint:disable file_length

/// The app's single @Observable. Decides what is on screen (`state`), owns HUD
/// priority and display timers, and routes view intents to actuators. Sources
/// and actuators are injected by protocol — never a concrete implementation.
@MainActor
@Observable
final class Coordinator {
    /// Default time the HUD stays up after the last event (~1.5 s,
    /// restarting on every key press). The single place this number lives.
    static let defaultHUDRevertDelay: Double = 1.5

    /// How long a now-playing appearance lingers before tucking away. In
    /// reactive mode a media event (track change, play/pause) surfaces it
    /// temporarily; it does not sit on screen for the whole playback. Hover
    /// holds it (cancels the timer); hover-out restarts it. Quiet mode
    /// (reactiveNowPlaying == false) suppresses that self-surfacing while still
    /// tracking nowPlaying/mediaActive, so click-invoke and hover still work.
    static let defaultNowPlayingLinger: Double = 3.0

    /// Linger for a click-invoked appearance — longer than the reactive one:
    /// the user asked for it, so it earns more time to be read (and hovered
    /// into the expanded form) before tucking.
    static let defaultInvokedLinger: Double = 5.0

    /// Hover-intent timing (design-reference §2.3). A skin that sits on the
    /// screen's top edge (the notch) expands only after the pointer lingers for
    /// `defaultHoverIntentDelay`, and collapses only after it has left for
    /// `defaultHoverOutDebounce` — the delay rejects accidental grazes, the
    /// debounce absorbs a re-entry without flicker. Timing lives here because
    /// display timers are the Coordinator's job; the visual springs
    /// live with the style (`SurfaceAnimation`).
    static let defaultHoverIntentDelay: Double = 0.3
    static let defaultHoverOutDebounce: Double = 0.1

    /// Layout-driving state. The views observe this; it is written only when
    /// the presented shape or content actually changes. The WindowManager gets
    /// `onPresentationChange` instead of async observation (see below).
    private(set) var state: PresentationState = .hidden {
        didSet { onPresentationChange?() }
    }

    /// Live playback snapshot, including the once-per-second position tick.
    /// Position updates land only here: rewriting `state` for every tick would
    /// fire its observers — and with them the WindowManager frame pass — once
    /// per second for a frame that never changes. Views read scrubbing/position
    /// data from this property; `state`'s payload is the layout-relevant snapshot.
    private(set) var nowPlaying: NowPlaying?

    /// Whether media is actively playing — with the surface tucked
    /// (state == .hidden) it arms the click-invoke zone: a deliberate click on
    /// the style's region surfaces the compact appearance. Hover never does;
    /// an empty region does not react to the pointer (the region sits on the
    /// menu-bar traffic lane, and hover-invocation fired by accident).
    /// Written only on play/pause flips, never on the position tick.
    private(set) var mediaActive = false {
        didSet { onPresentationChange?() }
    }

    /// Closes the HUD loop after a slider-driven brightness write. Volume echoes
    /// its own programmatic writes — Core Audio property listeners fire on writes
    /// too — so its indicator follows and the revert timer refreshes for free;
    /// the brightness sources emit only through a key-gated poll, so a drag with
    /// no key press behind it would leave the indicator stuck at the old value
    /// and the revert timer unrefreshed (the HUD tucks mid-drag). On a successful
    /// write the Coordinator names the applied kind; AppCore pokes the matching
    /// sampler, which re-reads and emits the applied value into the HUD stream —
    /// the same close-the-loop poke the media-key router and OSD suppressor use.
    /// Injection is intact: the Coordinator names the kind, never a concrete sampler.
    @ObservationIgnored var onBrightnessApplied: (@MainActor (SystemHUD.Kind) -> Void)?

    /// Synchronous presentation hook for the WindowManager. The window must be
    /// resized/ordered in the same runloop callout as the state write: SwiftUI
    /// commits the new state's render at the end of the turn, and any async hop
    /// (observation onChange fires at willSet, so it needs one) races that
    /// commit — when the render won, the first frame of an expansion drew
    /// inside the old, smaller window and was cropped: the intermittent blink.
    @ObservationIgnored var onPresentationChange: (@MainActor () -> Void)?

    /// Whether media commands (play/pause, seek) are working. Optimistic until a
    /// command fails: on macOS 26.x the write path can be blocked while reads
    /// work, so the first blocked command flips this and the views disable their
    /// controls rather than offer a control that silently does nothing.
    private(set) var commandsAvailable = true

    /// Skip commands (next/previous) degrade independently: a source can
    /// accept play/pause but reject track skipping (single-item media, some
    /// backends) — the working controls must not go down with the broken one.
    private(set) var skipCommandsAvailable = true

    /// Whether the current media allows skipping (NowPlaying.supportsSkip).
    /// Mirrored out of the snapshot instead of read through `nowPlaying` so
    /// the transport doesn't re-render on every position tick; written only
    /// when the value actually flips.
    private(set) var skipSupportedByTrack = true

    /// What the transport's prev/next bind to: the write paths must be alive
    /// and the media must accept skips — prohibiting media (radio, live)
    /// swallows a delivered skip without an error, so the failure-driven
    /// flags alone would leave a dead-clicking enabled button.
    var skipControlsEnabled: Bool {
        commandsAvailable && skipCommandsAvailable && skipSupportedByTrack
    }

    @ObservationIgnored private let nowPlayingSource: any NowPlayingSource
    @ObservationIgnored private let systemHUDSource: any SystemHUDSource
    @ObservationIgnored private let nowPlayingController: any NowPlayingController
    @ObservationIgnored private let volumeController: any VolumeController
    @ObservationIgnored private let screenBrightnessController: any ScreenBrightnessController
    @ObservationIgnored private let keyboardBrightnessController: any KeyboardBrightnessController
    @ObservationIgnored private let clock: any SleepClock
    @ObservationIgnored private let hudRevertDelay: Double
    @ObservationIgnored private let nowPlayingLinger: Double
    @ObservationIgnored private let invokedLinger: Double
    @ObservationIgnored private let hoverIntentDelay: Double
    @ObservationIgnored private let hoverOutDebounce: Double
    /// Browser media is ignored by default (MediaSourceFilter): autoplay
    /// videos surface the now-playing for every feed scroll. The Settings
    /// "include browsers" toggle flips this live (setIgnoresBrowserMedia).
    @ObservationIgnored private var ignoresBrowserMedia: Bool
    /// Whether media events surface an appearance on their own. Off is quiet
    /// mode: the surface only appears via click-invoke or hover. Flipped live
    /// by the Settings "reactive" toggle (setReactiveNowPlaying).
    @ObservationIgnored private var reactiveNowPlaying: Bool

    /// Committed hover state — the expansion decision now-playing/revert read.
    /// Distinct from `pointerInside` (the raw pointer signal): during the
    /// hover-intent delay `pointerInside` is already true but `isHovering` stays
    /// false, so a track update mid-delay does not expand ahead of the intent.
    @ObservationIgnored private var isHovering = false
    @ObservationIgnored private var pointerInside = false
    /// The active appearance's linger — a property of the appearance, not of
    /// the restart site: the invoke click lands with the pointer inside the
    /// zone, so the monitor's re-entrant hover-in/out cycle immediately
    /// replaces the initial timer, and a restart that hardcoded the reactive
    /// duration would silently downgrade every invoked appearance to ~3 s.
    @ObservationIgnored private var currentLinger: Double
    /// Whether the HUD interrupted a visible now-playing appearance (or a media
    /// event arrived during the HUD): the revert resurfaces it. A HUD over a
    /// tucked surface must revert to hidden, not resurrect the appearance.
    @ObservationIgnored private var resumeNowPlayingAfterHUD = false
    @ObservationIgnored private var consumptionTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var hudRevertTask: Task<Void, Never>?
    @ObservationIgnored private var lingerTask: Task<Void, Never>?
    @ObservationIgnored private var hoverIntentTask: Task<Void, Never>?

    @ObservationIgnored private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.colatte.crema",
        category: "Coordinator"
    )

    init(
        nowPlayingSource: any NowPlayingSource,
        systemHUDSource: any SystemHUDSource,
        nowPlayingController: any NowPlayingController,
        volumeController: any VolumeController,
        screenBrightnessController: any ScreenBrightnessController,
        keyboardBrightnessController: any KeyboardBrightnessController,
        clock: any SleepClock = ContinuousSleepClock(),
        hudRevertDelay: Double = Coordinator.defaultHUDRevertDelay,
        nowPlayingLinger: Double = Coordinator.defaultNowPlayingLinger,
        invokedLinger: Double = Coordinator.defaultInvokedLinger,
        hoverIntentDelay: Double = Coordinator.defaultHoverIntentDelay,
        hoverOutDebounce: Double = Coordinator.defaultHoverOutDebounce,
        ignoresBrowserMedia: Bool = true,
        reactiveNowPlaying: Bool = true
    ) {
        self.nowPlayingSource = nowPlayingSource
        self.systemHUDSource = systemHUDSource
        self.nowPlayingController = nowPlayingController
        self.volumeController = volumeController
        self.screenBrightnessController = screenBrightnessController
        self.keyboardBrightnessController = keyboardBrightnessController
        self.clock = clock
        self.hudRevertDelay = hudRevertDelay
        self.nowPlayingLinger = nowPlayingLinger
        self.invokedLinger = invokedLinger
        self.hoverIntentDelay = hoverIntentDelay
        self.hoverOutDebounce = hoverOutDebounce
        self.ignoresBrowserMedia = ignoresBrowserMedia
        self.reactiveNowPlaying = reactiveNowPlaying
        currentLinger = nowPlayingLinger
    }

    // MARK: - Settings (live preference changes)

    /// Include or ignore browser media. Turning ignore back on drops a browser
    /// snapshot already on screen — otherwise it would linger until the next
    /// real-player event.
    func setIgnoresBrowserMedia(_ ignores: Bool) {
        guard ignores != ignoresBrowserMedia else { return }
        ignoresBrowserMedia = ignores
        if ignores, let current = nowPlaying, MediaSourceFilter.isBrowser(current.sourceBundleID) {
            discardActiveMedia()
        }
    }

    /// Quiet vs reactive. Flipping it never touches what is already on screen —
    /// it only decides whether the next media event surfaces on its own.
    func setReactiveNowPlaying(_ reactive: Bool) {
        reactiveNowPlaying = reactive
    }

    /// Begins consuming the injected sources. Consumption happens on the main
    /// actor: sources may produce anywhere; consumption is main.
    func start() {
        guard consumptionTasks.isEmpty else { return }

        consumptionTasks.append(Task { [weak self, nowPlayingSource] in
            for await update in nowPlayingSource.updates {
                guard let self else { return }
                self.handleNowPlayingUpdate(update)
            }
            // Stream finished ⇒ source gone. Re-evaluating the fallback chain
            // is the chain source's job; here the ghost snapshot must be
            // dropped, or hover stays armed forever and resurrects dead media.
            self?.handleNowPlayingEnded()
        })

        consumptionTasks.append(Task { [weak self, systemHUDSource] in
            for await hud in systemHUDSource.updates {
                guard let self else { return }
                self.handleHUDUpdate(hud)
            }
        })
    }

    func stop() {
        consumptionTasks.forEach { $0.cancel() }
        consumptionTasks.removeAll()
        hudRevertTask?.cancel()
        hudRevertTask = nil
        lingerTask?.cancel()
        lingerTask = nil
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
    }

    // MARK: - View intents (views report; the Coordinator decides)

    /// Click-invoke: the deliberate "show me what's playing". A click on the
    /// (empty) style region opens the expanded player directly — the user
    /// clicked because they want to see/control, and the pointer is already
    /// on the fresh surface, so a compact would only flash on its way to the
    /// hover expansion anyway. Closing is spatial: pointer leaves → collapse
    /// to compact → the invoked linger (longer than the reactive one) tucks
    /// it. Only meaningful while nothing is visible and media is playing —
    /// with a surface up, clicks route through its own controls instead;
    /// paused media stays invokable only by a media event (same decision as
    /// the old paused-resurface rule).
    func invoke() {
        guard state == .hidden, let track = nowPlaying, track.isPlaying else { return }
        // Before the state write: its didSet synchronously arms the hover
        // monitor, whose immediate sample finds the pointer already inside
        // (the click that got here landed in that exact rect) and re-enters
        // the hover path — which must already see the invoked duration.
        currentLinger = invokedLinger
        state = .nowPlaying(track, expanded: true)
        restartLingerTimer()
    }

    /// Immediate hover: expand/collapse now. Used by the floating styles,
    /// whose surfaces aren't on the accident-prone top edge.
    func hover(_ hovering: Bool) {
        // An empty region never reacts to hover: the region sits on the
        // menu-bar traffic lane and hover-invocation fired by accident.
        // Invocation is a click (or a media event); hover only expands what
        // is already visible.
        if hovering, state == .hidden { return }
        // A gesture that entered through the intent path leaves through it,
        // keeping the recheck and the pointer mirror consistent.
        if !hovering, pointerInside || hoverIntentTask != nil {
            hoverIntent(false)
            return
        }
        commitHover(hovering)
    }

    /// Debounced hover for the notch (design-reference §2.3): expansion waits
    /// `hoverIntentDelay`, collapse waits `hoverOutDebounce`; the newest event
    /// cancels the pending one, and the fired task rechecks the pointer before
    /// committing (the pointer may have moved during the wait).
    func hoverIntent(_ hovering: Bool) {
        pointerInside = hovering
        // The pointer's arrival already holds the appearance — the linger must
        // not tuck the surface out from under a cursor waiting out the intent
        // delay.
        if hovering { cancelLinger() }
        hoverIntentTask?.cancel()
        let delay = hovering ? hoverIntentDelay : hoverOutDebounce
        hoverIntentTask = Task { [weak self, clock, delay, hovering] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return // cancelled: a newer hover event superseded this one
            }
            // A cancel landing between the sleep's expiry and this hop is
            // silent (Task.sleep only throws while pending) — a stale fire
            // would act on a successor's state.
            guard !Task.isCancelled else { return }
            self?.applyHoverIntent(expanded: hovering)
        }
    }

    private func applyHoverIntent(expanded: Bool) {
        // Recheck: only commit if the pointer still matches the intent that was
        // scheduled (it may have entered/left during the delay).
        guard pointerInside == expanded else { return }
        commitHover(expanded)
    }

    /// The single hover commitment path (immediate and debounced). Hover-in
    /// holds the appearance and expands the visible compact; hover-out
    /// collapses and resumes the tuck timer. A hidden state stays hidden —
    /// hover never invokes (that is the click's job).
    private func commitHover(_ hovering: Bool) {
        isHovering = hovering
        if hovering {
            cancelLinger()
            if case .nowPlaying(let track, false) = state {
                state = .nowPlaying(track, expanded: true)
            }
        } else if case let .nowPlaying(track, expanded) = state {
            if expanded {
                state = .nowPlaying(track, expanded: false)
            }
            restartLingerTimer()
        }
    }

    /// Dismisses the surface. Resets the hover commitment because ordering the
    /// panel out does not synthesize a mouseExited (the pointer never moved), so
    /// `onHover(false)` would never fire and a stale `isHovering` would make the
    /// surface reappear expanded with no pointer on it. Deliberately not used on
    /// the HUD-revert-to-now-playing path, where keeping `isHovering` is correct
    /// (the pointer is typically still on the notch).
    private func hide() {
        state = .hidden
        lingerTask?.cancel()
        lingerTask = nil
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
        isHovering = false
        pointerInside = false
        currentLinger = nowPlayingLinger
    }

    func togglePlayPause() {
        runMediaCommand("togglePlayPause") { [nowPlayingController] in
            try await nowPlayingController.togglePlayPause()
        }
    }

    func scrub(to seconds: Double) {
        runMediaCommand("seek") { [nowPlayingController] in
            try await nowPlayingController.seek(to: seconds)
        }
    }

    func nextTrack() {
        runMediaCommand("nextTrack", updating: \.skipCommandsAvailable) { [nowPlayingController] in
            try await nowPlayingController.nextTrack()
        }
    }

    func previousTrack() {
        runMediaCommand("previousTrack", updating: \.skipCommandsAvailable) { [nowPlayingController] in
            try await nowPlayingController.previousTrack()
        }
    }

    func hudSliderChanged(to value: Double) {
        guard case .hud(let hud) = state else { return }
        switch hud.kind {
        case .volume:
            // A drag to any audible target unmutes first, mirroring the
            // volume-up key and the native handler: writing a level onto a
            // muted device raises the number to no sound — the exact "does
            // nothing audible" the key path unmutes to avoid. A drag to 0
            // leaves mute untouched (parity with volume-down). setMuted before
            // setVolume in one Task keeps the key path's ordering; a duplicate
            // unmute from a fast drag echoing a stale snapshot is idempotent.
            let unmute = hud.isMuted && value > 0
            run("setVolume") { [volumeController] in
                if unmute { try await volumeController.setMuted(false, on: hud.display) }
                try await volumeController.setVolume(value, on: hud.display)
            }
        case .screenBrightness:
            applyBrightness("setBrightness(screen)", kind: .screenBrightness) { [screenBrightnessController] in
                try await screenBrightnessController.setBrightness(value, on: hud.display)
            }
        case .keyboardBrightness:
            applyBrightness("setBrightness(keyboard)", kind: .keyboardBrightness) { [keyboardBrightnessController] in
                try await keyboardBrightnessController.setBrightness(value)
            }
        }
    }

    // MARK: - Event handling

    // Weighs every arrival against HUD priority, linger, and the surfacing
    // thresholds in one place; branchy by nature.
    // swiftlint:disable:next function_body_length
    private func handleNowPlayingUpdate(_ update: NowPlaying) {
        // Ignored media is treated as nothing playing, not merely "don't
        // surface": keeping the snapshot would leave hover/click armed for a
        // ghost whose controls command the wrong app. A browser stealing the
        // system's now-playing focus from a real player reads as that player
        // having stopped — the next real-player event re-earns everything.
        if ignoresBrowserMedia, MediaSourceFilter.isBrowser(update.sourceBundleID) {
            discardActiveMedia()
            return
        }

        let previous = nowPlaying
        nowPlaying = update
        if skipSupportedByTrack != update.supportsSkip {
            skipSupportedByTrack = update.supportsSkip
        }
        // mediaActive lands after the state decision (on every exit path): each
        // write runs a synchronous frame pass, and a pass seeing new
        // mediaActive with the old state would transiently disarm the hover
        // monitor mid-update, losing the pointer mirror.
        defer {
            if mediaActive != update.isPlaying {
                mediaActive = update.isPlaying
            }
        }

        // Two thresholds: a surfacing event (track change or play/pause flip)
        // earns an appearance from hidden; a mere content refinement (artwork
        // bytes or duration arriving a beat later) only refreshes an already
        // visible surface — it must not pop a tucked one back up. The position
        // tick clears neither and never touches `state`.
        let identityChanged = previous == nil
            || previous?.title != update.title
            || previous?.artist != update.artist
        let surfacingEvent = identityChanged
            || previous?.isPlaying != update.isPlaying
        // A spontaneous pop only fires for a change that involves playing:
        // something now playing, or a play/pause flip of the same track. A
        // switch to a different track/source that lands paused (a filtered
        // browser handing now-playing back to a paused app, a stream failover)
        // must not surface itself — a paused app returning is not news.
        let surfacesReactively = surfacingEvent && (update.isPlaying || !identityChanged)
        let contentChanged = previous?.layoutContent != update.layoutContent

        // A surfacing event is a natural re-check point: restore optimism so a
        // degraded control becomes usable again — otherwise the disabled
        // control has no path back once flipped. Hoisted above every branch,
        // the .hud one included (audit B2): a track change arriving while a HUD
        // owns the surface must still re-enable the controls, or play/pause
        // stays dead for the rest of the track. Independent of quiet vs
        // reactive: quiet mode still has a live invoked surface with controls,
        // so it recovers the same way, ahead of the self-surface gate.
        if surfacingEvent, !commandsAvailable {
            commandsAvailable = true
        }
        if surfacingEvent, !skipCommandsAvailable {
            skipCommandsAvailable = true
        }

        if case .hud = state {
            // HUD has priority; a pending event resurfaces on the revert —
            // as the new event's reactive appearance (its linger too), exactly
            // as it would surface outside the HUD. Quiet mode never
            // self-surfaces, so the revert just returns to hidden.
            if surfacesReactively, reactiveNowPlaying {
                resumeNowPlayingAfterHUD = true
                currentLinger = nowPlayingLinger
            }
            return
        }

        // A refinement must preserve the current expansion: an invoked player
        // in the uncommitted-hover window (pointer inside, intent not fired)
        // would otherwise collapse under artwork arriving a beat later.
        let wasExpanded: Bool
        if case .nowPlaying(_, let expanded) = state {
            guard contentChanged else { return }
            wasExpanded = expanded
        } else {
            // From hidden, only a surfacing event appears — and only in reactive
            // mode. Quiet mode still tracks nowPlaying/mediaActive above (so
            // click-invoke works), it just does not pop the surface on its own.
            guard surfacesReactively, reactiveNowPlaying else { return }
            wasExpanded = false
        }
        // A media event is a reactive appearance — it earns the reactive
        // linger even over an invoked one. A mere content refinement
        // (artwork arriving) keeps the appearance's current duration.
        if surfacingEvent {
            currentLinger = nowPlayingLinger
        }
        state = .nowPlaying(update, expanded: surfacingEvent ? isHovering : (isHovering || wasExpanded))
        if isHovering {
            cancelLinger() // hover holds the appearance
        } else {
            restartLingerTimer()
        }
    }

    /// The now-playing stream ended: no source is left to emit, so the last
    /// snapshot is a ghost — playing it back on hover (or keeping hover armed)
    /// would offer a frozen scrubber and dead controls.
    private func handleNowPlayingEnded() {
        discardActiveMedia()
    }

    /// The active now-playing source ended without the outer stream finishing —
    /// a chain failover, a total outage, or a deliberate A4 promotion (audit
    /// S6). The consumer's outer stream stays alive across those, so it never
    /// sees a finish; without this seam the last snapshot lingers as a ghost
    /// with `mediaActive` true and click-invoke armed (invoke would resurrect an
    /// expanded player of dead media). Drops it here; the next live source's
    /// snapshots rebuild the state through the normal update path. Wired from
    /// the chain in AppCore. A brief surface blip on a fast failover is
    /// acceptable; showing dead media with armed controls is not.
    func activeNowPlayingSourceEnded() {
        discardActiveMedia()
    }

    /// Drops the active snapshot and everything armed on it: surface, click
    /// zone, hover. Shared by stream end and the browser filter — both mean
    /// "there is no media the app should represent".
    private func discardActiveMedia() {
        nowPlaying = nil
        if mediaActive {
            mediaActive = false
        }
        if case .nowPlaying = state {
            hide()
        }
    }

    private func handleHUDUpdate(_ hud: SystemHUD) {
        if case .nowPlaying = state {
            resumeNowPlayingAfterHUD = true
        } else if state == .hidden {
            resumeNowPlayingAfterHUD = false
        }
        cancelLinger()
        state = .hud(hud)
        restartHUDRevertTimer()
    }

    private func restartHUDRevertTimer() {
        hudRevertTask?.cancel()
        hudRevertTask = Task { [weak self, clock, hudRevertDelay] in
            do {
                try await clock.sleep(for: hudRevertDelay)
            } catch {
                return // cancelled: a newer event restarted the timer, or we stopped
            }
            // A cancel landing between the sleep's expiry and this hop is
            // silent — a stale fire would dismiss the successor HUD instantly.
            guard !Task.isCancelled else { return }
            self?.revertHUD()
        }
    }

    private func revertHUD() {
        guard case .hud = state else { return }
        // Only a pending media event (or the HUD having interrupted a visible
        // appearance) earns a resurface — a pointer merely resting on the
        // region during the HUD does not: the region sits on the menu-bar
        // traffic lane, and resurrecting a tucked appearance from a stray
        // cursor is the accidental-appearance class the click-invoke model
        // removed. The pointer still decides how it resumes: expanded under a
        // committed hover, and no tuck timer while it stays. The resume path
        // deliberately does not require isPlaying: a pause event during the
        // HUD earns its paused appearance (the linger bounds it), exactly as
        // it would outside the HUD.
        if resumeNowPlayingAfterHUD, let track = nowPlaying {
            state = .nowPlaying(track, expanded: isHovering)
            if !isHovering, !pointerInside {
                restartLingerTimer()
            }
        } else {
            hide()
        }
    }

    private func restartLingerTimer() {
        let delay = currentLinger
        lingerTask?.cancel()
        lingerTask = Task { [weak self, clock, delay] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return // cancelled: hover held the appearance, or a newer event restarted it
            }
            // A cancel landing between the sleep's expiry and this hop is
            // silent — a stale fire would tuck the successor appearance instantly.
            guard !Task.isCancelled else { return }
            self?.tuckNowPlaying()
        }
    }

    private func cancelLinger() {
        lingerTask?.cancel()
        lingerTask = nil
    }

    private func tuckNowPlaying() {
        // Never tuck under the pointer: the raw signal covers the intent-delay
        // gap where `isHovering` hasn't committed yet. Expanded is tuckable
        // too — it normally has no running linger (hover cancels it), so
        // reaching here expanded means the invoked player opened under a
        // click and the cursor moved straight out before any hover committed;
        // the appearance must still be able to end.
        guard case .nowPlaying = state, !isHovering, !pointerInside else { return }
        hide()
    }

    /// Fires a one-shot actuator command; failures are logged, never fatal.
    private func run(_ name: StaticString, _ command: @escaping @Sendable () async throws -> Void) {
        Task {
            do {
                try await command()
            } catch {
                logger.error("actuator command \(name, privacy: .public) failed: \(error, privacy: .public)")
            }
        }
    }

    /// A slider-driven brightness write closes its own HUD loop: on success, poke
    /// the matching sampler through `onBrightnessApplied` (see its doc) so the
    /// applied value echoes back — otherwise the indicator sticks and the revert
    /// timer never refreshes. Separate from `run` only because volume echoes
    /// itself (Core Audio) and needs no poke. `@MainActor` because the hook is.
    private func applyBrightness(
        _ name: StaticString,
        kind: SystemHUD.Kind,
        _ command: @escaping @Sendable () async throws -> Void
    ) {
        Task { @MainActor in
            do {
                try await command()
                onBrightnessApplied?(kind)
            } catch {
                logger.error("actuator command \(name, privacy: .public) failed: \(error, privacy: .public)")
            }
        }
    }

    /// Media command: success confirms the write path works; a genuine failure
    /// (e.g. blocked on this macOS) flips the given availability flag so the
    /// matching controls degrade — play/pause/seek update `commandsAvailable`,
    /// next/previous update `skipCommandsAvailable` (they can be rejected
    /// independently). `Task { @MainActor }` because it writes observable state.
    private func runMediaCommand(
        _ name: StaticString,
        updating availability: ReferenceWritableKeyPath<Coordinator, Bool> = \.commandsAvailable,
        _ command: @escaping @Sendable () async throws -> Void
    ) {
        Task { @MainActor in
            do {
                try await command()
                if !self[keyPath: availability] { self[keyPath: availability] = true }
            } catch NowPlayingCommandError.noActiveSource {
                // Transient: nothing is active to command right now (the chain
                // may be mid re-selection). Don't latch the controls off.
                logger.debug("media command \(name, privacy: .public) skipped: no active source")
            } catch {
                logger.error("media command \(name, privacy: .public) failed: \(error, privacy: .public)")
                if self[keyPath: availability] { self[keyPath: availability] = false }
            }
        }
    }
}

private extension NowPlaying {
    /// Everything except the playback position — the fields whose change makes
    /// an update an event (track change, play/pause) rather than a tick.
    /// The source bundle ID is excluded too: it routes the browser filter at
    /// the top of handleNowPlayingUpdate (before the thresholds) and no view
    /// renders it — a chain failover re-reporting the same track from a
    /// different source must not count as content.
    var layoutContent: NowPlaying {
        var copy = self
        copy.position = 0
        copy.sourceBundleID = nil
        return copy
    }
}
