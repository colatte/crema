import Foundation
import Observation
import os

// This file holds the whole Coordinator: state machine + HUD priority + the
// display/linger/hover timers — cohesive, but large.
// swiftlint:disable file_length

/// The app's single @Observable for PRESENTATION STATE — the qualifier is load-
/// bearing, because there are five others (the permission, suppression and
/// now-playing monitors, and the per-panel `SurfaceDisplayPolicy`). Those are
/// read-mirrors for views and hold no domain; this one decides what is on screen.
/// Decides what is on screen (`state`), owns HUD
/// priority and display timers, and routes view intents to actuators. Sources
/// and actuators are injected by protocol — never a concrete implementation.
@MainActor
@Observable
// Cohesive past the 400-line body ceiling for the same reason the file opts
// out of file_length above: priority and timers live ONLY here by design
// (CLAUDE.md, Fluxo de estado), so every presentation feature lands in this
// type. Pure decisions still get extracted (ScrubGrace, PresentationState).
// swiftlint:disable:next type_body_length
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
    /// What any finished hover on the REACTIVE appearance buys before the
    /// tuck, in place of a fresh full linger — a graze must not re-arm the
    /// whole 3 s (the invoked appearance keeps its full tail; see
    /// commitHover). Calibration-in-test (hover round): if it reads short on
    /// hardware, replace the tail expression with `currentLinger` at the
    /// commitHover call site.
    static let hoverExitRelinger: Double = 1.5

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
    /// Written only on play/pause flips, never on the position tick — the menu
    /// bar's Play/Pause label leans on that guarantee too: it renders this flag
    /// directly, and a per-tick write would rebuild the menu (the cost of that is
    /// spelled out on `nowPlayingTitle`).
    private(set) var mediaActive = false {
        didSet { onPresentationChange?() }
    }

    /// Closes the HUD loop after a slider-driven brightness write. Volume echoes
    /// its own programmatic writes — Core Audio property listeners fire on writes
    /// too — so its indicator follows and the revert timer refreshes for free;
    /// the brightness sources emit only through a key-gated poll, so a drag with
    /// no key press behind it would leave the indicator stuck at the old value
    /// and the revert timer unrefreshed (the HUD tucks mid-drag). On a successful
    /// write the Coordinator hands back what it applied; AppCore closes the loop
    /// the way that authority requires — poking the matching sampler for a
    /// system write, and for a neighbour's write echoing the applied value
    /// directly, because a neighbouring app does not report back the levels
    /// third parties ask it to set (measured), and re-reading the system would
    /// answer on a different scale than the bar is drawn in.
    /// Injection is intact: the Coordinator describes what it applied, never a
    /// concrete sampler.
    @ObservationIgnored var onBrightnessApplied: (@MainActor (SystemHUD) -> Void)?

    /// Synchronous presentation hook for the WindowManager, and it has to stay
    /// synchronous — but not for the reason first written here. The original
    /// justification was a window-resize-vs-render race, and the fixed-window model
    /// abolished that: no frame is racing anything any more, so anyone reading the
    /// old note would reasonably conclude the hop is now safe to make async.
    ///
    /// It is not. What depends on the synchrony is everything the WindowManager
    /// DERIVES from `state` inside this callout: whether hover is armed, the
    /// click-interactive region, and the invoke zone. An async hop leaves all three
    /// one turn behind the rendered surface — hover disarmed over pixels that are
    /// already visible, clicks falling through a surface the user can see.
    @ObservationIgnored var onPresentationChange: (@MainActor () -> Void)?

    /// Whether media commands (play/pause, seek) are working. Optimistic until a
    /// command fails, then the views disable their controls rather than offer one
    /// that silently does nothing — and back to optimistic on the next surfacing
    /// event, so a transient failure costs the controls until the next track.
    /// Not a verdict on the platform: measured on macOS 26.5.2 the write path
    /// works (see NowPlayingCommandChannel).
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

    /// Title and artist of the current media, for readers outside the surface —
    /// the menu bar first among them. Mirrors for the same reason as
    /// `skipSupportedByTrack`, one order of magnitude sharper: `nowPlaying` is
    /// rewritten once per second by the position tick, and Observation invalidates
    /// per PROPERTY rather than per value, so ANY read of it — `nowPlaying?.title`
    /// included — subscribes the reader to a 1 Hz rebuild. The menu's status block
    /// pull-reads the event-tap chain, and each of those reads resets the min/max
    /// latency counters of every tap on the machine, so the naive read costs a
    /// system-wide probe per second rather than a menu line
    /// (docs/DECISIONS.md: menu-reads-mirrors).
    ///
    /// Written only when the value actually changes; nil means there is no media to
    /// name. Both borders drop a titleless payload and map a blank artist to nil
    /// (AdapterPayloadTranslation, JXANowPlayingTranslation), so a present title is
    /// a real one — the menu still tests emptiness rather than trust that
    /// (NowPlayingMenuLine), because a blank row reads as a broken app.
    private(set) var nowPlayingTitle: String?
    private(set) var nowPlayingArtist: String?

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
    /// Where a drag goes when the bar was drawn from a neighbouring app's report:
    /// its scale is not the system's, so the write must go back to it. Nil when
    /// that integration is not wired (demo sources), and then the system actuator
    /// takes every drag, exactly as before.
    @ObservationIgnored private let externalScreenBrightnessController: (any ScreenBrightnessController)?
    /// Whether the neighbour is still worth asking. Set false by a command it
    /// refused or never answered, and true again by its next report — evidence in
    /// both directions, so a neighbour that quits mid-gesture stops costing every
    /// following frame a deadline, and one that comes back is used again.
    @ObservationIgnored private var externalBrightnessReachable = true
    @ObservationIgnored private let keyboardBrightnessController: any KeyboardBrightnessController
    @ObservationIgnored private let clock: any SleepClock
    @ObservationIgnored private let hudRevertDelay: Double
    @ObservationIgnored private let nowPlayingLinger: Double
    @ObservationIgnored private let invokedLinger: Double
    @ObservationIgnored private let hoverIntentDelay: Double
    @ObservationIgnored private let hoverOutDebounce: Double
    @ObservationIgnored private let scrubGraceWindow: Double
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
    /// The raw pointer mirror, published — the global signal the timers key on
    /// (the HUD hold). Written by BOTH hover paths via `publishPointer`; on the
    /// debounced path it flips before the intent delay, so holding starts the
    /// moment the cursor arrives. Flips are rare, so the observation cost is
    /// nil. The per-display knob reads the panel-local
    /// `SurfaceDisplayPolicy.pointerInside` instead.
    ///
    /// UNVERIFIED hypothesis (hover round, kept deliberately unimplemented):
    /// on multi-display setups every panel's monitor writes this single global
    /// mirror, and the last writer could in principle mask another display's
    /// state. Needs a two-panel hardware probe before any change — no
    /// speculative set-of-displays here.
    private(set) var pointerInside = false
    /// Whether the current hover gesture entered through the intent path — the
    /// routing guard in `hover(_:)` reads it so a gesture leaves the way it
    /// came. Split from `pointerInside`, which both paths now write.
    @ObservationIgnored private var enteredViaHoverIntent = false
    /// The active appearance's linger — a property of the appearance, not of
    /// the restart site: the invoke click lands with the pointer inside the
    /// zone, so the monitor's re-entrant hover-in/out cycle immediately
    /// replaces the initial timer, and a restart that hardcoded the reactive
    /// duration would silently downgrade every invoked appearance to ~3 s.
    @ObservationIgnored private var currentLinger: Double
    /// Provenance of `currentLinger` — true only for a click-invoked
    /// appearance. A flag, not a value compare against `invokedLinger`:
    /// injected durations that happened to coincide would silently turn every
    /// re-linger into a full tail.
    @ObservationIgnored private var lingerIsInvoked = false
    /// Whether the HUD interrupted a visible now-playing appearance (or a media
    /// event arrived during the HUD): the revert resurfaces it. A HUD over a
    /// tucked surface must revert to hidden, not resurrect the appearance.
    /// A bare Bool, while the revert resurfaces whatever `nowPlaying` holds THEN:
    /// the promise only means anything while that snapshot lives, so dropping the
    /// snapshot must drop it (`discardActiveMedia`) or the revert spends it on a
    /// stranger.
    @ObservationIgnored private var resumeNowPlayingAfterHUD = false
    @ObservationIgnored private var consumptionTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var hudRevertTask: Task<Void, Never>?
    @ObservationIgnored private var lingerTask: Task<Void, Never>?
    @ObservationIgnored private var hoverIntentTask: Task<Void, Never>?
    /// The seek-in-flight authority window (pure decision in ScrubGrace);
    /// the timer that expires it honestly lives here, on the injected clock.
    @ObservationIgnored private var scrubGrace: ScrubGrace
    @ObservationIgnored private var scrubGraceTask: Task<Void, Never>?
    /// Monotonic scrub counter: a seek's failure callback rolls back only if
    /// no newer scrub has taken over the grace and the source anchor since —
    /// a stale failure acting unconditionally would tear down state a newer
    /// actor owns (the superseded-actor class the tap/probe rounds closed).
    @ObservationIgnored private var seekEpoch = 0

    @ObservationIgnored private let logger = Logger.crema("Coordinator")

    init(
        nowPlayingSource: any NowPlayingSource,
        systemHUDSource: any SystemHUDSource,
        nowPlayingController: any NowPlayingController,
        volumeController: any VolumeController,
        screenBrightnessController: any ScreenBrightnessController,
        keyboardBrightnessController: any KeyboardBrightnessController,
        externalScreenBrightnessController: (any ScreenBrightnessController)? = nil,
        clock: any SleepClock = ContinuousSleepClock(),
        hudRevertDelay: Double = Coordinator.defaultHUDRevertDelay,
        nowPlayingLinger: Double = Coordinator.defaultNowPlayingLinger,
        invokedLinger: Double = Coordinator.defaultInvokedLinger,
        hoverIntentDelay: Double = Coordinator.defaultHoverIntentDelay,
        hoverOutDebounce: Double = Coordinator.defaultHoverOutDebounce,
        scrubGraceWindow: Double = ScrubGrace.defaultWindow,
        scrubConfirmTolerance: Double = ScrubGrace.defaultConfirmTolerance,
        ignoresBrowserMedia: Bool = true,
        reactiveNowPlaying: Bool = true
    ) {
        self.nowPlayingSource = nowPlayingSource
        self.systemHUDSource = systemHUDSource
        self.nowPlayingController = nowPlayingController
        self.volumeController = volumeController
        self.screenBrightnessController = screenBrightnessController
        self.keyboardBrightnessController = keyboardBrightnessController
        self.externalScreenBrightnessController = externalScreenBrightnessController
        self.clock = clock
        self.hudRevertDelay = hudRevertDelay
        self.nowPlayingLinger = nowPlayingLinger
        self.invokedLinger = invokedLinger
        self.hoverIntentDelay = hoverIntentDelay
        self.hoverOutDebounce = hoverOutDebounce
        self.scrubGraceWindow = scrubGraceWindow
        scrubGrace = ScrubGrace(confirmTolerance: scrubConfirmTolerance)
        self.ignoresBrowserMedia = ignoresBrowserMedia
        self.reactiveNowPlaying = reactiveNowPlaying
        currentLinger = nowPlayingLinger
        lingerIsInvoked = false
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
    ///
    /// One-shot, and there is no `stop()`. There was one, unreferenced by app and
    /// suite alike, and it was worse than unused: cancelling the consumption task
    /// makes the `for await` below exit, and the line after the loop then reports
    /// the teardown to the rest of the machine as "the media source died" —
    /// discarding the snapshot and hiding the surface, which the ghost-discard
    /// decision reserves for a genuine source death. `ChainedNowPlayingSource`
    /// builds `updates` once at init, so a cancelled iteration is not resubscribable
    /// either: whoever called it would get a permanently media-less app and no error
    /// anywhere. The Coordinator lives for the process; a teardown seam that cannot
    /// be honoured is better absent than available.
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
        lingerIsInvoked = true
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
        if !hovering, enteredViaHoverIntent || hoverIntentTask != nil {
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
        // Same refusal as `hover(_:)` above, for the reason spelled out there —
        // enforced at THIS edge because every line below leaves residue nothing
        // on screen can clear: the published mirror holds off the next HUD's
        // revert timer, and a committed hover makes the next media event appear
        // expanded with no tuck timer behind it. Only an armed monitor reaches
        // here and none is armed over a hidden surface — but that rule lives in
        // the WindowManager, and this decision is the Coordinator's.
        if hovering, state == .hidden { return }
        enteredViaHoverIntent = hovering
        publishPointer(hovering)
        // The pointer's arrival already holds the appearance — the linger must
        // not tuck the surface out from under a cursor waiting out the intent
        // delay.
        if hovering { cancelLinger() }
        hoverIntentTask?.cancel()
        let delay = hovering ? hoverIntentDelay : hoverOutDebounce
        hoverIntentTask = scheduleTimer(after: delay) { [weak self] in
            self?.applyHoverIntent(expanded: hovering)
        }
    }

    private func applyHoverIntent(expanded: Bool) {
        // Recheck: only commit if the pointer still matches the intent that was
        // scheduled (it may have entered/left during the delay).
        guard pointerInside == expanded else { return }
        commitHover(expanded)
    }

    /// Single writer of the pointer mirror for pointer TRANSITIONS — both hover
    /// paths come through here (idempotent when the debounced path already
    /// published) — and the home of the HUD hold: the pointer's arrival cancels
    /// the revert timer, its exit restarts the full delay, which is what makes
    /// the knob's premise real (docs/DECISIONS.md: hud-capsule-track).
    /// Not the mirror's only writer: `hide()` resets it directly (see its doc),
    /// so accounting hung here reaches transitions only — whatever a dismissal
    /// also owes has to be added there in the same change.
    private func publishPointer(_ inside: Bool) {
        guard pointerInside != inside else { return }
        pointerInside = inside
        guard case .hud = state else { return }
        if inside {
            hudRevertTask?.cancel()
            hudRevertTask = nil
        } else {
            restartHUDRevertTimer()
        }
    }

    /// The single hover commitment path (immediate and debounced). Hover-in
    /// holds the appearance and expands the visible compact; hover-out
    /// collapses and resumes the tuck timer. A hidden state stays hidden —
    /// hover never invokes (that is the click's job).
    private func commitHover(_ hovering: Bool) {
        publishPointer(hovering)
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
            // Any finished hover on the REACTIVE appearance buys the short
            // re-linger, not a fresh full one (calibration-in-test — see
            // hoverExitRelinger). The invoked appearance keeps its full tail
            // (provenance flag): its pointer sits on the surface from the
            // click itself, so a capped re-linger would make the invoked
            // linger unreachable again — the exact production bug the
            // invoked-linger tests pin.
            let tail = lingerIsInvoked
                ? currentLinger
                : min(currentLinger, Self.hoverExitRelinger)
            restartLingerTimer(duration: tail)
        }
    }

    /// Dismisses the surface. Resets the hover commitment because ordering the
    /// panel out does not synthesize a mouseExited (the pointer never moved), so
    /// `onHover(false)` would never fire and a stale `isHovering` would make the
    /// surface reappear expanded with no pointer on it. Deliberately not used on
    /// the HUD-revert-to-now-playing path, where keeping `isHovering` is correct
    /// (the pointer is typically still on the notch).
    ///
    /// The pointer mirror is reset DIRECTLY, not through `publishPointer`: a
    /// dismissal is not a pointer transition (the cursor did not move; the
    /// surface under it left), and that method's HUD accounting reads `state`,
    /// so routing the reset above the write below would arm a revert timer for
    /// the very HUD being dismissed. Unconditional on purpose: in the panel path
    /// the disarm already reported the exit, but the state machine must not
    /// depend on a panel existing.
    private func hide() {
        state = .hidden
        lingerTask?.cancel()
        lingerTask = nil
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
        isHovering = false
        pointerInside = false
        enteredViaHoverIntent = false
        currentLinger = nowPlayingLinger
        lingerIsInvoked = false
    }

    func togglePlayPause() {
        runMediaCommand("togglePlayPause") { [nowPlayingController] in
            try await nowPlayingController.togglePlayPause()
        }
    }

    func scrub(to seconds: Double) {
        // The release of a drag (the view sends ONE scrub per gesture). The
        // player's echo is inherently late — the seek travels a one-shot
        // subprocess while the source keeps emitting from its pre-seek anchor
        // — so the user's value takes authority NOW: optimistic position
        // (position-only, S7 — `state` untouched), the source re-anchors its
        // ticker, and a grace window holds stale echoes off until the stream
        // flows at the target or the window expires. Clamped here so the grace
        // target and the command carry the same number (the floor survives a
        // nil duration on purpose); the source re-clamps its anchor
        // defensively against its own snapshot — the same number today, and
        // its ticker's authority if the two ever diverge.
        let floored = max(0, seconds)
        let target = nowPlaying?.duration.map { min(floored, $0) } ?? floored
        seekEpoch += 1
        let epoch = seekEpoch
        if nowPlaying != nil {
            nowPlaying?.position = target
            scrubGrace.begin(target: target)
            nowPlayingSource.noteSeek(to: target)
            scrubGraceTask?.cancel()
            scrubGraceTask = scheduleTimer(after: scrubGraceWindow) { [weak self] in self?.endScrubGrace() }
        }
        // A failed (or never-delivered) seek means the player stays where it
        // was: the optimism has to roll back — end the grace and let the
        // source undo its fabricated anchor, or the ticker would keep
        // counting from a position the player never reached until the next
        // real payload (which, on the adapter, only comes on a change). The
        // epoch guard keeps a stale failure from touching a newer scrub's
        // grace and anchor.
        runMediaCommand(
            "seek",
            onFailure: { [weak self] in
                guard let self, self.seekEpoch == epoch else { return }
                self.endScrubGrace()
                self.nowPlayingSource.noteSeekFailed()
            },
            { [nowPlayingController] in
                try await nowPlayingController.seek(to: target)
            }
        )
    }

    /// The stream takes back authority over the shown position: discard, a
    /// failed seek, and the honest timeout come here directly; confirmation
    /// and track change end inside ScrubGrace and the update path reaps the
    /// timer through here right after — every exit cancels the task.
    private func endScrubGrace() {
        scrubGrace.end()
        scrubGraceTask?.cancel()
        scrubGraceTask = nil
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
                if unmute { try await volumeController.setMuted(false, on: hud.commandDisplay) }
                try await volumeController.setVolume(value, on: hud.commandDisplay)
            }
        case .screenBrightness:
            applyScreenBrightness(value, on: hud)
        case .keyboardBrightness:
            applyBrightness("setBrightness(keyboard)", applied: hud.at(value)) { [keyboardBrightnessController] in
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
        // Ahead of every early return below, the .hud one included: the menu bar is
        // not the surface and does not inherit its priority — it names what is
        // playing even while a HUD owns the screen.
        publishTrackNames(title: update.title, artist: update.artist)
        // Scrub grace: the update lands whole first (the thresholds below and
        // mediaActive read it), then its POSITION is weighed against a seek in
        // flight — a stale echo must not clobber what the user just set
        // (ScrubGrace; confirmation and track change end the window there,
        // and the reap below collects the timeout timer they leave behind).
        if let held = scrubGrace.heldPosition(update: update, previous: previous) {
            nowPlaying?.position = held
        } else if scrubGraceTask != nil, scrubGrace.target == nil {
            endScrubGrace()
        }
        // mediaActive lands after the state decision (on every exit path): each
        // write runs a synchronous frame pass, and a pass seeing new mediaActive
        // against the OLD state arms the invoke zone off a state that is about to
        // change — the invoke zone is the only reader this ORDER protects
        // (WindowManager, alongside `state == .hidden`); the menu bar's Play/Pause
        // label reads the same flag but only ever wants its value. Hover is not at
        // risk here whatever the order: it is armed from `state` alone.
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
        // the .hud one included: a track change arriving while a HUD owns the
        // surface must still re-enable the controls, or play/pause stays dead
        // for the rest of the track. Independent of quiet vs
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
                lingerIsInvoked = false
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
            lingerIsInvoked = false
        }
        state = .nowPlaying(update, expanded: surfacingEvent ? isHovering : (isHovering || wasExpanded))
        if isHovering {
            cancelLinger() // hover holds the appearance
        } else {
            restartLingerTimer()
        }
    }

    /// The single writer of the name mirrors.
    ///
    /// The comparison is belt-and-braces, and saying so is the point: an earlier
    /// version of this comment claimed an @Observable set fires its observers even
    /// when the value is unchanged, and that is not what the runtime does. Measured
    /// on Swift 6.3.3, writing an equal value through the generated setter fires
    /// NOTHING, while an unequal one fires — so this guard removes no invalidation
    /// that would otherwise happen, and the suite cannot tell it apart from an
    /// unguarded write.
    ///
    /// It stays anyway. The mirrors exist to keep the menu off a 1 Hz rebuild whose
    /// cost is a system-wide tap probe (see their declaration), and that protection
    /// would then rest entirely on an optimization inside Observation that no Apple
    /// document promises. A comparison here costs one string compare per second and
    /// makes the guarantee local — the same trade the house makes wherever the truth
    /// lives on the other side of a boundary we do not control.
    ///
    /// Do not read the green suite as proof that this guard works: it is proof that
    /// the tick does not invalidate the mirrors, which is true with the guard and,
    /// on this toolchain, without it (CoordinatorMenuMirrorTests states the
    /// measurement).
    private func publishTrackNames(title: String?, artist: String?) {
        if nowPlayingTitle != title { nowPlayingTitle = title }
        if nowPlayingArtist != artist { nowPlayingArtist = artist }
    }

    /// The now-playing stream ended: no source is left to emit, so the last
    /// snapshot is a ghost — playing it back on hover (or keeping hover armed)
    /// would offer a frozen scrubber and dead controls.
    private func handleNowPlayingEnded() {
        discardActiveMedia()
    }

    /// The active now-playing source ended without the outer stream finishing —
    /// a chain failover, a total outage, or a deliberate promotion
    /// (docs/DECISIONS.md: ghost-discard). The consumer's outer stream stays
    /// alive across those, so it never
    /// sees a finish; without this seam the last snapshot lingers as a ghost
    /// with `mediaActive` true and click-invoke armed (invoke would resurrect an
    /// expanded player of dead media). Drops it here; the next live source's
    /// snapshots rebuild the state through the normal update path. Wired from
    /// the chain in AppCore. A brief surface blip on a fast failover is
    /// acceptable; showing dead media with armed controls is not.
    func activeNowPlayingSourceEnded() {
        discardActiveMedia()
    }

    /// Drops the active snapshot and everything armed on it: surface, click zone,
    /// hover, the names the menu bar shows, and the HUD's promise to resurface.
    /// Shared by stream end, the browser filter and the live filter toggle — all
    /// mean "there is no media the
    /// app should represent". A scrub in flight dies with it: a dead snapshot
    /// cannot retain a position target.
    ///
    /// The resume promise goes for the same reason the surface does: a discard
    /// means the appearance would now be hidden, and a hidden surface owes no
    /// resume (`publishHUD` writes that same false when a HUD rises over hidden).
    /// Under a HUD this is the only write that happens — the state is `.hud`, so
    /// `hide()` below is skipped — and without it the revert resurfaces whatever
    /// landed next, which after a discard is typically a paused app that arms no
    /// resume of its own (docs/DECISIONS.md: ghost-discard). A snapshot that is
    /// news re-earns the promise through handleNowPlayingUpdate's .hud branch.
    private func discardActiveMedia() {
        endScrubGrace()
        nowPlaying = nil
        // The mirrors go with the snapshot: a menu still naming dead media would
        // sit above a transport that reads enabled for a track no live source can
        // command.
        publishTrackNames(title: nil, artist: nil)
        resumeNowPlayingAfterHUD = false
        if mediaActive {
            mediaActive = false
        }
        if case .nowPlaying = state {
            hide()
        }
    }

    private func handleHUDUpdate(_ hud: SystemHUD) {
        // A fresh report is proof the neighbour is answering again, so a channel
        // written off after a failed command is given back its chance. Recovery by
        // evidence, never by a timer.
        if hud.authority == .betterDisplay {
            externalBrightnessReachable = true
        }
        publishHUD(hud)
    }

    /// Puts a reading on screen: the same path an arriving HUD and a drag's own
    /// optimistic echo both take, so a dragged level and a reported one behave
    /// identically (revert timer, pointer hold, now-playing resume).
    private func publishHUD(_ hud: SystemHUD) {
        if case .nowPlaying = state {
            resumeNowPlayingAfterHUD = true
        } else if state == .hidden {
            resumeNowPlayingAfterHUD = false
        }
        cancelLinger()
        state = .hud(hud)
        // A key while the pointer holds the HUD must not re-arm the revert —
        // the hold owns dismissal until the pointer leaves.
        if !pointerInside { restartHUDRevertTimer() }
    }

    /// The one home for the cancellable display-timer idiom: sleep on the
    /// injected clock, then fire — with the two silences that make a timer
    /// safe to restart under a burst. The catch swallows a cancel landing
    /// while the sleep is pending; the isCancelled guard swallows one landing
    /// between the sleep's expiry and this hop, where a stale fire would act
    /// on a successor's state (dismiss its HUD, tuck its appearance). Every
    /// display timer goes through here — the guard is a correctness invariant,
    /// and hand-rolled copies are how it gets lost.
    private func scheduleTimer(after delay: Double, fire: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { [clock] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return // cancelled: a newer event superseded this timer
            }
            guard !Task.isCancelled else { return }
            fire()
        }
    }

    private func restartHUDRevertTimer() {
        hudRevertTask?.cancel()
        hudRevertTask = scheduleTimer(after: hudRevertDelay) { [weak self] in self?.revertHUD() }
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

    private func restartLingerTimer(duration: Double? = nil) {
        let delay = duration ?? currentLinger
        lingerTask?.cancel()
        lingerTask = scheduleTimer(after: delay) { [weak self] in self?.tuckNowPlaying() }
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
    /// A drag on the screen-brightness bar, sent to whoever drew it.
    ///
    /// Three things this owes the user, none of which the plain write gives:
    ///
    /// 1. The bar moves NOW. It has no local value — it draws whatever the last
    ///    SystemHUD said — so it only follows the finger because something echoes
    ///    the new level back. The system path echoes in microseconds; a
    ///    neighbouring app is a round-trip away and may never answer, and a bar
    ///    frozen under a moving finger reads as a broken control. So the level is
    ///    published before the write, and the write's own echo confirms or
    ///    corrects it.
    /// 2. A failed write still moves the screen. The neighbour's command channel
    ///    is a SEPARATE setting from the OSD notification one, so "it reports but
    ///    refuses commands" is a configuration a user can really be in, not an
    ///    edge case. Falling back to the system actuator writes on the other
    ///    scale, which is a smaller lie than a control that does nothing.
    /// 3. Once it has failed, later drags go straight to the system: re-asking a
    ///    neighbour that just refused would stall every frame of the gesture on a
    ///    deadline.
    private func applyScreenBrightness(_ value: Double, on hud: SystemHUD) {
        let applied = hud.at(value)
        publishHUD(applied)

        let viaNeighbour = hud.authority == .betterDisplay && externalBrightnessReachable
        guard let external = externalScreenBrightnessController, viaNeighbour else {
            applyBrightness("setBrightness(screen)", applied: applied.by(.system)) { [screenBrightnessController] in
                try await screenBrightnessController.setBrightness(value, on: hud.commandDisplay)
            }
            return
        }

        Task { @MainActor in
            do {
                try await external.setBrightness(value, on: hud.commandDisplay)
                onBrightnessApplied?(applied)
            } catch {
                logger.error("setBrightness(screen) via BetterDisplay failed: \(error, privacy: .public)")
                externalBrightnessReachable = false
                do {
                    try await screenBrightnessController.setBrightness(value, on: hud.commandDisplay)
                    onBrightnessApplied?(applied.by(.system))
                } catch {
                    logger.error("setBrightness(screen) fallback failed: \(error, privacy: .public)")
                }
            }
        }
    }

    private func applyBrightness(
        _ name: StaticString,
        applied: SystemHUD,
        _ command: @escaping @Sendable () async throws -> Void
    ) {
        Task { @MainActor in
            do {
                try await command()
                onBrightnessApplied?(applied)
            } catch {
                logger.error("actuator command \(name, privacy: .public) failed: \(error, privacy: .public)")
            }
        }
    }

    /// Media command: success confirms the command path works; a genuine failure
    /// (a non-zero adapter exit, a send that outlived its timeout, Automation
    /// denied) flips the given availability flag so the matching controls degrade
    /// — play/pause/seek update `commandsAvailable`, next/previous update
    /// `skipCommandsAvailable` (they can be rejected independently). The
    /// degradation is not a verdict on the platform and not permanent: the next
    /// surfacing event re-enables both, so a transient failure costs the controls
    /// until the next track or resurface, never the session.
    /// `Task { @MainActor }` because it writes observable state.
    private func runMediaCommand(
        _ name: StaticString,
        updating availability: ReferenceWritableKeyPath<Coordinator, Bool> = \.commandsAvailable,
        onFailure: (@MainActor () -> Void)? = nil,
        _ command: @escaping @Sendable () async throws -> Void
    ) {
        Task { @MainActor in
            do {
                try await command()
                if !self[keyPath: availability] { self[keyPath: availability] = true }
            } catch NowPlayingCommandError.noActiveSource {
                // Transient: nothing is active to command right now (the chain
                // may be mid re-selection). Don't latch the controls off — but
                // the command never reached a player, so a caller's optimism
                // still has to roll back.
                logger.debug("media command \(name, privacy: .public) skipped: no active source")
                onFailure?()
            } catch {
                logger.error("media command \(name, privacy: .public) failed: \(error, privacy: .public)")
                if self[keyPath: availability] { self[keyPath: availability] = false }
                onFailure?()
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
