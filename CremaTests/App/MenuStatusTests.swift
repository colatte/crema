import Testing
@testable import Crema

/// What the menu says, in which block, and in what order. The blocks ARE the
/// hierarchy — the switch that turns the headline feature on, the facts it is true
/// of, what needs the user, the media — and the gating is where it rots in silence:
/// a row that restates a preference promises something the app is not doing, and a
/// media block under the line saying nothing is reporting contradicts it. All of it
/// lives in MenuStatus and is pinned here, not in a view body no test can reach
/// (docs/DECISIONS.md: menu-status-before-warnings).
struct MenuStatusTests {

    /// A healthy app on hardware that honours the declaration, with every fact
    /// overridable one at a time.
    private func status(
        fallsBackToCard: Bool = false,
        accessibilityGranted: Bool = true,
        suppressionEnabled: Bool = true,
        suppressionAvailable: Bool = true,
        suspendedDomains: Set<OSDSuppressionDomain> = [],
        chainNotice: MediaKeyChainNotice = .quiet,
        brightnessTarget: BrightnessKeyTargetNotice = .quiet,
        nowPlayingActive: Bool = true,
        mediaCommandsAvailable: Bool = true,
        loginOutcome: LoginItemReconciler.Outcome = .quiet
    ) -> MenuStatus {
        MenuStatus(
            fallsBackToCard: fallsBackToCard,
            accessibilityGranted: accessibilityGranted,
            suppressionEnabled: suppressionEnabled,
            suppressionAvailable: suppressionAvailable,
            suspendedDomains: suspendedDomains,
            chainNotice: chainNotice,
            brightnessTarget: brightnessTarget,
            nowPlayingActive: nowPlayingActive,
            mediaCommandsAvailable: mediaCommandsAvailable,
            loginOutcome: loginOutcome
        )
    }

    @Test func theStatusBlockIsAbsentOnAHealthyMac() {
        // The common shape, and the change this subtraction makes observable: a Mac
        // where the declaration is honoured and no neighbour reports has no FACT left
        // to state. "Crema opens at login" was the mirror of a checkbox the user
        // reads in General, and the pointer scope is stated unconditionally in the
        // Indicators tab, right under the switch that turns the replacement on — a
        // row that restates another surface is not news, and it made the status block
        // permanent. So the block is absent here rather than carrying a line nobody
        // needs the menu to say.
        #expect(status().blocks == [.controls, .media])
        #expect(status().rows.isEmpty)
    }

    @Test func theMenuIsFourBlocksAndTheOrderIsTheContract() {
        // Controls first and unconditionally: the switch is the anchor the menu
        // opens with, and on a fresh install — the feature is opt-in and ships OFF —
        // it is the only line that names the headline feature at all.
        #expect(status().blocks == [.controls, .media])
        // A warning slots between the facts and the media, never at either end: what
        // the app IS doing above it, the transport it does not govern below. The fact
        // has to be asked for now — no row is true of a healthy Mac any more — and
        // asking for it is what keeps this pinning the ORDER of four blocks rather
        // than of the three that survive on their own.
        let everything = status(fallsBackToCard: true, mediaCommandsAvailable: false)
        #expect(everything.blocks == [.controls, .status, .warnings, .media])
    }

    @Test func aDeadChainNeverPutsATransportUnderTheLineThatSaysItIsDead() {
        // With no media source reporting, a "Nothing playing" row states as news what
        // the warning right above it already said, and it is the one line in the menu
        // no user can act on. The gate used to live in the scene's ViewBuilder, where
        // no test could reach it and nothing tied it to the warning it belongs to.
        let dead = status(nowPlayingActive: false)
        #expect(!dead.blocks.contains(.media))
        #expect(dead.warnings.contains(.nowPlayingUnavailable))
        #expect(status().blocks.contains(.media))
    }

    @Test func aHealthyAppStatesNoFactAndWarnsAboutNothing() {
        // Each row this used to hold left for the same reason, one round apart: the
        // replacement claim because the menu's own Toggle states it checked, the
        // login row because the General checkbox is where that fact is read AND
        // changed. A sentence repeating a control the user can see is noise, and the
        // control is the honest place for the fact — so a healthy app says nothing
        // here and warns about nothing, which is the whole point of the block being
        // conditional.
        #expect(status().rows.isEmpty)
        #expect(status().warnings.isEmpty)
    }

    @Test func withNothingToReportTheStatusBlockSimplyIsNotThere() {
        // Everything off or broken — no longer the only way to empty the block (a
        // healthy Mac empties it too), but still the arrangement where every gate
        // fires at once, and what it pins is the absence itself: an empty block would
        // still draw the separator that opens it, over nothing.
        let broken = status(
            accessibilityGranted: false,
            suppressionEnabled: false,
            suppressionAvailable: false,
            nowPlayingActive: false,
            mediaCommandsAvailable: false
        )
        #expect(broken.rows.isEmpty)
        #expect(broken.blocks == [.controls, .warnings])
    }

