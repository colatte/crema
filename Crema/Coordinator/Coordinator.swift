import Foundation
import Observation
import os

// This file holds the whole Coordinator: state machine + HUD priority + the
// display/linger/hover timers — cohesive, but large.
// swiftlint:disable file_length

/// The app's single @Observable for PRESENTATION STATE — the qualifier is load-
/// bearing, because the app's other observables are read-mirrors for views that
/// hold no domain (docs/STATE-FLOW.md lists them). This one decides what is on
/// screen (`layers`), owns
/// HUD priority and display timers, and routes view intents to actuators. Sources
/// and actuators are injected by protocol — never a concrete implementation.
@MainActor
@Observable
// Cohesive past the 400-line body ceiling for the same reason the file opts
// out of file_length above: priority and timers live ONLY here by design
// (AGENTS.md, Structure), so every presentation feature lands in this
// type. Pure decisions still get extracted (ScrubGrace, PresentationLayers).
// swiftlint:disable:next type_body_length
final class Coordinator {
    /// Default time the HUD stays up after the last event (~1.5 s,
    /// restarting on every key press). The single place this number lives.
    static let defaultHUDRevertDelay: Double = 1.5

    /// The bar answers a key while it is down and lets go when it comes up, but
    /// never sooner than this after the press began, so a tap is seen: UIKit's
    /// `minimumPressDuration` for the volume buttons (UIKitCore, iOS 26.1,
    /// `_UIFluidSliderDiscreteButtonDriverSettings`, read decompiled;
    /// docs/DECISIONS.md: the-bar-answers-the-press).
    static let defaultHUDPressMinimumHold: Double = 0.25

    /// The press lets go after this long without a down even if no up arrived
    /// (the event tap disabled mid-press, a pointer holding the HUD). An
    /// autorepeat re-arms it, so it only has to outlast the delay before the
    /// first repeat (`InitialKeyRepeat`); the margin over that delay is taste,
    /// not measured.
    static let defaultHUDPressLongestHold: Double = 3

    /// How long the bar stays grown after a drag ends before it settles thin,
    /// well inside the HUD's own revert: the grown bar says "under the hand",
    /// the thin one "showing the level"
    /// (docs/DECISIONS.md: the-bar-answers-the-press).
    static let defaultHUDEngagedHold: Double = 0.6

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

    /// Hover-intent timing. A skin that sits on the
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
    /// commitHover). Calibration-in-test: if it reads short on hardware, drop
    /// the cap `commitHover` applies to `currentLinger`.
    static let hoverExitRelinger: Double = 1.5

    /// Layout-driving state, as its two layers. Written only when the presented
    /// shape or content actually changes, and a transition that moves both layers
    /// is one write: the WindowManager's frame pass runs inside it
    /// (`onPresentationChange`, below), and a pass between two writes would place
    /// a frame for a state that never existed.
    private(set) var layers = PresentationLayers() {
        didSet { onPresentationChange?() }
    }

    /// The key the bar is answering, nil at rest. Kept apart from `layers`: it
    /// moves no window, and a write there runs the frame pass.
    private(set) var hudPress: HUDPress?

    /// Whether a drag is under way, or just ended, which grows the bar; it
    /// settles thin `hudEngagedHold` after the release. Apart from `layers` for
    /// the same reason as `hudPress`.
    private(set) var hudIsEngaged = false

    /// The layers as a surface drawing both shows them — the HUD over the
    /// appearance. The global answer, read by the Coordinator's own guards and
    /// the WindowManager's frame pass; a view reads only its surface's share
    /// (`layers.state(on:)`).
    var state: PresentationState { layers.state(on: .both) }

    /// Live playback snapshot, including the once-per-second position tick.
    /// Position updates land only here: rewriting `layers` for every tick would
    /// fire its observers — and with them the WindowManager frame pass — once
    /// per second for a frame that never changes. Views read scrubbing/position
    /// data from this property; `layers`' payload is the layout-relevant snapshot.
    private(set) var nowPlaying: NowPlaying?

    /// Whether media is actively playing — with the surface tucked
    /// (state == .hidden) it arms the click-invoke zone (`canInvoke`): a
    /// deliberate click on the style's region opens the expanded appearance
    /// (`invoke()`). Hover never does;
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
    /// Test seam, unset in production: fires once per screen-brightness drag write,
    /// after the write, its fallback and any correction it owes have all run. A
    /// negative claim about that write (nothing else was written, nothing was
    /// corrected under the finger) needs an end-of-work barrier behind what it
    /// denies, and this is the one point behind all of them (docs/TESTING.md).
    @ObservationIgnored var onScreenBrightnessWriteFinished: (@MainActor () -> Void)?

    /// Synchronous presentation hook for the WindowManager, and it must stay
    /// synchronous: inside this callout the WindowManager derives hover arming,
    /// the click-interactive region and the invoke zone from `state`, and an
    /// async hop leaves all three one turn behind the rendered surface — hover
    /// disarmed over pixels already visible, clicks falling through a surface
    /// the user can see.
    @ObservationIgnored var onPresentationChange: (@MainActor () -> Void)?

    /// Whether media commands (play/pause, seek) are working. Optimistic until a
    /// command fails, then the views disable their controls rather than offer one
    /// that silently does nothing — and back to optimistic on the next surfacing
    /// event, so a transient failure costs the controls until the next track.
    /// Not a verdict on the platform (NowPlayingCommandChannel says why).
    private(set) var commandsAvailable = true

    /// Skip commands (next/previous) degrade independently: a source can
    /// accept play/pause but reject track skipping (single-item media, some
    /// backends) — the working controls must not go down with the broken one.
    private(set) var skipCommandsAvailable = true

