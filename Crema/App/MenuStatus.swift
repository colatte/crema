/// What the menu bar has to say right now, split into the blocks it says it in:
/// the switch that turns the app's headline feature on, the facts that are true of
/// it, the warnings that need the user, and the media the app is watching.
///
/// The hierarchy is the decision — the control first, what the app IS doing after
/// it, what needs attention after that, the transport last — and it lives here
/// rather than in the menu's ViewBuilder so the order and the gating are pinned by
/// tests instead of resting on the shape of a view body
/// (docs/DECISIONS.md: menu-status-before-warnings).
/// Nothing here knows a string: the view maps each case to its localized sentence
/// and, where there is one, to its repair or its advice.
struct MenuStatus {
    /// The blocks the menu is built from, in the order they appear. A block with
    /// nothing to say is ABSENT rather than empty — an empty group would still draw
    /// the separator that opens it, over nothing.
    ///
    /// What is deliberately not a block: the app's own actions (Settings, updates,
    /// quit). They are unconditional, so there is no gating to pin, and the update
    /// item exists only in Release — a case for it here would be one the
    /// Debug-hosted suite can never reach, which is exactly the reason that item
    /// stays in the scene body.
    enum Block: Equatable {
        case controls
        case status
        case warnings
        case media
    }

    /// A fact about what Crema is doing, never a wish. Every row is gated on the
    /// feature actually being IN EFFECT, because a block that restated preferences
    /// would promise "replacing the system indicators" with the native HUD on
    /// screen.
    enum Row: Hashable {
        /// Notch is declared and no attached display has a slit, so every panel
        /// draws Card. The declaration itself is said by the checked item in the
        /// menu's Style submenu — a checkmark is what an NSMenu uses for exactly
        /// that — but a checkmark cannot say that nothing honours it, and a Notch
        /// tick beside a Card-shaped HUD reads as a lie
        /// (docs/DECISIONS.md: rendered-style-gates-settings).
        case styleFallsBackToCard
        case brightnessFromBetterDisplay
        /// The rule the user cannot see: a brightness key acts on the display under
        /// the pointer, Crema applies it only on the built-in panel, and every other
        /// display is left to the system. Said out loud because both halves read as
        /// a bug unnamed — the old behavior dimmed the laptop from the monitor, and
        /// the new one makes the same key do two different things depending on where
        /// the pointer rests. Deliberately does NOT promise that the other display
        /// gets adjusted: this row only appears where no neighbour is ahead or
        /// reporting, which is where nobody may be managing it
        /// (docs/DECISIONS.md: brightness-key-follows-the-pointer).
        case brightnessFollowsPointer
        /// No built-in panel in use: clamshell, or a Mac that has none. Crema applies
        /// no brightness key there — every display in use belongs to someone else —
        /// so the honest line is what Crema cannot do.
        case brightnessNoBuiltIn
        case opensAtLogin
    }

    /// The one-click repair a warning offers, when there is one to offer.
    enum Action: Equatable {
        case grantAccessibility
        case retrySuppression
        /// Not a repair but the walk to one: nothing in this app revives a dead
        /// media source, and the Permissions tab is where the backup reader's
        /// Automation requirement is stated and granted. It exists so the sentence
        /// above it can state the requirement instead of spelling out a route.
        case openPermissionsTab
        case reactivateLoginItem
        case openLoginItemsSettings
    }

    /// A second sentence a warning owes when the button under it would not say what
    /// it is for on its own.
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
            case .nowPlayingUnavailable: .openPermissionsTab
            case .loginItemRevoked: .reactivateLoginItem
            case .loginItemNeedsApproval: .openLoginItemsSettings
            case .betterDisplayAheadAndSilent, .anotherAppAhead, .mediaControlsBlocked: nil
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
        loginOutcome: LoginItemReconciler.Outcome,
        loginRegistered: Bool
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
        // suspended, someone else applies the key and a line about Crema's aim
        // explains nothing. The field measurement that shaped this row still holds —
        // with a neighbour ahead in the tap chain the keys follow the display under
        // the POINTER, which is where Crema's own rule came from — and where Crema
        // does not apply, the row above is the one that speaks. It also qualifies
        // the menu's own Toggle, which is a flat wish: for brightness the
        // replacement holds only while the pointer is on the built-in panel.
        let cremaApplies = suppressionEnabled && suppressionAvailable && suspended.isEmpty
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

        var blocks: [Block] = [.controls]
        if !rows.isEmpty { blocks.append(.status) }
        if !warnings.isEmpty { blocks.append(.warnings) }
        // The transport is gated on the chain being alive, and on the SAME value the
        // warning above it comes from: with no source reporting, four disabled items
        // are noise rather than a control the user can wait on, and a transport
        // under the line that says nothing is reporting contradicts it. The gate
        // used to sit in the scene's ViewBuilder, where the two could drift apart
        // with no test able to see either.
        if nowPlayingActive { blocks.append(.media) }
        self.blocks = blocks
    }

    // The three switches live out here rather than inline, and each takes exactly
    // the one value it maps: together they carried enough branches to put the
    // derivation past the cyclomatic ceiling the CI enforces. Splitting on the
    // mapping seam rather than on rows-versus-warnings keeps the ORDER of both
    // lists — which is the contract the tests pin — visible in one place.

    private static func brightnessRow(for target: BrightnessKeyTargetNotice) -> Row? {
        switch target {
        case .builtInAmongOthers: .brightnessFollowsPointer
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

    /// Whether a separator OPENS the block at `index`. Every block but the first is
    /// preceded by one, and the rule is stated over the INDEX rather than over which
    /// block it is: what leads changes with what the app has to say, so a rule
    /// naming `.controls` would draw a separator above the menu's first line the day
    /// that block becomes conditional. Total at both borders, like
    /// `separatesWarning` — the view walks an enumerated list, and every index it
    /// can hold has to answer.
    func separatesBlock(at index: Int) -> Bool {
        index > 0 && blocks.indices.contains(index)
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
