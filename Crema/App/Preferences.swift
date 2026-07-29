import Foundation

/// Injectable user preferences over UserDefaults. Everything per-display is
/// keyed by the stable display UUID (never the numeric display ID — the
/// displayID→UUID translation happens at the border, in ScreenTranslation).
struct Preferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Style: one global declaration, per-display overrides on top

    /// What the all-displays picker declared, and the fallback of `style(for:)`
    /// — which is what lets a display connected LATER inherit the user's choice
    /// instead of the shipped default. Deliberately NOT keyed under the `style.`
    /// prefix: that prefix is swept when the overrides are dropped, and the
    /// declaration has to survive its own sweep. Unset reads as the notch — the
    /// app's hero surface, which the WindowManager resolves to the card on a
    /// display without a physical slit, so it is safe everywhere.
    /// (docs/DECISIONS.md: global-style-default)
    static let declaredStyleKey = "declaredStyle"
    var declaredStyle: Style {
        get {
            guard let raw = defaults.string(forKey: Self.declaredStyleKey),
                  let style = Style(rawValue: raw) else {
                return .notch
            }
            return style
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.declaredStyleKey) }
    }

    /// This display's override when it has one, else the declaration. An unknown
    /// persisted rawValue (a style removed since — "pill", "circular") is no
    /// override at all, so it falls through to the declaration rather than to a
    /// value the user never picked.
    func style(for display: DisplayUUID) -> Style {
        persistedStyle(for: display) ?? declaredStyle
    }

    /// The per-display override. No Settings control writes it yet (the
    /// per-display picker is roadmap), but resolution above is already
    /// override-aware, which is what makes that picker a UI change only. Not
    /// dead: do not remove for lack of a production caller.
    func setStyle(_ style: Style, for display: DisplayUUID) {
        defaults.set(style.rawValue, forKey: Key.style(display))
    }

    /// The all-displays declaration, as one operation. "Applies to every
    /// display" cannot be honored by writing the attached displays alone — a
    /// monitor plugged in afterwards has no key and would keep the shipped
    /// default — so this declares globally AND drops the overrides: one left
    /// behind would hold its display on the style the user just replaced, with
    /// no UI to clear it. Only explicit user action reaches here (pref-sacred).
    func declareStyleEverywhere(_ style: Style) {
        declaredStyle = style
        clearStyleOverrides()
    }

    /// Adoption for installs that predate the declaration: back then the picker
    /// wrote per-display keys only, so the user's choice lives in them. Takes
    /// the first override in `displays` (the caller orders them — the internal
    /// display leads, matching what the picker shows) and never overwrites an
    /// existing declaration: the PRESENCE of the key closes the door, not its
    /// validity, so this fires once in an install's life and a rawValue retired
    /// by a future version cannot resurrect a stale choice. Overrides are left
    /// untouched, which is the conservative half: overrides can disagree (one
    /// pick made with only the laptop attached, a later one made in clamshell),
    /// and this order may well adopt the OLDER of them — so every display that
    /// carries a key keeps looking exactly as it looks today, and only a display
    /// that had fallen to the shipped default changes. An install with no
    /// override writes NOTHING: an eagerly written key would freeze today's
    /// shipped default in every install past any change to it.
    func adoptDeclaredStyleFromOverrides(preferring displays: [DisplayUUID]) {
        guard defaults.string(forKey: Self.declaredStyleKey) == nil,
              let adopted = displays.compactMap({ persistedStyle(for: $0) }).first else {
            return
        }
        defaults.set(adopted.rawValue, forKey: Self.declaredStyleKey)
    }

    private func persistedStyle(for display: DisplayUUID) -> Style? {
        guard let raw = defaults.string(forKey: Key.style(display)) else { return nil }
        return Style(rawValue: raw)
    }

    /// Swept by key prefix because the override set is open-ended: one key per
    /// display UUID ever seen, including displays not attached now — exactly the
    /// ones that must stop shadowing the declaration when it changes.
    private func clearStyleOverrides() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Key.stylePrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - "Show now playing here"

    /// Unset falls back to the default: on only for the internal display.
    /// (`object(forKey:)` instead of `bool(forKey:)` to distinguish unset.)
    func showsNowPlaying(on display: DisplayUUID, isInternal: Bool) -> Bool {
        defaults.object(forKey: Key.showsNowPlaying(display)) as? Bool ?? isInternal
    }

    /// Honored live by WindowManager but intentionally headless — no Settings
    /// control writes it yet (deferred to the per-display-styling roadmap; see
    /// CONTRACTS-AUDIT P5). Not dead: do not remove for lack of a caller.
    func setShowsNowPlaying(_ shows: Bool, on display: DisplayUUID) {
        defaults.set(shows, forKey: Key.showsNowPlaying(display))
    }

    // MARK: - Native-OSD suppression

    /// The raw key is exposed for @AppStorage bindings so the Settings toggle
    /// reflects the same UserDefaults source of truth the app writes.
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

    // MARK: - System-HUD indicator appearance

    /// The HUD level-indicator appearance, scoped to the Card style. Persisted
    /// as the enum rawValue; an unknown value (a variant removed since) degrades
    /// to the shipped default, `.slider`, same rule as the per-display Style.
    static let hudIndicatorStyleKey = "hudIndicatorStyle"
    var hudIndicatorStyle: HUDIndicatorStyle {
        get {
            guard let raw = defaults.string(forKey: Self.hudIndicatorStyleKey),
                  let style = HUDIndicatorStyle(rawValue: raw) else {
                return .slider
            }
            return style
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.hudIndicatorStyleKey) }
    }

    // MARK: - Launch at login (the user's INTENT, not the system's state)

    /// What the user asked for — never the truth about the registration, which
    /// only `SMAppService` knows and which macOS can revoke on its own (see
    /// LoginItemReconciler). Written exclusively by explicit user action, the
    /// same contract the suppression preference lives under (pref-sacred), so a
    /// system-side revocation can be DETECTED without the app ever deciding for
    /// the user. Off by default: the app never registers itself uninvited.
    static let launchesAtLoginKey = "launchesAtLogin"
    var launchesAtLogin: Bool {
        get { defaults.bool(forKey: Self.launchesAtLoginKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.launchesAtLoginKey) }
    }

    /// The CFBundleVersion in force when that intent was recorded. It is what
    /// distinguishes "macOS dropped the registration when the bundle changed"
    /// from "the user removed it in System Settings" — without it, the warning
    /// would nag people who deliberately turned it off outside the app.
    static let launchesAtLoginBuildKey = "launchesAtLoginBuild"
    var launchesAtLoginBuild: String? {
        get { defaults.string(forKey: Self.launchesAtLoginBuildKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.launchesAtLoginBuildKey) }
    }

    // MARK: - Accessibility onboarding

    /// Whether the first-launch Accessibility onboarding was already shown
    /// (it appears once; the persistent signal afterwards is the menu warning).
    var hasSeenAccessibilityOnboarding: Bool {
        get { defaults.bool(forKey: "hasSeenAccessibilityOnboarding") }
        nonmutating set { defaults.set(newValue, forKey: "hasSeenAccessibilityOnboarding") }
    }

    private enum Key {
        /// The override sweep walks this prefix, so nothing else may live under
        /// it — which is why the global declaration is keyed outside it.
        static let stylePrefix = "style."

        static func style(_ display: DisplayUUID) -> String {
            "\(stylePrefix)\(display.rawValue)"
        }

        static func showsNowPlaying(_ display: DisplayUUID) -> String {
            "showsNowPlaying.\(display.rawValue)"
        }
    }
}
