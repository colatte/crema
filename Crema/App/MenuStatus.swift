/// What the menu bar has to say right now, split into the blocks it says it in:
/// the controls of the app's headline feature with the facts that are true of
/// them, the warnings that need the user, and the media the app is watching.
///
/// The hierarchy is the decision — the controls first, each fact written under the
/// control it qualifies, what needs attention after that, the transport last — and
/// it lives here
/// rather than in the menu's ViewBuilder so the order and the gating are pinned by
/// tests instead of resting on the shape of a view body
/// (docs/DECISIONS.md: menu-status-before-warnings).
/// Nothing here knows a string: the view maps each case to its localized sentence
/// and, where there is one, to its repair.
struct MenuStatus {
    /// The blocks the menu is built from, in the order they appear, each one a
    /// menu section. A block with nothing to say is ABSENT rather than empty — an
    /// empty section would still draw the separator that opens it, over nothing.
    ///
    /// What is deliberately not a block: the app's own actions (Settings, updates,
    /// quit). They are unconditional, so there is no gating to pin, and the update
    /// item exists only in Release — a case for it here would be one the
    /// Debug-hosted suite can never reach, which is exactly the reason that item
    /// stays in the scene body.
    enum Block: Hashable {
        case controls
        case warnings
        case media
    }

    /// The control a fact is written under, as that item's subtitle. A fact on a
    /// line of its own reads as a disabled item and sits apart from the switch it
    /// explains; under its control it is the control's own state.
    enum Host: Equatable {
        /// "Replace the system indicators": what the replacement covers.
        case replacementSwitch
        /// The Style submenu: what the declaration draws.
        case styleMenu
    }

    /// A fact about what Crema is doing, never a wish, and never one another surface
    /// already carries. Two gates, and both are load-bearing. Every row is gated on
    /// the feature actually being IN EFFECT, because a block that restated
    /// preferences would promise "replacing the system indicators" with the native
    /// HUD on screen. And a fact the user reads on a control — the login checkbox in
    /// General, the switch at the top of this very menu — or in a sentence Settings
    /// states unconditionally is not news here: it costs a permanent note on a
    /// healthy Mac, and it teaches the reader that these lines are decoration
    /// rather than the app's own report.
    enum Row: Hashable {
        /// Notch is declared and no attached display has a slit, so every panel
        /// draws Card. The declaration itself is said by the checked item in the
        /// menu's Style submenu — a checkmark is what an NSMenu uses for exactly
        /// that — but a checkmark cannot say that nothing honours it, and a Notch
        /// tick beside a Card-shaped HUD reads as a lie
        /// (docs/DECISIONS.md: rendered-style-gates-settings).
        case styleFallsBackToCard
        case brightnessFromBetterDisplay
        /// No built-in panel in use: clamshell, or a Mac that has none. Crema applies
        /// no brightness key there — every display in use belongs to someone else —
        /// so the honest line is what Crema cannot do. The one brightness arrangement
        /// still worth a row: the pointer rule that governs the ordinary case is
        /// stated unconditionally in the Indicators tab, under the switch that turns
        /// the replacement on, and this one is stated nowhere else in the app
        /// (docs/DECISIONS.md: brightness-key-follows-the-pointer).
        case brightnessNoBuiltIn

        var host: Host {
            switch self {
            case .styleFallsBackToCard: .styleMenu
            case .brightnessFromBetterDisplay, .brightnessNoBuiltIn: .replacementSwitch
            }
        }
    }

    /// The one-click repair a warning offers, when there is one to offer.
    enum Action: Equatable {
        case grantAccessibility
        case retrySuppression
        /// Not a repair but the walk to one: nothing in this app revives a dead
        /// media source, and the Permissions tab is where the backup reader's
        /// Automation requirement is stated and granted. It exists so the line under
        /// it can state the requirement instead of spelling out a route.
        case openPermissionsTab
        case reactivateLoginItem
        case openLoginItemsSettings
    }

    /// A warning that offers no repair, so the fact itself is its item.
    enum Fact: Equatable {
        case betterDisplayAheadAndSilent
        case anotherAppAhead(String)
        case mediaControlsBlocked
    }

    /// What a warning's item IS: the repair it offers or, with none, the fact.
    /// Exhaustive on both sides, so a warning cannot be added without choosing one,
    /// and a fact cannot be added without its words — `CremaMenu` maps `Fact`
    /// exhaustively, where an optional lookup would let a warning draw nothing.
    enum Item: Equatable {
        case repair(Action)
        case fact(Fact)
    }

    /// Something the user can act on, or at least needs to know. Ordered by
    /// urgency; see `init`.
    enum Warning: Equatable {
        case accessibilityMissing
        /// The domains whose native indicator is back after a failed apply, in the
        /// enum's declared order so the same set never reads two different ways.
        case suppressionSuspended([OSDSuppressionDomain])
        case betterDisplayAheadAndSilent
        case anotherAppAhead(String)
        case nowPlayingUnavailable
        case mediaControlsBlocked
        case loginItemRevoked
        case loginItemNeedsApproval

        /// Exhaustive on purpose: a warning added without deciding whether it is a
        /// repair or a fact does not compile.
        var item: Item {
            switch self {
            case .accessibilityMissing: .repair(.grantAccessibility)
            case .suppressionSuspended: .repair(.retrySuppression)
            case .nowPlayingUnavailable: .repair(.openPermissionsTab)
            case .loginItemRevoked: .repair(.reactivateLoginItem)
            case .loginItemNeedsApproval: .repair(.openLoginItemsSettings)
            case .betterDisplayAheadAndSilent: .fact(.betterDisplayAheadAndSilent)
            case .anotherAppAhead(let app): .fact(.anotherAppAhead(app))
            case .mediaControlsBlocked: .fact(.mediaControlsBlocked)
            }
        }

