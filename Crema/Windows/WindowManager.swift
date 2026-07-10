import CoreGraphics

/// Owns one panel per screen, resolves the style per display via Preferences,
/// and pushes the state's rule frame to each panel by hand — the panel uses it
/// as the click-interactive region of its fixed window. Window frames never
/// come from SwiftUI layout.
@MainActor
final class WindowManager {
    private struct Entry {
        var screen: ScreenDescription
        var style: Style
        var panel: any PresentationPanel
    }

    private let coordinator: Coordinator
    private let preferences: Preferences
    private let makePanel: @MainActor (ScreenDescription, Style, Coordinator) -> any PresentationPanel
    private var entries: [DisplayUUID: Entry] = [:]
    private var isApplyingFrames = false
    private var needsReapply = false

    init(
        coordinator: Coordinator,
        preferences: Preferences,
        makePanel: @escaping @MainActor (ScreenDescription, Style, Coordinator) -> any PresentationPanel
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
    /// new screen → new panel; gone screen → panel closed; kept screen → kept
    /// panel (geometry refreshed).
    func updateScreens(_ screens: [ScreenDescription]) {
        let incoming = Dictionary(uniqueKeysWithValues: screens.map { ($0.id, $0) })

        for (id, entry) in entries where incoming[id] == nil {
            entry.panel.close()
            entries[id] = nil
        }

        for (id, screen) in incoming {
            if let entry = entries[id] {
                let style = resolvedStyle(for: screen)
                // The panel captures geometry-derived state at creation — the
                // slit inset, the per-state surface sizes, and the hover regions
                // (screen-space rects). Any geometry change on a kept UUID —
                // scale/resolution change, display rearrangement moving the
                // frame origin — leaves that state stale (content in the camera
                // dead zone, hover detecting at the old screen position), so the
                // panel is rebuilt. Only per-state frames flow fresh through
                // apply(frame:).
                if entry.style != style || entry.screen.geometry != screen.geometry {
                    entry.panel.close()
                    entries[id] = Entry(screen: screen, style: style, panel: makePanel(screen, style, coordinator))
                } else {
                    var updated = entry
                    updated.screen = screen
                    entries[id] = updated
                }
            } else {
                let style = resolvedStyle(for: screen)
                entries[id] = Entry(screen: screen, style: style, panel: makePanel(screen, style, coordinator))
            }
        }

        runFramePass()
    }

    /// Re-resolves the style of every display against Preferences; a changed
    /// style swaps view + frame rule by recreating that display's panel —
    /// nothing in Sources/Domain/Coordinator is involved.
    func refreshStyles() {
        for (id, entry) in entries {
            let style = resolvedStyle(for: entry.screen)
            if style != entry.style {
                entry.panel.close()
                entries[id] = Entry(screen: entry.screen, style: style, panel: makePanel(entry.screen, style, coordinator))
            }
        }
        runFramePass()
    }

    /// Re-applies the current per-frame preferences (show now playing, show
    /// controls) to every panel without recreating them — the seam the Settings
    /// toggles that only change render context (not window geometry) go through.
    func refreshPresentation() {
        runFramePass()
    }

    /// The Preferences style, except: the notch style only makes sense on a
    /// display that has a notch. A notch preference orphaned onto a non-notch
    /// display (external monitor, or the setting carried over) falls back to the
    /// card — the floating skin; the graceful path called for.
    private func resolvedStyle(for screen: ScreenDescription) -> Style {
        let preferred = preferences.style(for: screen.id)
        if preferred == .notch, screen.geometry.safeTop <= 0 {
            return .card
        }
        return preferred
    }

    // MARK: - State-driven frames

    private func applyFrames() {
        let state = coordinator.state
        for entry in entries.values {
            let effective = effectiveState(state, for: entry.screen)
            // Per display: "show now playing here" off ⇒ never armed, and the
            // panel's view suppresses now-playing content.
            let shows = preferences.showsNowPlaying(on: entry.screen.id, isInternal: entry.screen.isInternal)
            // Hover is armed only while a surface is visible on this display —
            // it expands/holds what is on screen (a paused appearance stays
            // holdable during its linger). An empty region never reacts to
            // the pointer: invocation is the click zone below.
            let hoverArmed = effective != .hidden
            // Click-invoke zone: media playing, nothing visible here — the
            // style's own zone rule (the notch's physical slit; nil for the
            // floating styles, whose region sits over live app content)
            // captures clicks to surface the appearance. Everything outside
            // it keeps falling through to the menu bar and windows below.
            let invokeZone: CGRect?
            if effective == .hidden, coordinator.mediaActive, shows {
                invokeZone = entry.style.invokeZone(on: entry.screen.geometry)
            } else {
                invokeZone = nil
            }
            entry.panel.apply(
                frame: entry.style.frame(for: effective, on: entry.screen.geometry),
                hoverArmed: hoverArmed,
                showsNowPlaying: shows,
                showsControls: preferences.showsPlaybackControls,
                hudIndicatorStyle: preferences.hudIndicatorStyle,
                invokeZone: invokeZone
            )
        }
    }

    /// Per-display policy: "show now playing here" (Preferences) suppresses the
    /// now-playing surface on displays where it's off; HUDs are unaffected.
    private func effectiveState(_ state: PresentationState, for screen: ScreenDescription) -> PresentationState {
        if case .nowPlaying = state,
           !preferences.showsNowPlaying(on: screen.id, isInternal: screen.isInternal) {
            return .hidden
        }
        return state
    }

    /// Runs synchronously inside the Coordinator's state write (didSet), so
    /// hover arming and click routing track the state in the same beat as the
    /// render (the windows themselves are fixed — no frame is racing anything).
    /// The hook fires only on `state`/`mediaActive` writes, so the position
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