    @Test func aSeparatorOpensEveryBlockButTheFirst() {
        // EVERY block but the first, which takes three of them to say: with a healthy
        // Mac down to two blocks, a rule that fenced only the second would pass here
        // and drop the separator above the media the day a fact appears.
        let withAFact = status(fallsBackToCard: true)
        #expect(withAFact.blocks == [.controls, .status, .media])
        #expect(!withAFact.separatesBlock(at: 0))
        #expect(withAFact.separatesBlock(at: 1))
        #expect(withAFact.separatesBlock(at: 2))

        let healthy = status()
        #expect(healthy.blocks == [.controls, .media])
        #expect(!healthy.separatesBlock(at: 0))
        #expect(healthy.separatesBlock(at: 1))
        // Total at both borders, like separatesWarning: the view walks an enumerated
        // list, so every index it can hold has to answer instead of trapping.
        #expect(!healthy.separatesBlock(at: 2))
        #expect(!healthy.separatesBlock(at: -1))
    }

    @Test func aDeclarationNothingHonoursIsSaidOutLoud() {
        // A Mac with no slit — the shipped default declares Notch and every panel
        // draws Card. The declaration itself is the checked item in the Style
        // submenu; what a checkmark cannot say is that nothing honours it, so the
        // fallback keeps its row and now opens the block
        // (docs/DECISIONS.md: rendered-style-gates-settings).
        let notchless = status(fallsBackToCard: true)
        #expect(notchless.rows.first == .styleFallsBackToCard)
        #expect(notchless.warnings.isEmpty)
        #expect(!status().rows.contains(.styleFallsBackToCard))
    }

    @Test func theNeighboursReportIsStatusAndNotAWarning() {
        // The arrangement the app asked the user to make. It used to sit in the
        // warning stack behind a checkmark, which is why it read as noise.
        let drawing = status(chainNotice: .drawingFromBetterDisplay)
        #expect(drawing.rows.contains(.brightnessFromBetterDisplay))
        #expect(drawing.warnings.isEmpty)
    }

    @Test func aSuspendedDomainReplacesTheClaimWithTheNews() {
        // Suppression is engaged and one channel's native indicator is back: the
        // flat claim is false for that channel, and the warning is what the user
        // needs. Domains in declared order, so the same set never reads two ways.
        let suspended = status(suspendedDomains: [.keyboardBrightness, .volume])
        #expect(suspended.warnings == [.suppressionSuspended([.volume, .keyboardBrightness])])
        #expect(suspended.rows.isEmpty)   // and no claim beside it
    }

    @Test func theBrightnessTargetIsStatusAndNeverCollidesWithTheNeighboursRow() {
        // One arrangement still has news the user can get nowhere else: no built-in
        // panel in use, so Crema applies no brightness key at all
        // (docs/DECISIONS.md: brightness-key-target-in-the-menu).
        #expect(status(brightnessTarget: .noBuiltInDisplay).rows.contains(.brightnessNoBuiltIn))
        #expect(status(brightnessTarget: .noBuiltInDisplay).warnings.isEmpty)
        // A built-in panel among others is now SILENT, and silent is not "says the
        // other row": the pointer scope is stated unconditionally in the Indicators
        // tab, so the menu copy was redundant — but mapping this target to the
        // remaining row would tell a Mac that HAS a built-in display that Crema
        // cannot control screen brightness, which is false.
        #expect(status(brightnessTarget: .builtInAmongOthers).rows.isEmpty)
        // The composition upstream stands the target down for any chain answer but
        // `.quiet`, so the neighbour's row and the brightness row are mutually
        // exclusive by construction — this pins that they never both appear.
        let drawing = status(chainNotice: .drawingFromBetterDisplay, brightnessTarget: .quiet)
        #expect(drawing.rows.contains(.brightnessFromBetterDisplay))
        #expect(!drawing.rows.contains(.brightnessNoBuiltIn))
    }

    @Test func approvalPendingIsAWarningOfItsOwn() {
        // A non-throwing register() can park for approval: nothing opens at login
        // yet. The half of this that pinned the absent row went with the row itself —
        // the General checkbox is where that state is read now — and what survives is
        // the half no other surface carries: a registration waiting on the user is a
        // warning, with the walk to Login Items under it.
        let pending = status(loginOutcome: .needsApproval)
        #expect(pending.warnings == [.loginItemNeedsApproval])
        #expect(pending.rows.isEmpty)
    }

