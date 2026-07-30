/// What the menu bar has to say right now: a status block that is always there,
/// and warnings only when something needs the user.
///
/// The hierarchy is the decision — what the app IS doing first, what needs
/// attention after it, actions last — and it lives here rather than in the menu's
/// ViewBuilder so the order and the gating are pinned by tests instead of resting
/// on the shape of a view body (docs/DECISIONS.md: menu-status-before-warnings).
/// Nothing here knows a string: the view maps each case to its localized sentence
/// and, where there is one, to its repair or its advice.
struct MenuStatus {
    /// A fact about what Crema is doing, never a wish. Every row is gated on the
    /// feature actually being IN EFFECT, because a block that restated preferences
    /// would promise "replacing the system indicators" with the native HUD on
    /// screen.
    enum Row: Hashable {
        case style(Style)
        /// Notch is declared and no attached display has a slit, so every panel
        /// draws Card. Said out loud for the same reason Settings says it: the
        /// declaration alone, beside a Card-shaped HUD, reads as a lie
        /// (docs/DECISIONS.md: rendered-style-gates-settings).
        case styleFallsBackToCard
        case replacingSystemIndicators
        case brightnessFromBetterDisplay
        /// Correct behavior nobody can see reads as a bug: with a monitor as the
        /// main display the brightness key dims the laptop panel the user is not
        /// looking at. Crema drives the built-in panel because that is the only
        /// display it has been TAUGHT to drive with the keys — not because an
        /// external one is out of reach. It is reachable: the neighbour reads and
        /// writes brightness, and an earlier claim to the contrary here was our own
        /// probe asking through the metadata door
        /// (docs/DECISIONS.md: neighbour-features-are-not-identifiers). Until the
        /// keys learn to follow the screen in use, this row is the honest one.
        case brightnessBuiltInOnly
        /// No built-in panel in use: clamshell, or a Mac that has none. The write
        /// degrades to false there rather than reaching for whatever display is
        /// main, so the honest line is what Crema cannot do.
        case brightnessNoBuiltIn
        case opensAtLogin
    }

    /// The one-click repair a warning offers, when there is one to offer.
    enum Action: Equatable {
        case grantAccessibility
        case retrySuppression
        case reactivateLoginItem
        case openLoginItemsSettings
    }

    /// A second sentence a warning owes when the trail out of it is not a button.
    enum Advice: Equatable {
        /// Now Playing is dead, so the BACKUP reader is what is left — and that one
        /// needs Automation access, a requirement the app used to have without ever
        /// naming it. States the requirement, never a verdict: nothing here knows
        /// whether consent is the reason, and reading that state would put a poll
        /// behind a body whose rebuild costs the tap-chain read.
        case automationForBackupReader
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

        /// The repair this warning offers. Exhaustive on purpose: a warning added
        /// without deciding whether it has an action does not compile.
        var action: Action? {
            switch self {
            case .accessibilityMissing: .grantAccessibility
            case .suppressionSuspended: .retrySuppression
            case .loginItemRevoked: .reactivateLoginItem
            case .loginItemNeedsApproval: .openLoginItemsSettings
            case .betterDisplayAheadAndSilent, .anotherAppAhead, .nowPlayingUnavailable, .mediaControlsBlocked: nil
            }
        }

        var advice: Advice? {
            switch self {
            case .nowPlayingUnavailable: .automationForBackupReader
            case .accessibilityMissing, .suppressionSuspended, .betterDisplayAheadAndSilent,
                 .anotherAppAhead, .mediaControlsBlocked, .loginItemRevoked, .loginItemNeedsApproval: nil
            }
        }
    }

    let rows: [Row]
    let warnings: [Warning]

    /// Derives both lists from one reading of the app's state. An initializer
    /// rather than a factory because the type IS that derivation — there is no
    /// MenuStatus that was not read off the running app.
    init(
        style: Style,
        fallsBackToCard: Bool,
        accessibilityGranted: Bool,
        suppressionEnabled: Bool,
        suppressionAvailable: Bool,
        suspendedDomains: Set<OSDSuppressionDomain>,
        chainNotice: MediaKeyChainNotice,
        brightnessTarget: BrightnessKeyTargetNotice,
        nowPlayingActive: Bool,
        mediaCommandsAvailable: Bool,
        loginOutcome: LoginItemReconciler.Outcome,
        loginRegistered: Bool
    ) {
        let suspended = OSDSuppressionDomain.allCases.filter(suspendedDomains.contains)

        // The style row opens the menu unconditionally: it is the anchor line, so
        // the first item never moves under the pointer as conditions come and go.
        var rows: [Row] = [.style(style)]
        if fallsBackToCard { rows.append(.styleFallsBackToCard) }
        // The claim is about the keys right now, so a suspended domain takes it
        // away entirely: with the native indicator back for one channel the flat
        // sentence is false for that channel, and the warning below is the news.
        let cremaApplies = suppressionEnabled && suppressionAvailable && suspended.isEmpty
        if cremaApplies { rows.append(.replacingSystemIndicators) }
        // The neighbour reporting is the arrangement working, so it belongs here and
        // not in the warning stack, where it sat behind a checkmark and read as
        // noise (docs/DECISIONS.md: betterdisplay-osd-source). Mutually exclusive
        // with the brightness row below by construction: the target stands down for
        // any chain answer but `.quiet`.
        if chainNotice == .drawingFromBetterDisplay {
            rows.append(.brightnessFromBetterDisplay)
        }
        // Gated on Crema being the one that applies, which is the whole subject of
        // the sentence. Measured in the field, and this is why: with a neighbour
        // ahead in the tap chain the keys follow the display under the POINTER, so
        // "Crema drives the built-in only" would be true about Crema and useless to
        // the person reading it — the monitor they are looking at responds. Where
        // Crema does not apply, the row above is the one that speaks.
        if cremaApplies, let row = Self.brightnessRow(for: brightnessTarget) {
            rows.append(row)
        }
        // Only a registration macOS honours right now: requiresApproval opens
        // nothing yet, and it has its own warning below.
        if loginRegistered { rows.append(.opensAtLogin) }
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
    }

    // The three switches live out here rather than inline, and each takes exactly
    // the one value it maps: together they carried enough branches to put the
    // derivation past the cyclomatic ceiling the CI enforces. Splitting on the
    // mapping seam rather than on rows-versus-warnings keeps the ORDER of both
    // lists — which is the contract the tests pin — visible in one place.

    private static func brightnessRow(for target: BrightnessKeyTargetNotice) -> Row? {
        switch target {
        case .builtInAmongOthers: .brightnessBuiltInOnly
        case .noBuiltInDisplay: .brightnessNoBuiltIn
        case .quiet: nil
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

    /// Whether a separator OPENS the warning at `index`. A warning that offers a
    /// repair is fenced from its neighbours in both directions — an unfenced button
    /// sits flush against the next sentence and reads as that sentence's repair —
    /// and stating the rule over the PAIR is what keeps two adjacent actionable
    /// warnings to one separator instead of two. Index 0 is already opened by the
    /// block's own separator, and the upper bound keeps the rule total.
    func separatesWarning(at index: Int) -> Bool {
        guard index > 0, warnings.indices.contains(index) else { return false }
        return warnings[index].action != nil || warnings[index - 1].action != nil
    }
}
