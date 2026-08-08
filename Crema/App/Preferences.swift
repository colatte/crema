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
    /// app's hero surface, safe to DECLARE everywhere because the render rule
    /// (`Style.resolved(on:)`) draws it as the card where there is no physical
    /// slit. Safe to declare is not what a display draws, though: a style-scoped
    /// UI control has to ask the rendered answer, never this one.
    /// (docs/DECISIONS.md: global-style-default, rendered-style-gates-settings)
    static let declaredStyleKey = "declaredStyle"
    /// The shipped default, named once: the menu bar reads this same key (through
    /// the resolver below), and a second literal `.notch` over there would start
    /// lying the day this default changes. Why notch is safe to declare everywhere
    /// is the comment above.
    static let defaultDeclaredStyle = Style.notch

    /// The override key of one display, exposed for the @AppStorage binding of a
    /// per-display control, which cannot call an instance accessor. Delegates to
    /// `Key` so the exposed spelling is byte-for-byte the one this type writes —
    /// and so it stays under the prefix the declaration's sweep walks.
    static func styleKey(for display: DisplayUUID) -> String {
        Key.style(display)
    }

    /// The key's whole reading rule, over the raw value: unset — or a rawValue a
    /// future version retired — resolves to the shipped default. Static so the two
    /// readers of this key, this type and the menu's @AppStorage, cannot disagree
    /// about either half.
    static func declaredStyle(fromRawValue raw: String?) -> Style {
        guard let raw, let style = Style(rawValue: raw) else { return defaultDeclaredStyle }
        return style
    }

    /// The whole per-display reading rule, over the two raw values: an override
    /// the app can still name wins; anything else — unset, or a rawValue a future
    /// version retired — falls through to the DECLARATION, and only from there to
    /// the shipped default. A retired override deliberately does NOT reach the
    /// default: it is not a choice the user made, so it must not outrank one he
    /// did make (docs/DECISIONS.md: global-style-default). Static so a control
    /// reading both keys raw through @AppStorage resolves by the same rule the
    /// app renders by, instead of a second copy of it.
    static func style(overrideRawValue: String?, declaredRawValue: String?) -> Style {
        styleOverride(fromRawValue: overrideRawValue) ?? declaredStyle(fromRawValue: declaredRawValue)
    }

    /// The one home of "does this raw value name a style the app still ships?" —
    /// a retired rawValue reads as no override at all, so it falls to the
    /// declaration, never to the factory default (the user never chose it).
    /// Static because a view reaches the raw key through @AppStorage, not the
    /// store; the instance accessor and the resolver above both funnel here.
    static func styleOverride(fromRawValue raw: String?) -> Style? {
        raw.flatMap { Style(rawValue: $0) }
    }

    var declaredStyle: Style {
        get { Self.declaredStyle(fromRawValue: defaults.string(forKey: Self.declaredStyleKey)) }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.declaredStyleKey) }
    }

    /// This display's override when it has one, else the declaration — through
    /// the shared resolver, so there is one rule and not one per reader.
    func style(for display: DisplayUUID) -> Style {
        Self.style(
            overrideRawValue: defaults.string(forKey: Key.style(display)),
            declaredRawValue: defaults.string(forKey: Self.declaredStyleKey)
        )
    }

    /// This display's own choice, or nil when it inherits — the distinction a
    /// per-display control shows and `style(for:)` resolves away. A rawValue a
    /// future version retired reads as nil for the same reason it does not
    /// resolve: presenting it as this display's choice would name a style the app
    /// can no longer draw.
    func styleOverride(for display: DisplayUUID) -> Style? {
        Self.styleOverride(fromRawValue: defaults.string(forKey: Key.style(display)))
    }

    /// The per-display override, written programmatically; a control binds
    /// `styleKey(for:)` instead of calling here, so do not remove this for lack
    /// of a production caller — it is the same key from the other side.
    func setStyle(_ style: Style, for display: DisplayUUID) {
        defaults.set(style.rawValue, forKey: Key.style(display))
    }

    /// Returns one display to the declaration, and only that display. Inheriting
    /// IS the absence of the key, so this removes rather than writing the current
    /// declaration into it: a copy would look identical today and then shadow the
    /// next declaration forever, which is the bug the declaration exists to fix.
    /// A display that already inherits gets nothing written — not the key, not
    /// the declaration.
    func clearStyle(for display: DisplayUUID) {
        defaults.removeObject(forKey: Key.style(display))
    }

    /// The all-displays declaration, as one operation. "Applies to every
    /// display" cannot be honored by writing the attached displays alone — a
    /// monitor plugged in afterwards has no key and would keep the shipped
    /// default — so this declares globally AND drops the overrides: one left
    /// behind would hold its display on the style the user just replaced, and a
    /// display not attached right now is one no per-display control can reach —
    /// `clearStyle(for:)` needs a display in front of the user. Only explicit
    /// user action reaches here (pref-sacred).
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
              let adopted = displays.compactMap({ styleOverride(for: $0) }).first else {
            return
        }
        defaults.set(adopted.rawValue, forKey: Self.declaredStyleKey)
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

    /// The key of one display, exposed for the @AppStorage binding of a
    /// per-display control, which cannot call an instance accessor. Delegates to
    /// `Key` so the exposed spelling is byte-for-byte the one this type writes.
    static func showsNowPlayingKey(for display: DisplayUUID) -> String {
        Key.showsNowPlaying(display)
    }

    /// The unset reading, named once: this type and a control that binds the key
    /// raw both ask here, so the internal display's "on" is not spelled twice and
    /// left to drift. On only for the internal display — the surface belongs
    /// where the user's eyes rest by default, and any other display says so
    /// explicitly.
    static func defaultShowsNowPlaying(isInternal: Bool) -> Bool {
        isInternal
    }

    /// (`object(forKey:)` instead of `bool(forKey:)` to distinguish unset from a
    /// stored `false`, which the default above is not free to override.)
    func showsNowPlaying(on display: DisplayUUID, isInternal: Bool) -> Bool {
        defaults.object(forKey: Key.showsNowPlaying(display)) as? Bool
            ?? Self.defaultShowsNowPlaying(isInternal: isInternal)
    }

    /// Honored live by WindowManager; written programmatically, while a
    /// per-display control binds `showsNowPlayingKey(for:)` instead of calling
    /// here. Do not remove for lack of a caller — it is the same key from the
    /// other side.
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

    // MARK: - Lock screen

    /// The raw key, exposed for the @AppStorage binding the Settings toggle uses.
    static let showsLockScreenWidgetKey = "showsLockScreenWidget"

    /// Now playing on the lock screen. Opt-in and born off via `bool(forKey:)`:
    /// it draws over a security surface using a private space API, which is not
    /// something an app should start doing on the user's behalf. Deliberately
    /// NOT under the `style.` prefix — `clearStyleOverrides` sweeps everything
    /// there when the declaration changes.
    var showsLockScreenWidget: Bool {
        get { defaults.bool(forKey: Self.showsLockScreenWidgetKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.showsLockScreenWidgetKey) }
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

    // MARK: - Welcome tour

    /// Whether the welcome tour has already been presented. Once per install: it
    /// is the walk through the app's setup, not a reference — the menu bar and
    /// Settings are where any of it is reached again, and the Accessibility
    /// warning in the menu is the persistent signal for the one step that can
    /// stay unfinished. Unset reads false, which is the only reading a fresh
    /// install can produce.
    var hasSeenWelcomeTour: Bool {
        get { defaults.bool(forKey: "hasSeenWelcomeTour") }
        nonmutating set { defaults.set(newValue, forKey: "hasSeenWelcomeTour") }
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
