import Foundation

/// Injectable user preferences over UserDefaults. Everything per-display is
/// keyed by the stable display UUID (never the numeric display ID — the
/// displayID→UUID translation happens at the border, in ScreenTranslation).
struct Preferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Style per display

    /// Default style is the notch — the app's hero surface; on displays
    /// without a physical notch the WindowManager resolves it to the card, so
    /// the default is safe everywhere. Unknown persisted rawValues (styles
    /// removed since — "pill", "circular") land here too.
    func style(for display: DisplayUUID) -> Style {
        guard let raw = defaults.string(forKey: Key.style(display)),
              let style = Style(rawValue: raw) else {
            return .notch
        }
        return style
    }

    func setStyle(_ style: Style, for display: DisplayUUID) {
        defaults.set(style.rawValue, forKey: Key.style(display))
    }

    // MARK: - "Show now playing here"

    /// Unset falls back to the default: on only for the internal display.
    /// (`object(forKey:)` instead of `bool(forKey:)` to distinguish unset.)
    func showsNowPlaying(on display: DisplayUUID, isInternal: Bool) -> Bool {
        defaults.object(forKey: Key.showsNowPlaying(display)) as? Bool ?? isInternal
    }

    func setShowsNowPlaying(_ shows: Bool, on display: DisplayUUID) {
        defaults.set(shows, forKey: Key.showsNowPlaying(display))
    }

    // MARK: - Native-OSD suppression

    /// The raw key is exposed for @AppStorage bindings so the Settings toggle
    /// and the auto-disengage path share one source of truth in UserDefaults.
    static let suppressesNativeOSDKey = "suppressesNativeOSD"

    /// Suppression is opt-in and off by default — the user activates it.
    var suppressesNativeOSD: Bool {
        get { defaults.bool(forKey: Self.suppressesNativeOSDKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.suppressesNativeOSDKey) }
    }

    // MARK: - Now-playing behavior

    /// Reactive appearance: media events (track change, external play/pause)
    /// surface the compact appearance on their own. Default on — it matches the
    /// behavior the app shipped with, so playing media shows something out of
    /// the box. (Reactive was originally conceived as opt-in on top of a persistent-compact
    /// quiet mode; this codebase's appearances are timed, so quiet here means
    /// "no self-appearance" and defaulting it on avoids a surface that seems
    /// never to show. The user picks quiet in Settings.)
    static let reactiveNowPlayingKey = "reactiveNowPlaying"
    var reactiveNowPlaying: Bool {
        get { defaults.object(forKey: Self.reactiveNowPlayingKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.reactiveNowPlayingKey) }
    }

    /// Whether browser media (Safari, Chrome, …) is shown in the now-playing.
    /// Default off: autoplay video would otherwise flicker the surface. The
    /// Coordinator consumes the inverse (`ignoresBrowserMedia`).
    static let includesBrowserMediaKey = "includesBrowserMedia"
    var includesBrowserMedia: Bool {
        get { defaults.bool(forKey: Self.includesBrowserMediaKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.includesBrowserMediaKey) }
    }

    /// Whether the expanded surface shows the transport controls. Off is the
    /// view-only mode — cover + title/artist + scrubber, no action buttons.
    /// Default on.
    static let showsPlaybackControlsKey = "showsPlaybackControls"
    var showsPlaybackControls: Bool {
        get { defaults.object(forKey: Self.showsPlaybackControlsKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.showsPlaybackControlsKey) }
    }

    // MARK: - Accessibility onboarding

    /// Whether the first-launch Accessibility onboarding was already shown
    /// (it appears once; the persistent signal afterwards is the menu warning).
    var hasSeenAccessibilityOnboarding: Bool {
        get { defaults.bool(forKey: "hasSeenAccessibilityOnboarding") }
        nonmutating set { defaults.set(newValue, forKey: "hasSeenAccessibilityOnboarding") }
    }

    private enum Key {
        static func style(_ display: DisplayUUID) -> String {
            "style.\(display.rawValue)"
        }
        static func showsNowPlaying(_ display: DisplayUUID) -> String {
            "showsNowPlaying.\(display.rawValue)"
        }
    }
}
