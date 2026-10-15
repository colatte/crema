import CoreGraphics
import os

/// Owns every screen's panels — one per surface its style draws there
/// (`PanelSurface`) — resolves the style per display via Preferences, and pushes
/// each panel's rule frame by hand: the panel uses it as the click-interactive
/// region of its fixed window. Window frames never come from SwiftUI layout.
@MainActor
final class WindowManager {
    private struct Entry {
        var screen: ScreenDescription
        /// The display's resolved style, which every panel on it belongs to.
        var style: Style
        /// In `PanelSurface.surfaces(for:hudPlacement:)` order.
        var panels: [Panel]
    }

    private struct Panel {
        let surface: PanelSurface
        let window: any PresentationPanel
    }

    private let coordinator: Coordinator
    private let preferences: Preferences
    private let makePanel: @MainActor (ScreenDescription, PanelSurface, Coordinator) -> any PresentationPanel
    private var entries: [DisplayUUID: Entry] = [:]
    private var isApplyingFrames = false
    private var needsReapply = false
    /// The no-owner condition already reported, so the diagnostic below states a
    /// CHANGE instead of repeating itself. The frame pass runs on every state
    /// WRITE, not every state change — the Coordinator's `didSet` has no equality
    /// guard and a HUD is republished per key repeat and per drag frame — and the
    /// conditions themselves last as long as a mirroring session, so an unguarded
    /// notice would put tens of identical lines a second into the log for one fact
    /// (docs/DECISIONS.md: hud-target-is-a-role).
    private var reportedUnownedHUD: UnownedHUD?
    private let logger = Logger.crema("Windows")

    /// The two ways a HUD can end up with no panel that owns it, kept apart
    /// because they are opposite outcomes: the first draws nowhere (deliberate),
    /// the second draws everywhere (the fall-open).
    private enum UnownedHUD: Equatable {
        case namedDisplayGone(DisplayUUID)
        case noBuiltInPanel
    }