    @Test func warningsComeInAFixedOrderMostUrgentFirst() {
        // Everything wrong at once — the shape a fresh, broken install really takes.
        // Accessibility leads because without it no media key arrives at all;
        // launch-at-login trails because it is about the next launch.
        let bad = status(
            accessibilityGranted: false,
            suspendedDomains: [.volume],
            chainNotice: .anotherAppAhead("Some Other App"),
            nowPlayingActive: false,
            mediaCommandsAvailable: false,
            loginOutcome: .revokedByUpdate
        )
        #expect(bad.warnings == [
            .accessibilityMissing,
            .suppressionSuspended([.volume]),
            .anotherAppAhead("Some Other App"),
            .nowPlayingUnavailable,
            .mediaControlsBlocked,
            .loginItemRevoked,
        ])
        #expect(bad.rows.isEmpty)
    }

    @Test func onlyAWarningWithARepairOffersOne() {
        // The PAIRING itself: a retry button under the login warning would ship
        // green otherwise, since the menu's switch is compile-checked for
        // exhaustiveness and not for correctness.
        #expect(MenuStatus.Warning.accessibilityMissing.action == .grantAccessibility)
        #expect(MenuStatus.Warning.suppressionSuspended([.volume]).action == .retrySuppression)
        #expect(MenuStatus.Warning.loginItemRevoked.action == .reactivateLoginItem)
        #expect(MenuStatus.Warning.loginItemNeedsApproval.action == .openLoginItemsSettings)
        // No button revives a dead media source, but the trail out of it is a place
        // in this app — the tab where the backup reader's requirement is granted —
        // so the sentence above it stops naming the tab and this walks there.
        #expect(MenuStatus.Warning.nowPlayingUnavailable.action == .openPermissionsTab)
        // Naming who is ahead in the tap chain is all the app can honestly do, and
        // a command the player refused has no repair on this side.
        #expect(MenuStatus.Warning.anotherAppAhead("Some Other App").action == nil)
        #expect(MenuStatus.Warning.betterDisplayAheadAndSilent.action == nil)
        #expect(MenuStatus.Warning.mediaControlsBlocked.action == nil)
    }

    @Test func onlyTheDeadNowPlayingCarriesTheTrailOutOfIt() {
        // The one warning with no button but a second sentence: the backup reader
        // needs Automation access, a requirement the app used to have without ever
        // naming it. That advice on any other warning is a non sequitur.
        #expect(MenuStatus.Warning.nowPlayingUnavailable.advice == .automationForBackupReader)
        #expect(MenuStatus.Warning.mediaControlsBlocked.advice == nil)
        #expect(MenuStatus.Warning.accessibilityMissing.advice == nil)
        #expect(MenuStatus.Warning.betterDisplayAheadAndSilent.advice == nil)
    }

    @Test func anActionableWarningIsFencedOnceFromItsNeighbours() {
        let twoActionable = status(
            accessibilityGranted: false,
            suppressionAvailable: false,
            loginOutcome: .revokedByUpdate
        )
        #expect(twoActionable.warnings == [.accessibilityMissing, .loginItemRevoked])
        // ONE separator between two actionable warnings, not the two a
        // fence-before-plus-fence-after rule would emit.
        #expect(twoActionable.separatesWarning(at: 1))

        // A plain sentence following an actionable one is fenced too: the button
        // above it must not read as its repair.
        let mixed = status(
            accessibilityGranted: false,
            suppressionAvailable: false,
            mediaCommandsAvailable: false
        )
        #expect(mixed.warnings == [.accessibilityMissing, .mediaControlsBlocked])
        #expect(mixed.separatesWarning(at: 1))

        // Two plain sentences read as a list and need no fence between them.
        let plain = status(chainNotice: .betterDisplayAheadAndSilent, mediaCommandsAvailable: false)
        #expect(plain.warnings == [.betterDisplayAheadAndSilent, .mediaControlsBlocked])
        #expect(!plain.separatesWarning(at: 1))
        // The block's own separator already opened the first one, and asking past
        // the end is not a question the view can ask — both stay total.
        #expect(!plain.separatesWarning(at: 0))
        #expect(!plain.separatesWarning(at: 2))
    }

    @Test func theBrightnessRowSpeaksOnlyWhereCremaIsTheOneApplying() {
        // Field evidence, and the reason this gate exists at all. With a neighbour
        // ahead in the tap chain the brightness keys follow the display under the
        // POINTER — measured: pointer on the monitor moved the monitor, pointer on
        // the laptop moved the laptop, same build, same chain order. A row about what
        // Crema does with a key it is not the one applying is true about Crema and
        // useless to the person reading it, because the screen they are looking at
        // responds anyway.
        //
        // So the row speaks only where Crema is the one that writes: opted in,
        // available, and no domain suspended. Everywhere else another line speaks —
        // the neighbour's row, or the suspension warning. The pointer row left this
        // block as a copy of the Indicators footer; the gate did NOT leave with it,
        // because "Crema can't control screen brightness" makes exactly the same
        // promise about who applies.
        for target in [BrightnessKeyTargetNotice.noBuiltInDisplay] {
            #expect(
                status(brightnessTarget: target).rows.contains(.brightnessNoBuiltIn),
                "\(target) should speak while Crema applies"
            )

            for silenced in [
                status(suppressionEnabled: false, brightnessTarget: target),
                status(suppressionAvailable: false, brightnessTarget: target),
                status(suspendedDomains: [.screenBrightness], brightnessTarget: target),
            ] {
                #expect(
                    !silenced.rows.contains(.brightnessNoBuiltIn),
                    "\(target) must stay silent where Crema does not apply"
                )
            }
        }
    }
}