    /// Whether the current media allows skipping (NowPlaying.supportsSkip).
    /// Mirrored out of the snapshot instead of read through `nowPlaying` so
    /// the transport doesn't re-render on every position tick; written only
    /// when the value actually flips.
    private var skipSupportedByTrack = true

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
        controlsEnabled && skipCommandsAvailable && skipSupportedByTrack
    }

    /// What the transport's play/pause and scrubber bind to: the write path
    /// works and the appearance is media a player can be told about — never the
    /// tour's sample, which no player is playing.
    var controlsEnabled: Bool {
        commandsAvailable && !showsSample
    }

    /// Whether the appearance on screen is the welcome tour's sample rather than
    /// a player's track (`showcase(sample:)`).
    private(set) var showsSample = false

    /// The sample the tour holds the player up with; non-nil exactly while a
    /// showcase is held, which is what keeps every tuck away.
    @ObservationIgnored private var showcaseSample: NowPlaying?

    @ObservationIgnored private let nowPlayingSource: any NowPlayingSource
    @ObservationIgnored private let systemHUDSource: any SystemHUDSource
    @ObservationIgnored private let nowPlayingController: any NowPlayingController
    @ObservationIgnored private let volumeController: any VolumeController
    @ObservationIgnored private let screenBrightnessController: any ScreenBrightnessController
    /// Where a drag goes when the bar was drawn from a neighbouring app's report:
    /// its scale is not the system's, so the write must go back to it. Nil when
    /// that integration is not wired (demo sources), and then the system actuator
    /// takes every drag.
    @ObservationIgnored private let externalScreenBrightnessController: (any ScreenBrightnessController)?
    /// What the placement preview shows: the output's level, read at the moment
    /// of the preview. Nil on a graph that cannot read it, and then there is no
    /// preview — a bar at a level the output is not at would be a picture, not
    /// the HUD.
    @ObservationIgnored private let volumeReading: (any VolumeReading)?
    /// Counts the previews asked for and the HUDs reported since: a reading that
    /// lands after either is no longer the newest thing to show, and is dropped.
    @ObservationIgnored private var hudPreviewEpoch = 0
    /// Whether the neighbour is still worth asking. Set false by a command it
    /// refused or never answered, and true again by its next report — evidence in
    /// both directions, so a neighbour that quits mid-gesture stops costing every
    /// following frame a deadline, and one that comes back is used again.
    @ObservationIgnored private var externalBrightnessReachable = true
    /// The last screen-brightness level with evidence behind it: a reading that
    /// arrived from a source, or one an actuator confirmed writing. A drag frame
    /// never updates it — the fill under a moving finger is a proposal, and this
    /// is what the proposal falls back to when nothing honours it.
    @ObservationIgnored private var confirmedScreenBrightness: Double?
    /// A drag reached no actuator at all, so the bar is showing a level no display
    /// went to. Held rather than corrected on the spot because the finger is
    /// usually still down, and a fill that jumps backwards under the pointer only
    /// to be dragged forward on the next frame fights the hand sixty times a
    /// second. Any write that does land clears it.
    @ObservationIgnored private var screenBarUnconfirmed = false
    /// True from a drag's first frame until the gesture ends.
    @ObservationIgnored private var hudSliderHeld = false
    /// The drag writes of each system actuator, one after another so the last
    /// frame lands last (`SerialWrites`). The neighbour's actuator orders and
    /// coalesces its own writes, so its frames do not queue here; the system
    /// fallback it hands a failed frame to does.
    @ObservationIgnored private let volumeWrites = SerialWrites()
    @ObservationIgnored private let screenWrites = SerialWrites()
    @ObservationIgnored private let keyboardWrites = SerialWrites()
    @ObservationIgnored private let keyboardBrightnessController: any KeyboardBrightnessController
    @ObservationIgnored private let clock: any SleepClock
    /// The press motion's own clock (`hudPress`, `hudIsEngaged`). Those timers
    /// shape how the bar moves, never what is presented or for how long, so they
    /// keep off the presentation timeline: a test that steps the HUD's revert or
    /// the linger by "the next parked timer" would otherwise step a settle.
    @ObservationIgnored private let motionClock: any SleepClock
    @ObservationIgnored private let hudRevertDelay: Double
    @ObservationIgnored private let hudPressMinimumHold: Double
    @ObservationIgnored private let hudPressLongestHold: Double
    @ObservationIgnored private let hudEngagedHold: Double
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
    /// Distinct from the raw pointer (`pointerSurfaces`): during the hover-intent
    /// delay the pointer is already in but `isHovering` stays false, so a track
    /// update mid-delay does not expand ahead of the intent.
    @ObservationIgnored private var isHovering = false
    /// `isHovering`, read-only, for the tests that need to know a dwell committed
    /// where the commit leaves nothing else observable (a hover under a HUD over a
    /// tucked surface).
    var hoverIsCommitted: Bool { isHovering }
    /// The surfaces the raw pointer is on — the signal the timers key on. Written
    /// by BOTH hover paths via `publishPointer`; on the debounced path it changes
    /// before the intent delay, so holding starts the moment the cursor arrives.
    /// Per surface, because a hold belongs to the layer under the cursor: on a
    /// surface drawing the HUD it holds the HUD, on one drawing the appearance it
    /// holds the appearance, on one drawing both it holds both. A set rather than
    /// one surface: two panels' exit and entry reach here in either order. The
    /// per-display knob reads the panel-local `SurfaceDisplayPolicy.pointerInside`
    /// instead.
    ///
    /// UNVERIFIED hypothesis, deliberately unimplemented:
    /// on multi-display setups every panel's monitor writes this one global
    /// record, and the last writer could in principle mask another display's
    /// state. Needs a two-panel hardware probe before any change — no
    /// speculative set-of-displays here.
    @ObservationIgnored private var pointerSurfaces: Set<PresentationLayers.Surface> = []
    /// The surfaces in `pointerSurfaces` a mouse event has put or found the
    /// pointer on. Only these hold a HUD: a pointer a surface was armed or
    /// retargeted under never moved, and holding on it would keep a HUD that rose
    /// under a resting cursor up until the mouse moved (docs/DECISIONS.md:
    /// hud-capsule-track). The appearance takes either, so an invoked player
    /// under the click that opened it stays held.
    @ObservationIgnored private var movedPointerSurfaces: Set<PresentationLayers.Surface> = []
    /// Whether the pointer is on any of the app's surfaces.
    var pointerInside: Bool { !pointerSurfaces.isEmpty }
    private var pointerHoldsHUD: Bool { movedPointerSurfaces.contains { $0.drawsHUD } }
    private var pointerHoldsAppearance: Bool { pointerSurfaces.contains { $0.drawsNowPlaying } }
    /// Whether the current hover gesture entered through the intent path — the
    /// routing guard in `hover(_:on:)` reads it so a gesture leaves the way it
    /// came. Split from `pointerSurfaces`, which both paths write.
    @ObservationIgnored private var enteredViaHoverIntent = false
    /// The linger the visible appearance still owes — a property of the
    /// appearance, not of the restart site: the invoke click lands with the
    /// pointer inside the zone, so the monitor's re-entrant hover-in/out cycle
    /// immediately replaces the initial timer, and a restart that hardcoded the
    /// reactive duration would silently downgrade every invoked appearance to
    /// ~3 s. A finished hover shortens it IN PLACE rather than handing its tail
    /// to one restart call (commitHover), because content arriving a beat later
    /// restarts the timer through the same plain path: a tail living only in
    /// that argument would hand the graze back the whole linger it has just spent.
    @ObservationIgnored private var currentLinger: Double
    /// Provenance of `currentLinger` — true only for a click-invoked
    /// appearance. A flag, not a value compare against `invokedLinger`:
    /// injected durations that happened to coincide would silently turn every
    /// re-linger into a full tail.
    @ObservationIgnored private var lingerIsInvoked = false

    /// The one writer of the pair above outside `init`: a linger and whether it is
    /// the invoked one always change together, so no site can set one and forget
    /// the other. A finished hover's cap (`commitHover`) shortens the linger in
    /// place and leaves the provenance alone, on purpose.
    private func oweLinger(_ seconds: Double, invoked: Bool) {
        currentLinger = seconds
        lingerIsInvoked = invoked
    }

    @ObservationIgnored private var consumptionTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var hudRevertTask: Task<Void, Never>?
    /// Running while the press is younger than `hudPressMinimumHold`; an up that
    /// lands meanwhile is owed and paid when it ends.
    @ObservationIgnored private var hudPressMinimumTask: Task<Void, Never>?
    @ObservationIgnored private var hudPressReleaseOwed = false
    @ObservationIgnored private var hudPressLongestTask: Task<Void, Never>?
    @ObservationIgnored private var hudEngagedTask: Task<Void, Never>?
    @ObservationIgnored private var lingerTask: Task<Void, Never>?
    @ObservationIgnored private var hoverIntentTask: Task<Void, Never>?
    /// The seek-in-flight authority window (pure decision in ScrubGrace);
    /// the timer that expires it honestly lives here, on the injected clock.
    @ObservationIgnored private var scrubGrace: ScrubGrace
    @ObservationIgnored private var scrubGraceTask: Task<Void, Never>?
    /// Monotonic scrub counter: a seek's failure callback rolls back only if
    /// no newer scrub has taken over the grace and the source anchor since —
    /// a stale failure acting unconditionally would tear down state a newer
    /// actor owns.
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
        volumeReading: (any VolumeReading)? = nil,
        clock: any SleepClock = ContinuousSleepClock(),
        motionClock: any SleepClock = ContinuousSleepClock(),
        hudRevertDelay: Double = Coordinator.defaultHUDRevertDelay,
        hudPressMinimumHold: Double = Coordinator.defaultHUDPressMinimumHold,
        hudPressLongestHold: Double = Coordinator.defaultHUDPressLongestHold,
        hudEngagedHold: Double = Coordinator.defaultHUDEngagedHold,
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
        self.volumeReading = volumeReading
        self.clock = clock
        self.motionClock = motionClock
        self.hudRevertDelay = hudRevertDelay
        self.hudPressMinimumHold = hudPressMinimumHold
        self.hudPressLongestHold = hudPressLongestHold
        self.hudEngagedHold = hudEngagedHold
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
    /// One-shot, and there is no `stop()`: cancelling the consumption task makes
    /// the `for await` below exit and report the teardown as a source death
    /// (snapshot discarded, surface hidden), and `ChainedNowPlayingSource` builds
    /// `updates` once at init, so a cancelled iteration cannot be resubscribed —
    /// a teardown seam that cannot be honoured is better absent than available
    /// (docs/DECISIONS.md: teardown-seam-that-cannot-be-honoured).
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
    /// paused media stays invokable only by a media event.
    func invoke() {
        guard canInvoke, let track = nowPlaying else { return }
        // Before the state write: its didSet synchronously arms the hover
        // monitor, whose immediate sample finds the pointer already inside
        // (the click that got here landed in that exact rect) and re-enters
        // the hover path — which must already see the invoked duration.
        oweLinger(invokedLinger, invoked: true)
        layers.nowPlaying = PresentationLayers.Appearance(track: track, expanded: true)
        restartLingerTimer()
    }

    /// Whether a click-invoke would act now: nothing visible and media playing.
    /// The one spelling of it — the WindowManager arms the invoke zone on it, so
    /// the zone captures a click only when `invoke()` takes it.
    var canInvoke: Bool { state == .hidden && mediaActive }

    /// Shows the volume HUD at the output's current level on `displays` alone, as a
    /// key press would show it there, and lets it revert like any HUD: Settings'
    /// way of showing a new Card placement on the real surface. Reads the level,
    /// never writes it. A drag on the bar is the person's own and goes to the
    /// output as any drag does; its echo is a reported HUD and is drawn wherever
    /// its target puts it.
    func previewHUD(on displays: Set<DisplayUUID>) {
        guard !displays.isEmpty, let volumeReading else { return }
        hudPreviewEpoch += 1
        let epoch = hudPreviewEpoch
        Task { @MainActor [weak self] in
            guard let reading = await volumeReading.currentVolume(),
                  let self, self.hudPreviewEpoch == epoch else { return }
            self.publishHUD(reading, on: displays)
        }
    }

    /// Puts the player up and holds it while the welcome tour talks about it:
    /// the player's own track when there is one, otherwise `sample`, so a Mac
    /// in silence still sees what the app draws. Held, never lingered, until
    /// `endShowcase`. A track arriving takes the sample's place as any media
    /// event would, and media dropped mid-showcase brings the sample back.
    func showcase(sample: NowPlaying) {
        showcaseSample = sample
        cancelLinger()
        guard layers.nowPlaying == nil else { return }
        if let nowPlaying {
            layers.nowPlaying = PresentationLayers.Appearance(track: nowPlaying, expanded: isHovering)
        } else {
            showSample(sample)
        }
    }

    /// Lets go of the showcase: the sample leaves at once, and a real track
    /// goes back to its ordinary tuck.
    func endShowcase() {
        guard showcaseSample != nil else { return }
        showcaseSample = nil
        if showsSample {
            showsSample = false
            hideNowPlaying()
        } else if layers.nowPlaying != nil, !isHovering, !pointerHoldsAppearance {
            restartLingerTimer()
        }
    }

    private func showSample(_ sample: NowPlaying) {
        showsSample = true
        layers.nowPlaying = PresentationLayers.Appearance(track: sample, expanded: isHovering)
    }

    /// Immediate hover: expand/collapse now. Used by the floating styles,
    /// whose surfaces aren't on the accident-prone top edge. `surface` is the
    /// one the pointer crossed, and the hover reaches only the layers it draws:
    /// on a surface drawing only the HUD it holds the HUD and nothing else. It
    /// carries no default on purpose: a caller that forgets it fails to compile
    /// instead of holding layers its surface does not draw. `byMovement` says
    /// whether a mouse event caused the report (`publishPointer`).
    func hover(_ hovering: Bool, on surface: PresentationLayers.Surface, byMovement: Bool = true) {
        // An empty region never reacts to hover: the region sits on the
        // menu-bar traffic lane and hover-invocation fired by accident.
        // Invocation is a click (or a media event); hover only expands what
        // is already visible.
        if hovering, layers.state(on: surface) == .hidden { return }
        if confirmsMovement(hovering, byMovement: byMovement, on: surface) { return }
        guard surface.drawsNowPlaying else {
            publishPointer(hovering, byMovement: byMovement, on: surface)
            return
        }
        // A gesture that entered through the intent path leaves through it,
        // keeping the recheck and the pointer record consistent. That path is
        // the notch's, a surface drawing both layers.
        if !hovering, surface == .both, enteredViaHoverIntent || hoverIntentTask != nil {
            hoverIntent(false)
            return
        }
        commitHover(hovering, byMovement: byMovement, on: surface)
    }

    /// A mouse event finding the pointer where a still sample already put it: the
    /// hover it ran stands, and only the record learns the pointer moved.
    private func confirmsMovement(
        _ hovering: Bool,
        byMovement: Bool,
        on surface: PresentationLayers.Surface
    ) -> Bool {
        guard hovering, byMovement, pointerSurfaces.contains(surface),
              !movedPointerSurfaces.contains(surface) else { return false }
        publishPointer(true, byMovement: true, on: surface)
        return true
    }

    /// Debounced hover for the notch: expansion waits
    /// `hoverIntentDelay`, collapse waits `hoverOutDebounce`; the newest event
    /// cancels the pending one, and the fired task rechecks the pointer before
    /// committing (the pointer may have moved during the wait). The notch draws
    /// both layers on one surface, so this path names no surface. `byMovement`
    /// as in `hover(_:on:byMovement:)`.
    func hoverIntent(_ hovering: Bool, byMovement: Bool = true) {
        // Same refusal as `hover(_:on:)` above, for the reason spelled out there —
        // enforced at THIS edge because every line below leaves residue nothing
        // on screen can clear: the pointer record holds off the next HUD's
        // revert timer, and a committed hover makes the next media event appear
        // expanded with no tuck timer behind it. Only an armed monitor reaches
        // here and none is armed over a hidden surface — but that rule lives in
        // the WindowManager, and this decision is the Coordinator's.
        if hovering, state == .hidden { return }
        if confirmsMovement(hovering, byMovement: byMovement, on: .both) { return }
        enteredViaHoverIntent = hovering
        publishPointer(hovering, byMovement: byMovement, on: .both)
        // The pointer's arrival already holds the appearance — the linger must
        // not tuck the surface out from under a cursor waiting out the intent
        // delay.
        if hovering { cancelLinger() }
        hoverIntentTask?.cancel()
        let delay = hovering ? hoverIntentDelay : hoverOutDebounce
        hoverIntentTask = scheduleTimer(after: delay) { [weak self] in
            // A fired task is spent: the retained field must mean "gesture in
            // flight", because `hover(_:on:)` routes hover-out through the intent
            // path whenever it is non-nil — a dead task left retained would
            // debounce a collapse the immediate styles promise at once. Nulling
            // here is safe against cancel/replace: a superseded task never
            // reaches this closure (cancellation is checked after the sleep,
            // with no suspension between that check and this fire), so only
            // the task the field currently holds can clear it.
            self?.hoverIntentTask = nil
            self?.applyHoverIntent(expanded: hovering)
        }
    }

    private func applyHoverIntent(expanded: Bool) {
        // Recheck: only commit if the pointer still matches the intent that was
        // scheduled (it may have entered/left during the delay).
        guard pointerSurfaces.contains(.both) == expanded else { return }
        // The record already holds how the pointer arrived; the commit only
        // re-asserts it.
        commitHover(expanded, byMovement: false, on: .both)
    }

    /// Single writer of the pointer record for pointer TRANSITIONS — both hover
    /// paths come through here (idempotent when the debounced path already
    /// published) — and the home of the HUD hold: the pointer's arrival on a
    /// surface drawing the HUD cancels the revert timer, its exit restarts the
    /// full delay, which is what makes the knob's premise real
    /// (docs/DECISIONS.md: hud-capsule-track). The arrival has to be a mouse
    /// event's (`byMovement`); a still one is recorded and holds no HUD until
    /// one moves it (`movedPointerSurfaces`). A pointer on a surface drawing
    /// only the appearance never holds the HUD.
    /// Not the record's only writer: `releaseEmptiedSurfaces()` removes surfaces
    /// directly (see its doc), so accounting hung here reaches transitions only —
    /// whatever a dismissal also owes has to be added there in the same change.
    private func publishPointer(_ inside: Bool, byMovement: Bool, on surface: PresentationLayers.Surface) {
        let heldHUD = pointerHoldsHUD
        if inside {
            pointerSurfaces.insert(surface)
            if byMovement { movedPointerSurfaces.insert(surface) }
        } else {
            pointerSurfaces.remove(surface)
            movedPointerSurfaces.remove(surface)
        }
        guard pointerHoldsHUD != heldHUD, layers.hud != nil else { return }
        if pointerHoldsHUD {
            hudRevertTask?.cancel()
            hudRevertTask = nil
        } else {
            restartHUDRevertTimer()
        }
    }

    /// The single hover commitment path (immediate and debounced). Hover-in
    /// holds the appearance and expands the visible compact; hover-out
    /// collapses and resumes the tuck timer. Both act on the appearance only
    /// where `surface` shows it — on a surface drawing both, a HUD covers it. A
    /// hidden state stays hidden — hover never invokes (that is the click's job).
    private func commitHover(_ hovering: Bool, byMovement: Bool, on surface: PresentationLayers.Surface) {
        publishPointer(hovering, byMovement: byMovement, on: surface)
        isHovering = hovering
        if hovering {
            cancelLinger()
            if case .nowPlaying(_, expanded: false) = layers.state(on: surface) {
                layers.nowPlaying?.expanded = true
            }
        } else if case .nowPlaying(_, let expanded) = layers.state(on: surface) {
            if expanded {
                layers.nowPlaying?.expanded = false
            }
            // Any finished hover on the REACTIVE appearance buys the short
            // re-linger, not a fresh full one (calibration-in-test — see
            // hoverExitRelinger). The invoked appearance keeps its full tail
            // (provenance flag): its pointer sits on the surface from the
            // click itself, so a capped re-linger would make the invoked
            // linger unreachable again — the exact production bug the
            // invoked-linger tests pin.
            //
            // The cap goes into the appearance's own duration, not into one
            // restart: artwork landing during the tail restarts the timer from
            // that duration, and a cap held only in an argument is undone by
            // the next refinement — the graze gets its whole 3 s back.
            if !lingerIsInvoked {
                currentLinger = min(currentLinger, Self.hoverExitRelinger)
            }
            restartLingerTimer()
        }
    }

    /// Tucks the now-playing appearance; a HUD over it stays up, and a surface
    /// drawing both keeps showing it.
    private func hideNowPlaying() {
        layers.nowPlaying = nil
        cancelLinger()
        oweLinger(nowPlayingLinger, invoked: false)
        releaseEmptiedSurfaces()
    }

    /// What a dismissal owes the pointer. Ordering a surface out does not
    /// synthesize a mouseExited (the pointer never moved), so `onHover(false)`
    /// never fires: a surface left drawing nothing would keep its hold, and a
    /// stale `isHovering` would make the next appearance come back expanded with
    /// no pointer on it. Every write that can empty a surface ends here. A
    /// surface that still draws a layer keeps its pointer — on the HUD's revert
    /// to the appearance the pointer is typically still on the notch.
    ///
    /// The record is changed DIRECTLY, not through `publishPointer`: a dismissal
    /// is not a pointer transition (the cursor did not move; the surface under it
    /// left), and that method's HUD accounting would arm a revert timer for the
    /// very HUD being dismissed. Unconditional on purpose: in the panel path the
    /// disarm already reported the exit, but the state machine must not depend
    /// on a panel existing.
    private func releaseEmptiedSurfaces() {
        let emptied = pointerSurfaces.filter { layers.state(on: $0) == .hidden }
        pointerSurfaces.subtract(emptied)
        movedPointerSurfaces.subtract(emptied)
        if emptied.contains(where: \.drawsNowPlaying) {
            isHovering = false
        }
        // With both layers gone the hover gesture ends however far it got: a
        // collapse still debouncing has a pointer that already left.
        if state == .hidden {
            hoverIntentTask?.cancel()
            hoverIntentTask = nil
            isHovering = false
            enteredViaHoverIntent = false
        }
    }

    /// The bar a drag was working on is gone, so no correction is owed on it and
    /// no gesture can still be in progress — a HUD dismisses on its own revert
    /// timer while the button is still down, and that view's release never
    /// arrives. EVERY exit from `.hud` owes this, not just the one that hides:
    /// a mark carried into the next bar fires on that bar's release and pulls a
    /// perfectly good drag back to a level two readings old, its own write still
    /// in flight (docs/DECISIONS.md: the-bar-never-outruns-the-screen).
    private func forgetTheBarUnderTheFinger() {
        screenBarUnconfirmed = false
        hudSliderHeld = false
    }

    func togglePlayPause() {
        // The control is off for the sample (`controlsEnabled`), and this
        // refuses anyway: a command would reach whatever player macOS last
        // knew, which is not what the sample shows.
        guard !showsSample else { return }
        runMediaCommand("togglePlayPause") { [nowPlayingController] in
            try await nowPlayingController.togglePlayPause()
        }
    }

    func scrub(to seconds: Double) {
        guard !showsSample else { return }
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
        guard !showsSample else { return }
        runMediaCommand("nextTrack", updating: \.skipCommandsAvailable) { [nowPlayingController] in
            try await nowPlayingController.nextTrack()
        }
    }

    func previousTrack() {
        guard !showsSample else { return }
        runMediaCommand("previousTrack", updating: \.skipCommandsAvailable) { [nowPlayingController] in
            try await nowPlayingController.previousTrack()
        }
    }

    func hudSliderChanged(to value: Double) {
        guard case .hud(let hud) = state else { return }
        hudSliderHeld = true
        engageHUD()
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
            run("setVolume", on: volumeWrites) { [volumeController] in
                if unmute { try await volumeController.setMuted(false, on: hud.commandDisplay) }
                try await volumeController.setVolume(value, on: hud.commandDisplay)
            }
        case .screenBrightness:
            applyScreenBrightness(value, on: hud)
        case .keyboardBrightness:
            applyBrightness(
                "setBrightness(keyboard)",
                applied: hud.at(value),
                on: keyboardWrites
            ) { [keyboardBrightnessController] in
                try await keyboardBrightnessController.setBrightness(value)
            }
        }
    }

    /// The gesture ended, however it ended — released, or torn out from under the
    /// finger when the bar changed kind. The bar keeps whatever the finger left it
    /// at, unless nothing honoured the drag; then it eases back to the last level
    /// with evidence behind it.
    ///
    /// The view reports the end rather than the Coordinator inferring it from a
    /// quiet period. A debounce would be the same correction one guess later, and
    /// would fire on a finger that merely paused mid-drag — springing the fill back
    /// while the hand is still holding it, which is the one thing this correction
    /// exists to avoid.
    func hudSliderReleased() {
        hudSliderHeld = false
        engageHUD()
        settleScreenBarIfUnconfirmed()
    }

    /// The drag reached no actuator, so the bar is showing a level no display went
    /// to. Correct it now if the hand has already let go; otherwise the release
    /// will.
    private func noteScreenBarUnconfirmed() {
        screenBarUnconfirmed = true
        settleScreenBarIfUnconfirmed()
    }

    /// Puts the bar back on the last level with evidence behind it — the rejected
    /// drag animating home, the way a drop the system will not take does.
    ///
    /// It publishes rather than assigns, so the correction refreshes the revert
    /// timer too: the user gets the honest level for a full linger instead of a
    /// glimpse of it before the HUD dismisses. Everything about the ease itself
    /// belongs to the slider, which already springs to whatever value it is handed
    /// and already suspends that spring under Reduce Motion.
    private func settleScreenBarIfUnconfirmed() {
        guard screenBarUnconfirmed, !hudSliderHeld else { return }
        screenBarUnconfirmed = false
        // Anything else on screen means the bar being corrected is gone — the HUD
        // dismissed, or flipped to volume under the finger. Correcting then would
        // put a stale brightness reading over whatever replaced it.
        guard case .hud(let hud) = state, hud.kind == .screenBrightness,
              let confirmed = confirmedScreenBrightness, confirmed != hud.value else { return }
        // The bar on screen may be the app's own echo (it came round through the
        // stream); what replaces it is the last READING, so it goes back out as one.
        var settled = hud.at(confirmed)
        settled.provenance = .reading
        publishHUD(settled)
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
        // Ahead of every early return below: the menu bar is not the surface and
        // does not inherit its rules — it names what is playing whether or not an
        // appearance shows it, and while a HUD owns the screen.
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
        // (WindowManager, through `canInvoke`); the menu bar's Play/Pause
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
        let identityChanged = update.isAnotherTrack(than: previous)
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
        // control has no path back once flipped. Hoisted above every branch, so
        // a track change that surfaces nothing still re-enables the controls, or
        // play/pause stays dead for the rest of the track. Independent of quiet vs
        // reactive: quiet mode still has a live invoked surface with controls,
        // so it recovers the same way, ahead of the self-surface gate.
        if surfacingEvent, !commandsAvailable {
            commandsAvailable = true
        }
        if surfacingEvent, !skipCommandsAvailable {
            skipCommandsAvailable = true
        }

        // A HUD changes none of what follows: the appearance under it takes the
        // event exactly as it would with no HUD up, and a surface drawing both
        // shows it when the HUD reverts. Only its tuck waits for the revert
        // (`restartLingerTimer`).
        //
        // A refinement must preserve the current expansion: an invoked player
        // in the uncommitted-hover window (pointer inside, intent not fired)
        // would otherwise collapse under artwork arriving a beat later.
        let wasExpanded: Bool
        if let appearance = layers.nowPlaying {
            guard contentChanged else { return }
            wasExpanded = appearance.expanded
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
            oweLinger(nowPlayingLinger, invoked: false)
        }
        if showsSample {
            showsSample = false
        }
        layers.nowPlaying = PresentationLayers.Appearance(
            track: update,
            expanded: surfacingEvent ? isHovering : (isHovering || wasExpanded)
        )
        if isHovering {
            cancelLinger() // hover holds the appearance
        } else {
            restartLingerTimer()
        }
    }

    /// The single writer of the name mirrors.
    ///
    /// The comparison is belt-and-braces: measured on Swift 6.3.3, an equal write
    /// through the generated setter fires nothing, so the guard removes no
    /// invalidation; it stays so the menu's protection from a 1 Hz rebuild (see
    /// the mirrors' declaration) does not rest on an Observation optimization no
    /// Apple document promises (CoordinatorMenuMirrorTests states the
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

    /// Drops the active snapshot and everything armed on it: the appearance,
    /// click zone, hover, and the names the menu bar shows. Shared by stream end,
    /// the browser filter and the live filter toggle — all mean "there is no
    /// media the app should represent". A scrub in flight dies with it: a dead
    /// snapshot cannot retain a position target.
    ///
    /// The appearance goes under a HUD too, so the revert has nothing to bring
    /// back; kept, it would come back showing whatever landed next, which after a
    /// discard is typically a paused app that would not surface on its own
    /// (docs/DECISIONS.md: ghost-discard). A snapshot that is news earns a new
    /// appearance through handleNowPlayingUpdate. During a showcase the sample
    /// takes the dropped track's place: it is no player's, so nothing armed on
    /// it can command dead media.
    private func discardActiveMedia() {
        endScrubGrace()
        nowPlaying = nil
        // The mirrors go with the snapshot: a menu still naming dead media would
        // sit above a transport that reads enabled for a track no live source can
        // command.
        publishTrackNames(title: nil, artist: nil)
        if mediaActive {
            mediaActive = false
        }
        if let showcaseSample {
            if !showsSample { showSample(showcaseSample) }
        } else if layers.nowPlaying != nil {
            hideNowPlaying()
        }
    }

    private func handleHUDUpdate(_ hud: SystemHUD) {
        // The app's own echo comes back through this same stream (the neighbour's
        // source yields it, so the bar follows the finger), and it must move the
        // bar and nothing else: it is the level the app ASKED for, which is not
        // evidence of anything until a write answers. Taking it for a reading
        // lets a failed drag settle home on a brightness no display ever
        // went to, and lets a coalesced echo still in the pipe revive a channel
        // the failure has just written off (docs/DECISIONS.md:
        // the-bar-never-outruns-the-screen).
        if hud.provenance == .reading {
            // A fresh report is proof the neighbour is answering again, so a
            // channel written off after a failed command is given back its chance.
            // Recovery by evidence, never by a timer.
            if hud.authority == .betterDisplay {
                externalBrightnessReachable = true
            }
            // A reading that arrived on its own is evidence, so it becomes what an
            // unbacked drag falls back to. It does NOT also retire a pending
            // correction: this reading is already on the bar, so the correction it
            // would trigger finds the bar at the level it was going to publish and
            // returns without touching it. Clearing here would be a second
            // spelling of that guard, and a second spelling is what goes stale.
            if hud.kind == .screenBrightness { confirmedScreenBrightness = hud.value }
        }
        hudPreviewEpoch += 1
        publishHUD(hud)
    }

    /// Puts a reading on screen: the same path an arriving HUD, a drag's own
    /// optimistic echo and a placement preview all take, so each behaves
    /// identically (revert timer, pointer hold, the appearance's return).
    /// `displays` scopes a preview (`PresentationLayers.hudDisplays`); every
    /// other caller leaves it nil, which also clears a preview's scope.
    private func publishHUD(_ hud: SystemHUD, on displays: Set<DisplayUUID>? = nil) {
        // The appearance under it, visible or not, stays as it is; only its tuck
        // waits (`restartLingerTimer`).
        cancelLinger()
        var next = layers
        next.hud = hud
        next.hudDisplays = displays
        layers = next
        // A key while the pointer holds the HUD must not re-arm the revert —
        // the hold owns dismissal until the pointer leaves. A pointer the
        // write's own frame pass just found under the HUD holds nothing: the
        // arming sample is no movement (`movedPointerSurfaces`).
        if !pointerHoldsHUD { restartHUDRevertTimer() }
    }

    /// The one home for the cancellable display-timer idiom: sleep on the
    /// injected clock, then fire — with the two silences that make a timer
    /// safe to restart under a burst. The catch swallows a cancel landing
    /// while the sleep is pending; the isCancelled guard swallows one landing
    /// between the sleep's expiry and this hop, where a stale fire would act
    /// on a successor's state (dismiss its HUD, tuck its appearance). Every
    /// display timer goes through here — the guard is a correctness invariant,
    /// and hand-rolled copies are how it gets lost.
    private func scheduleTimer(
        after delay: Double,
        on timerClock: (any SleepClock)? = nil,
        fire: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        Task { [clock = timerClock ?? clock] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return // cancelled: a newer event superseded this timer
            }
            guard !Task.isCancelled else { return }
            fire()
        }
    }

    /// A step key went down, or repeated (the suppressor's `onKeyPressed`): the
    /// bar answers it until the key comes up. A repeat of the key already held
    /// keeps the presses it counted past the end. It engages nothing: a reading
    /// changes the level in a transaction of its own, so the two never share a
    /// spring (`SurfaceAnimation.hudPress`).
    func hudKeyPressed(_ key: MediaKey) {
        guard let press = HUDPress(key: key) else { return }
        hudPressReleaseOwed = false
        if hudPress?.isOf(key) != true { beginHUDPress(press) }
        rearmHUDPressLongestHold()
    }

    /// A press found the level already at the end its key points to (the
    /// suppressor's `onPushedPastEnd`). The reading that follows reports the end
    /// and cannot say it was pressed past, so the press arrives here on its own.
    /// It may land before the reading puts the HUD up; the bar then appears
    /// pushed out and eases back, as the native one does on a first press at full.
    func hudPushedPastEnd(_ key: MediaKey) {
        guard var press = HUDPress(key: key) else { return }
        if let held = hudPress, held.isOf(key) {
            press.stepsPastEnd = held.stepsPastEnd + 1
            hudPress = press
        } else {
            press.stepsPastEnd = 1
            beginHUDPress(press)
        }
        rearmHUDPressLongestHold()
    }

    /// The key came up (the suppressor's `onKeyReleased`); the bar lets go with
    /// it, once the press has been seen.
    func hudKeyReleased(_ key: MediaKey) {
        guard hudPress?.isOf(key) == true else { return }
        if hudPressMinimumTask == nil {
            endHUDPress()
        } else {
            hudPressReleaseOwed = true
        }
    }

    private func beginHUDPress(_ press: HUDPress) {
        hudPress = press
        hudPressMinimumTask?.cancel()
        hudPressMinimumTask = scheduleTimer(after: hudPressMinimumHold, on: motionClock) { [weak self] in
            guard let self else { return }
            hudPressMinimumTask = nil
            if hudPressReleaseOwed { endHUDPress() }
        }
    }

    private func rearmHUDPressLongestHold() {
        hudPressLongestTask?.cancel()
        hudPressLongestTask = scheduleTimer(after: hudPressLongestHold, on: motionClock) { [weak self] in
            self?.endHUDPress()
        }
    }

    private func endHUDPress() {
        hudPressMinimumTask?.cancel()
        hudPressMinimumTask = nil
        hudPressLongestTask?.cancel()
        hudPressLongestTask = nil
        hudPressReleaseOwed = false
        hudPress = nil
    }

    /// Grows the bar under a drag and restarts its settle; the drag holds it
    /// grown until the release calls here again.
    private func engageHUD() {
        hudIsEngaged = true
        hudEngagedTask?.cancel()
        guard !hudSliderHeld else { return }
        hudEngagedTask = scheduleTimer(after: hudEngagedHold, on: motionClock) { [weak self] in
            self?.hudIsEngaged = false
        }
    }

    private func restartHUDRevertTimer() {
        hudRevertTask?.cancel()
        hudRevertTask = scheduleTimer(after: hudRevertDelay) { [weak self] in self?.revertHUD() }
    }

    private func revertHUD() {
        guard layers.hud != nil else { return }
        forgetTheBarUnderTheFinger()
        // The appearance comes back only if one is there: the HUD rose over it,
        // or a media event earned it during the HUD. A pointer merely resting on
        // the region during the HUD earns none: the region sits on the menu-bar
        // traffic lane, and resurrecting a tucked appearance from a stray cursor
        // is the accidental-appearance class the click-invoke model rules out. The
        // pointer still decides how it comes back: expanded under a committed
        // hover, and no tuck timer while it stays. One write for both layers, so
        // no frame pass sees the HUD gone with the appearance not yet settled.
        var next = layers
        next.hud = nil
        next.hudDisplays = nil
        next.nowPlaying?.expanded = isHovering
        layers = next
        releaseEmptiedSurfaces()
        if layers.nowPlaying != nil, !isHovering, !pointerHoldsAppearance {
            restartLingerTimer()
        }
    }

    /// Arms the tuck on whatever the appearance currently owes. No per-call
    /// duration: one source for the number is what keeps a refinement from
    /// re-arming a tail the hover already shortened (see `currentLinger`).
    ///
    /// Never while a HUD is up: on a surface drawing both, the appearance under
    /// the HUD is not on screen to be read, and its tuck would leave the revert
    /// nothing to bring back. Wherever the HUD is drawn the rule is the same, so
    /// the appearance has one lifetime; the revert arms the tuck again. Never
    /// during a showcase either: the tour holds the player for as long as it
    /// talks about it, and `endShowcase` arms the tuck.
    private func restartLingerTimer() {
        guard layers.hud == nil, showcaseSample == nil else { return }
        lingerTask?.cancel()
        lingerTask = scheduleTimer(after: currentLinger) { [weak self] in self?.tuckNowPlaying() }
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
        guard layers.nowPlaying != nil, !isHovering, !pointerHoldsAppearance, showcaseSample == nil else { return }
        hideNowPlaying()
    }

    /// Fires a one-shot actuator command behind the writes already queued on
    /// `writes`; failures are logged, never fatal.
    private func run(
        _ name: StaticString,
        on writes: SerialWrites,
        _ command: @escaping @Sendable () async throws -> Void
    ) {
        writes.enqueue { [logger] in
            do {
                try await command()
            } catch {
                logger.error("actuator command \(name, privacy: .public) failed: \(error, privacy: .public)")
            }
        }
    }

    /// A drag on the screen-brightness bar, sent to whoever drew it.
    ///
    /// Four things this owes the user, none of which the plain write gives:
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
    /// 4. When even the fallback writes nothing — the bar names an external
    ///    display, which DisplayServices refuses by design — the bar comes back to
    ///    the last level with evidence behind it, once the gesture ends. Leaving it
    ///    under the finger would make a control that did nothing look like one that
    ///    worked (docs/DECISIONS.md: the-bar-never-outruns-the-screen).
    private func applyScreenBrightness(_ value: Double, on hud: SystemHUD) {
        publishHUD(hud.at(value))

        let viaNeighbour = hud.authority == .betterDisplay && externalBrightnessReachable
        guard let external = externalScreenBrightnessController, viaNeighbour else {
            screenWrites.enqueue { [self] in
                defer { onScreenBrightnessWriteFinished?() }
                if await write(value, on: hud, through: screenBrightnessController, as: .system, "system") { return }
                noteScreenBarUnconfirmed()
            }
            return
        }

        Task { @MainActor in
            defer { onScreenBrightnessWriteFinished?() }
            switch await writeThroughNeighbour(value, on: hud, through: external) {
            case .honoured:
                return
            case let .failed(newest, display):
                externalBrightnessReachable = false
                // The fallback writes the NEWEST level the neighbour left
                // unwritten, on the display that level was aimed at — never this
                // call's own argument, which by the time a drain fails is frames
                // behind the finger ("nobody wants the level a finger passed
                // through, only the one it stopped at"). It queues behind the
                // system writes already in flight and ahead of every frame after
                // this failure, which goes to the system too.
                let landed = await screenWrites.enqueue { [self] () -> Bool in
                    if display == hud.commandDisplay {
                        return await write(newest, on: hud, through: screenBrightnessController, as: .system, "fallback")
                    }
                    // An orphan aimed at another bar's display: write it where it
                    // was aimed, and never echo it here — an echo belongs to the
                    // display the call named, and this bar named a different one.
                    do {
                        _ = try await screenBrightnessController.setBrightness(newest, on: display)
                    } catch {
                        logger.error("setBrightness(screen) via fallback failed: \(error, privacy: .public)")
                    }
                    return false
                }.value
                if !landed { noteScreenBarUnconfirmed() }
            }
        }
    }

    /// What the neighbour-path caller has to decide on: either the drag is
    /// honoured (written, or echoed with a driver still owing the write), or it
    /// failed carrying the newest level nobody will write — the level the
    /// fallback must take up.
    private enum NeighbourWrite {
        case honoured
        case failed(newest: Double, display: DisplayUUID?)
    }

    /// One write attempt through the neighbour's actuator, with the echo kept
    /// apart from the evidence. A coalescing writer answers a queued frame
    /// IMMEDIATELY, before anything reaches the wire — that echo is what keeps
    /// the bar level with the finger, but recording it as a confirmed write let
    /// the rollback settle the bar on a level no display ever went to. Only a
    /// `.written` answer (or a plain conformer's return, which always follows a
    /// real write) becomes evidence; a failure surfaces the orphaned frame so the
    /// fallback writes the finger's newest level instead of a stale argument.
    private func writeThroughNeighbour(
        _ value: Double,
        on hud: SystemHUD,
        through external: any ScreenBrightnessController
    ) async -> NeighbourWrite {
        guard let coalescing = external as? any CoalescingScreenBrightnessWriting else {
            return await write(value, on: hud, through: external, as: hud.authority, "BetterDisplay")
                ? .honoured
                : .failed(newest: value, display: hud.commandDisplay)
        }
        do {
            switch try await coalescing.applyBrightness(value, on: hud.commandDisplay) {
            case .written(let written):
                confirmedScreenBrightness = written
                screenBarUnconfirmed = false
                onBrightnessApplied?(hud.at(written).by(hud.authority).echoed())
            case .coalesced(let echoed):
                // For the bar only: the driver still owes this level a write (or
                // will surface it with its error), so it is no evidence and must
                // not clear the unconfirmed mark — here, and again when this echo
                // comes back round through the HUD stream (handleHUDUpdate).
                onBrightnessApplied?(hud.at(echoed).by(hud.authority).echoed())
            }
            return .honoured
        } catch let failure as BrightnessWriteFailure {
            logger.error(
                "setBrightness(screen) via BetterDisplay failed: \(failure.underlying, privacy: .public)"
            )
            guard let orphan = failure.orphan else {
                return .failed(newest: value, display: hud.commandDisplay)
            }
            return .failed(newest: orphan.value, display: orphan.display)
        } catch {
            logger.error("setBrightness(screen) via BetterDisplay failed: \(error, privacy: .public)")
            return .failed(newest: value, display: hud.commandDisplay)
        }
    }

    /// One screen-brightness write attempt. Reports whether anything reached the
    /// wire, which is what the caller needs to decide between falling back and
    /// admitting the bar is unbacked.
    ///
    /// The echo carries what the actuator actually WROTE, not what this frame
    /// asked for: an actuator that coalesces returns holding an argument several
    /// frames old, and echoing that argument yanks the bar backwards mid-gesture —
    /// the flick a fast drag shows on the bar drawn on the external monitor
    /// itself. A conformer that can answer WITHOUT writing goes through
    /// `writeThroughNeighbour` instead, where its echo is kept apart from
    /// evidence; here, a successful return always follows a real write.
    private func write(
        _ value: Double,
        on hud: SystemHUD,
        through controller: any ScreenBrightnessController,
        as authority: SystemHUD.Authority,
        _ name: StaticString
    ) async -> Bool {
        do {
            let written = try await controller.setBrightness(value, on: hud.commandDisplay)
            confirmedScreenBrightness = written
            screenBarUnconfirmed = false
            onBrightnessApplied?(hud.at(written).by(authority))
            return true
        } catch {
            logger.error("setBrightness(screen) via \(name, privacy: .public) failed: \(error, privacy: .public)")
            return false
        }
    }

    /// A slider-driven brightness write closes its own HUD loop: on success, poke
    /// the matching sampler through `onBrightnessApplied` (see its doc) so the
    /// applied value echoes back — otherwise the indicator sticks and the revert
    /// timer never refreshes. Separate from `run` only because volume echoes
    /// itself (Core Audio) and needs no poke. `@MainActor` because the hook is.
    /// Queued on `writes` like `run`.
    private func applyBrightness(
        _ name: StaticString,
        applied: SystemHUD,
        on writes: SerialWrites,
        _ command: @escaping @Sendable () async throws -> Void
    ) {
        writes.enqueue { [self] in
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