    init(
        coordinator: Coordinator,
        preferences: Preferences,
        makePanel: @escaping @MainActor (ScreenDescription, PanelSurface, Coordinator) -> any PresentationPanel
    ) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.makePanel = makePanel
    }

    /// Registers for presentation changes. Call once after init.
    func start() {
        coordinator.onPresentationChange = { [weak self] in
            self?.presentationDidChange()
        }
    }

    /// Reconciles the panel set against the currently connected screens:
    /// new screen → its panels; gone screen → its panels closed; kept screen →
    /// its panels reconciled (`reconcile(_:)`).
    func updateScreens(_ screens: [ScreenDescription]) {
        // First key wins rather than trapping. `Dictionary(uniqueKeysWithValues:)`
        // has "must not have duplicate keys" as a PRECONDITION, so a roster with
        // two screens resolving to one DisplayUUID would take the process down —
        // on a path that runs at every hotplug and reconfiguration, which is
        // exactly where this app owes graceful degradation. Nothing here proves
        // the collision is reachable (mirroring, two identical panels with no
        // serial, AirPlay are the suspects), and that is the point: an extra screen
        // in the roster must cost at most a panel, never the app. The notice is
        // how it stops being invisible if it ever does happen.
        let incoming = Dictionary(screens.map { ($0.id, $0) }) { first, _ in
            logger.notice("two screens resolved to the same display UUID — keeping the first, the other gets no panel")
            return first
        }

        for id in entries.keys where incoming[id] == nil {
            retirePanels(id)
        }
        for screen in incoming.values {
            reconcile(screen)
        }

        runFramePass()
    }

    /// Re-resolves every display's panels against Preferences — its style and,
    /// where it draws the Card, the HUD placement — swapping view and frame rule
    /// by recreating the panels that changed; nothing in Sources/Domain/Coordinator
    /// is involved.
    func refreshStyles() {
        for screen in entries.values.map(\.screen) {
            reconcile(screen)
        }
        runFramePass()
    }

    /// Brings one display's panels in line with what it should draw. A panel whose
    /// surface is still wanted is kept; the rest close and the missing are built.
    /// Every panel captures geometry-derived state at creation — the slit inset,
    /// the per-state surface sizes, and the hover regions (screen-space rects) —
    /// so any geometry change on a kept UUID (scale/resolution change, display
    /// rearrangement moving the frame origin) rebuilds them all: kept, that state
    /// would put content in the camera dead zone and detect hover at the old
    /// screen position. Only per-state frames flow fresh through apply(frame:).
    ///
    /// The leaving panels drop out of the roster BEFORE they close, for the reason
    /// `retirePanels(_:)` spells out.
    private func reconcile(_ screen: ScreenDescription) {
        let style = resolvedStyle(for: screen)
        let wanted = PanelSurface.surfaces(for: style, hudPlacement: preferences.hudPlacement)
        let current = entries[screen.id]
        let reusable = current?.screen.geometry == screen.geometry ? current?.panels ?? [] : []
        let kept = reusable.filter { wanted.contains($0.surface) }
        let leaving = (current?.panels ?? []).filter { panel in !kept.contains { $0.surface == panel.surface } }

        entries[screen.id] = Entry(screen: screen, style: style, panels: kept)
        for panel in leaving {
            panel.window.close()
        }
        entries[screen.id]?.panels = wanted.map { surface in
            kept.first { $0.surface == surface }
                ?? Panel(surface: surface, window: makePanel(screen, surface, coordinator))
        }
    }

    /// Closes a display's panels, and the roster drops them FIRST — the order is
    /// the whole point. Closing stops a panel's hover monitor, which reports its
    /// pending exit through the Coordinator, whose state write runs a frame pass
    /// synchronously (`onPresentationChange`). With the panel still in `entries`
    /// that pass would apply to the panel just closed and re-arm its hover,
    /// reinstalling a pair of NSEvent monitors that nothing disarms again once the
    /// panel does leave — a dead panel sampling the cursor against regions on a
    /// screen that may no longer exist. Out of the roster first, the re-entrant
    /// pass simply cannot see it, and the caller's trailing pass covers whatever
    /// takes its place.
    private func retirePanels(_ id: DisplayUUID) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        for panel in entry.panels {
            panel.window.close()
        }
    }

    /// Re-applies the current per-frame preferences (show now playing, show
    /// controls) to every panel without recreating them — the seam the Settings
    /// toggles that only change render context (not window geometry) go through.
    func refreshPresentation() {
        runFramePass()
    }

    /// This display's declared style (or its per-display override) put through
    /// the render rule, which owns the notch→card fallback for a slitless panel —
    /// an orphaned notch choice degrades to the floating skin instead of drawing
    /// nothing. The rule lives on `Style` because Settings' per-display rows ask
    /// the same question (`DisplayStyleOptions`: which styles a screen draws, and
    /// what its caption names), and a second copy of the slit test would drift
    /// from this one (docs/DECISIONS.md: rendered-style-gates-settings).
    private func resolvedStyle(for screen: ScreenDescription) -> Style {
        preferences.style(for: screen.id).resolved(on: screen.geometry)
    }

    /// Whether any connected display is RENDERING this style right now — read off
    /// the panel roster, whose entries already hold the resolved value, so the
    /// answer cannot disagree with what is on screen. It feeds the notch→card
    /// fallback sentence (`Style.fallsBackToCard`) of the Settings footer, the
    /// welcome tour and the menu's status: on hardware without a notch the
    /// declaration stays notch while every panel draws card. An ANY over
    /// displays, never the leading one — a notched laptop with an external
    /// monitor renders both skins at once
    /// (docs/DECISIONS.md: rendered-style-gates-settings).
    func renders(_ style: Style) -> Bool {
        entries.values.contains { $0.style == style }
    }

    /// WHICH connected displays are rendering this style, off the same roster as
    /// `renders(_:)`. Settings gates its Card-only indicator section on this set
    /// being non-empty — gated on the declaration, that section is missing in the
    /// shipped default on hardware without a notch, with the HUD it governs on
    /// screen — and names the set under the Card indicator, so the one control
    /// that is not per display says which displays it reaches: the reason it is
    /// on screen at all in a mixed setup whose declaration is Notch.
    func displays(rendering style: Style) -> Set<DisplayUUID> {
        Set(entries.filter { $0.value.style == style }.keys)
    }

    // MARK: - State-driven frames

    private func applyFrames() {
        let state = coordinator.state
        // Which panel is the built-in one, answered ONCE per pass and from the
        // roster itself (`isInternal`, taken in the same snapshot that created the
        // panel). Deliberately not from the wider active-display list: the two
        // disagree by design, and a UUID resolved from that list can name a screen
        // no panel carries — which would hide the bar everywhere instead of scoping
        // it (docs/DECISIONS.md: hud-target-is-a-role).
        let builtInPanel = entries.values.first { $0.screen.isInternal }?.screen.id
        logIfNoPanelOwns(state, builtInPanel: builtInPanel)
        for entry in entries.values {
            // Per display: "show now playing here" off ⇒ never armed, and the
            // panel's view suppresses now-playing content.
            let shows = preferences.showsNowPlaying(on: entry.screen.id, isInternal: entry.screen.isInternal)
            for panel in entry.panels {
                apply(panel, on: entry.screen, showsNowPlaying: shows, builtInPanel: builtInPanel)
            }
        }
    }

    /// One panel's share of the pass: what it draws of the layers, scoped to its
    /// display.
    private func apply(
        _ panel: Panel,
        on screen: ScreenDescription,
        showsNowPlaying shows: Bool,
        builtInPanel: DisplayUUID?
    ) {
        let drawn = coordinator.layers.state(on: panel.surface.layers)
        let effective = effectiveState(drawn, for: screen, builtInPanel: builtInPanel)
        // Hover is armed only while a surface is visible on this panel — it
        // expands/holds what is on screen (a paused appearance stays holdable
        // during its linger). An empty region never reacts to the pointer:
        // invocation is the click zone below.
        let hoverArmed = effective != .hidden
        // Content-level scoping, the other half of `effectiveState`: the window is
        // fixed and never orders out, so a panel the HUD's target does not speak
        // for has to be told not to DRAW it — an empty frame only stops it from
        // being touched, and a bar still rendered there is a live control for a
        // screen the user is not looking at (docs/DECISIONS.md:
        // hud-target-is-a-role, hud-belongs-to-its-display).
        let showsHUD: Bool
        if case .hud = drawn {
            showsHUD = effective != .hidden
        } else {
            showsHUD = true
        }
        // Click-invoke zone: media playing, nothing visible here — the style's
        // own zone rule (the notch's physical slit; nil for the floating styles,
        // whose region sits over live app content) captures clicks to surface the
        // appearance. Everything outside it keeps falling through to the menu bar
        // and windows below. Keyed on the GLOBAL state, not this panel's: a panel
        // hidden only because the HUD belongs elsewhere must not arm the slit, or
        // the click it captures would die against `invoke()`'s hidden-only guard
        // instead of falling through to the menu bar.
        let invokeZone: CGRect?
        if coordinator.state == .hidden, coordinator.mediaActive, shows {
            invokeZone = panel.surface.invokeZone(on: screen.geometry)
        } else {
            invokeZone = nil
        }
        panel.window.apply(
            frame: panel.surface.frame(for: effective, on: screen.geometry),
            hoverArmed: hoverArmed,
            showsNowPlaying: shows,
            showsHUD: showsHUD,
            showsControls: preferences.showsPlaybackControls,
            hudIndicatorStyle: preferences.hudIndicatorStyle,
            invokeZone: invokeZone
        )
    }

    /// Per-display policy: what this display shows of what one panel draws.
    ///
    /// Two rules, from two different reasons. "Show now playing here"
    /// (Preferences) is the user's choice and suppresses the now-playing surface
    /// where it is off. A HUD's TARGET is a fact rather than a choice: a bar for
    /// one screen drawn on another is a live control for a display the user is not
    /// looking at, and its drag would dim the neighbour in silence. So the three
    /// targets answer three different questions here — no screen owns it (volume,
    /// the keyboard backlight) and it appears everywhere; a NAMED display and it
    /// appears only there, and nowhere at all if that display is gone, which is
    /// what an unplug between the report and this pass should look like; the
    /// built-in panel and it appears only on the internal one.
    ///
    /// That last one falls OPEN when the roster carries no internal panel: it then
    /// shows on every display, as a target no screen owns does. The case is
    /// reachable with the key already swallowed — a mirror set collapses to one
    /// NSScreen that may not be the internal one, and a screen with no
    /// NSScreenNumber is dropped from the roster — and a consumed key owes
    /// feedback, so too much of it beats none. Narrow on purpose: it is decided
    /// BEFORE there is an owner and never rescues a display that was named and is
    /// gone (docs/DECISIONS.md: hud-target-is-a-role).
    ///
    /// A HUD the app put up itself names its displays outright
    /// (`PresentationLayers.hudDisplays`), and appears on no other.
    private func effectiveState(
        _ state: PresentationState,
        for screen: ScreenDescription,
        builtInPanel: DisplayUUID?
    ) -> PresentationState {
        switch state {
        case .nowPlaying where !preferences.showsNowPlaying(on: screen.id, isInternal: screen.isInternal):
            return .hidden
        case .hud(let hud) where !panelOwns(hud.target, panel: screen.id, builtInPanel: builtInPanel):
            return .hidden
        case .hud where coordinator.layers.hudDisplays.map({ !$0.contains(screen.id) }) ?? false:
            return .hidden
        default:
            return state
        }
    }

    /// Whether this panel is one the HUD's target speaks for. No UUID is resolved
    /// here — `builtInPanel` came from the roster this method is scoping.
    private func panelOwns(_ target: SystemHUD.Target, panel: DisplayUUID, builtInPanel: DisplayUUID?) -> Bool {
        switch target {
        case .noDisplay: true
        case .builtIn: builtInPanel == nil || builtInPanel == panel
        case .display(let named): named == panel
        }
    }

    /// A HUD nobody draws is the worst outcome of scoping and the only one with no
    /// visible trace, so it leaves a line instead of vanishing silently. Both
    /// shapes: a named display the roster does not carry (drawn nowhere — the
    /// deliberate answer for an unplug) and a built-in HUD with no internal panel
    /// (fallen open to every display, so this one is a diagnostic, not damage).
    /// Reported on CHANGE, and that is not tidiness: this runs inside the frame
    /// pass, which fires on every state WRITE — a held key republishes the HUD per
    /// repeat, a drag per frame — while the conditions last as long as the
    /// arrangement that causes them. Repeating the line would bury the one moment
    /// it carries information.
    private func logIfNoPanelOwns(_ state: PresentationState, builtInPanel: DisplayUUID?) {
        let condition = unownedHUD(state, builtInPanel: builtInPanel)
        guard condition != reportedUnownedHUD else { return }
        reportedUnownedHUD = condition
        switch condition {
        case .namedDisplayGone:
            logger.notice("a HUD names a display with no panel — no display draws it")
        case .noBuiltInPanel:
            logger.notice("a built-in HUD with no built-in panel in the roster — showing it on every display")
        case nil:
            break
        }
    }

    private func unownedHUD(_ state: PresentationState, builtInPanel: DisplayUUID?) -> UnownedHUD? {
        guard case .hud(let hud) = state else { return nil }
        switch hud.target {
        case .display(let named) where entries[named] == nil: return .namedDisplayGone(named)
        case .builtIn where builtInPanel == nil: return .noBuiltInPanel
        default: return nil
        }
    }

    /// Runs synchronously inside the Coordinator's state write (didSet), so
    /// hover arming and click routing track the state in the same beat as the
    /// render (the windows themselves are fixed — no frame is racing anything).
    /// The hook fires only on `layers`/`mediaActive` writes, so the position
    /// tick still causes no pass.
    private func presentationDidChange() {
        runFramePass()
    }

    /// The only entry to applyFrames — every caller (the state hook, screen
    /// reconciliation, style refresh) goes through this guard. A pass can
    /// itself write state (arming a hover monitor samples the cursor, which
    /// may commit a hover synchronously), so a nested change is deferred and
    /// applied as a fresh pass after the current one — two passes never
    /// interleave, and the last one always runs with the final state.
    private func runFramePass() {
        guard !isApplyingFrames else {
            needsReapply = true
            return
        }
        isApplyingFrames = true
        repeat {
            needsReapply = false
            applyFrames()
        } while needsReapply
        isApplyingFrames = false
    }
}