        /// The repair this warning offers, read off `item`.
        var action: Action? {
            guard case .repair(let action) = item else { return nil }
            return action
        }
    }

    let blocks: [Block]
    let rows: [Row]
    let warnings: [Warning]

    /// Derives all three lists from one reading of the app's state. An initializer
    /// rather than a factory because the type IS that derivation — there is no
    /// MenuStatus that was not read off the running app.
    init(
        fallsBackToCard: Bool,
        accessibilityGranted: Bool,
        suppressionEnabled: Bool,
        suppressionAvailable: Bool,
        suspendedDomains: Set<OSDSuppressionDomain>,
        chainNotice: MediaKeyChainNotice,
        brightnessTarget: BrightnessKeyTargetNotice,
        nowPlayingActive: Bool,
        mediaCommandsAvailable: Bool,
        loginOutcome: LoginItemReconciler.Outcome
    ) {
        let suspended = OSDSuppressionDomain.allCases.filter(suspendedDomains.contains)

        var rows: [Row] = []
        if fallsBackToCard { rows.append(.styleFallsBackToCard) }
        // The neighbour reporting is the arrangement working, so it belongs here and
        // not in the warning stack, where it sat behind a checkmark and read as
        // noise (docs/DECISIONS.md: betterdisplay-osd-source). Mutually exclusive
        // with the brightness row below by construction: the target stands down for
        // any chain answer but `.quiet`.
        if chainNotice == .drawingFromBetterDisplay {
            rows.append(.brightnessFromBetterDisplay)
        }
        // Gated on Crema being the one that applies, which is the whole subject of
        // the sentence: with the pref off, the suppressor absent, or the domain
        // suspended, someone else applies the key and a line about what Crema cannot
        // reach explains nothing — where the neighbour reports, the row above speaks
        // instead, and where a domain is suspended, the warning below does. It also
        // qualifies the menu's own Toggle, which is a flat wish: with no built-in
        // panel in use, the replacement covers no screen brightness at all.
        let cremaApplies = suppressionEnabled && suppressionAvailable && suspended.isEmpty
        if cremaApplies, let row = Self.brightnessRow(for: brightnessTarget) {
            rows.append(row)
        }
        self.rows = rows

        var warnings: [Warning] = []
        // Urgency order, and the order is the contract: Accessibility first,
        // because without it no media key arrives at all and the chain reading
        // below cannot even see us; launch-at-login last, because it is about the
        // next launch rather than this session.
        if !accessibilityGranted { warnings.append(.accessibilityMissing) }
        if !suspended.isEmpty { warnings.append(.suppressionSuspended(suspended)) }
        if let warning = Self.chainWarning(for: chainNotice) { warnings.append(warning) }
        if !nowPlayingActive { warnings.append(.nowPlayingUnavailable) }
        if !mediaCommandsAvailable { warnings.append(.mediaControlsBlocked) }
        if let warning = Self.loginWarning(for: loginOutcome) { warnings.append(warning) }
        self.warnings = warnings

        var blocks: [Block] = [.controls]
        if !warnings.isEmpty { blocks.append(.warnings) }
        // The media block is gated on the chain being alive, and on the SAME value
        // the warning above it comes from: with no source reporting, a media section
        // would state as news what the warning right above just said. Alive with
        // nothing playing, the section draws nothing (NowPlayingMenuSection).
        if nowPlayingActive { blocks.append(.media) }
        self.blocks = blocks
    }

    // The three switches live out here rather than inline, and each takes exactly
    // the one value it maps: together they carried enough branches to put the
    // derivation past the cyclomatic ceiling the CI enforces. Splitting on the
    // mapping seam rather than on rows-versus-warnings keeps the ORDER of both
    // lists — which is the contract the tests pin — visible in one place.

    /// Silence for a built-in panel among others, and it is not the same silence as
    /// `.quiet`: there the app has nothing true to say, here it has a sentence that
    /// the Indicators tab already states UNCONDITIONALLY — the pointer scope, under
    /// the switch that turns the replacement on — so a menu copy would add no fact
    /// and put a note on every healthy Mac. What must never happen is this
    /// target falling through to the row below: telling a Mac that HAS a built-in
    /// display that Crema cannot control screen brightness is false, not merely
    /// redundant (docs/DECISIONS.md: brightness-key-target-in-the-menu).
    private static func brightnessRow(for target: BrightnessKeyTargetNotice) -> Row? {
        switch target {
        case .noBuiltInDisplay: .brightnessNoBuiltIn
        case .builtInAmongOthers, .quiet: nil
        }
    }

    private static func chainWarning(for notice: MediaKeyChainNotice) -> Warning? {
        switch notice {
        case .betterDisplayAheadAndSilent: .betterDisplayAheadAndSilent
        case .anotherAppAhead(let app): .anotherAppAhead(app)
        case .drawingFromBetterDisplay, .quiet: nil
        }
    }

    private static func loginWarning(for outcome: LoginItemReconciler.Outcome) -> Warning? {
        switch outcome {
        case .revokedByUpdate: .loginItemRevoked
        case .needsApproval: .loginItemNeedsApproval
        case .quiet, .userRemoved: nil
        }
    }

    /// The fact written under `host`, if there is one. At most one per host by
    /// construction: the style row is the only one hosted by the Style submenu, and
    /// the two brightness rows are mutually exclusive (see `init`).
    func note(on host: Host) -> Row? {
        rows.first { $0.host == host }
    }
}
