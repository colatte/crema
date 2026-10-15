import Testing
@testable import Crema

/// What the menu says, in which block, under which control, and in what order. The
/// blocks ARE the hierarchy — the controls with the facts written under them, what
/// needs the user, the media — and the gating is where it rots in silence: a fact
/// that restates a preference promises something the app is not doing, and a media
/// section under the line saying nothing is reporting contradicts it. All of it
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

    @Test func aHealthyMacStatesNoFact() {
        // The common shape: a Mac where the declaration is honoured and no neighbour
        // reports has no FACT left to state, so no control carries a note nobody
        // needs the menu to say.
        #expect(status().blocks == [.controls, .media])
        #expect(status().rows.isEmpty)
        #expect(status().note(on: .replacementSwitch) == nil)
        #expect(status().note(on: .styleMenu) == nil)
    }

    @Test func theMenuIsThreeBlocksAndTheOrderIsTheContract() {
        // Controls first and unconditionally: the switch is the anchor the menu
        // opens with, and on a fresh install — the feature is opt-in and ships OFF —
        // it is the only line that names the headline feature at all.
        #expect(status().blocks == [.controls, .media])
        // A warning slots between the controls and the media, never at either end:
        // what the app IS doing above it, the transport it does not govern below. A
        // fact adds no block — it is written under its control — so asking for one
        // here pins that it stays out of the block list.
        let everything = status(fallsBackToCard: true, mediaCommandsAvailable: false)
        #expect(everything.blocks == [.controls, .warnings, .media])
    }

    @Test func aDeadChainNeverPutsATransportUnderTheLineThatSaysItIsDead() {
        // With no media source reporting, a media section states as news what the
        // warning right above it already said, and holds nothing a user can act on.
        // The gate lives here, tied to the warning it belongs to, rather than in a
        // view body no test can reach.
        let dead = status(nowPlayingActive: false)
        #expect(!dead.blocks.contains(.media))
        #expect(dead.warnings.contains(.nowPlayingUnavailable))
        #expect(status().blocks.contains(.media))
    }

    @Test func aHealthyAppStatesNoFactAndWarnsAboutNothing() {
        // A healthy app states no fact: a line repeating a control the user can
        // already see is noise, so every note is conditional.
        #expect(status().rows.isEmpty)
        #expect(status().warnings.isEmpty)
    }

    @Test func withEverythingBrokenNoFactSpeaksAndNoEmptyBlockIsBuilt() {
        // Everything off or broken: the arrangement where every gate fires at once.
        // What it pins is absence — no note on a control that is not in effect, and
        // no media block whose empty section would still draw the separator that
        // opens it, over nothing.
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

    @Test func aDeclarationNothingHonoursIsSaidOutLoud() {
        // A Mac with no slit — the shipped default declares Notch and every panel
        // draws Card. The declaration itself is the checked item in the Style
        // submenu; what a checkmark cannot say is that nothing honours it, so the
        // fallback is written under that submenu
        // (docs/DECISIONS.md: rendered-style-gates-settings).
        let notchless = status(fallsBackToCard: true)
        #expect(notchless.rows.first == .styleFallsBackToCard)
        #expect(notchless.note(on: .styleMenu) == .styleFallsBackToCard)
        #expect(notchless.warnings.isEmpty)
        #expect(!status().rows.contains(.styleFallsBackToCard))
    }

    @Test func theNeighboursReportIsStatusAndNotAWarning() {
        // The arrangement the app asked the user to make.
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

    @MainActor
    @Test func theBrightnessTargetIsStatusAndNeverCollidesWithTheNeighboursRow() {
        // One arrangement still has news the user can get nowhere else: no built-in
        // panel in use, so Crema applies no brightness key at all
        // (docs/DECISIONS.md: brightness-key-target-in-the-menu).
        #expect(status(brightnessTarget: .noBuiltInDisplay).rows.contains(.brightnessNoBuiltIn))
        #expect(status(brightnessTarget: .noBuiltInDisplay).warnings.isEmpty)
        // `.builtInAmongOthers` is silent, never mapped to the remaining row: that
        // row would tell a Mac that HAS a built-in display that Crema cannot control
        // screen brightness, which is false.
        #expect(status(brightnessTarget: .builtInAmongOthers).rows.isEmpty)
        // The two rows never both appear because the composition upstream stands
        // the target down for any chain answer but `.quiet`. So the target here is
        // the one that composition really produces, for the arrangement that would
        // otherwise say both: the neighbour reporting, and no built-in panel.
        let noPanel = (hasBuiltIn: false, count: 1)
        let target = AppCore.brightnessKeyTargetNotice(
            chain: .drawingFromBetterDisplay, keysAreCaptured: true, census: { noPanel }
        )
        let drawing = status(chainNotice: .drawingFromBetterDisplay, brightnessTarget: target)
        #expect(drawing.rows.contains(.brightnessFromBetterDisplay))
        #expect(!drawing.rows.contains(.brightnessNoBuiltIn))
    }

    @Test func eachFactIsWrittenUnderTheControlItQualifies() {
        // Kills a fact written under the wrong control — the style fallback under
        // the replacement switch reads as a claim about the indicators — and a host
        // carrying two notes, which the item's single subtitle cannot show.
        #expect(MenuStatus.Row.styleFallsBackToCard.host == .styleMenu)
        #expect(MenuStatus.Row.brightnessFromBetterDisplay.host == .replacementSwitch)
        #expect(MenuStatus.Row.brightnessNoBuiltIn.host == .replacementSwitch)

        let both = status(fallsBackToCard: true, chainNotice: .drawingFromBetterDisplay)
        #expect(both.note(on: .styleMenu) == .styleFallsBackToCard)
        #expect(both.note(on: .replacementSwitch) == .brightnessFromBetterDisplay)
        let noPanel = status(fallsBackToCard: true, brightnessTarget: .noBuiltInDisplay)
        #expect(noPanel.note(on: .replacementSwitch) == .brightnessNoBuiltIn)
    }

    @Test func approvalPendingIsAWarningOfItsOwn() {
        // A non-throwing register() can park for approval: nothing opens at login
        // yet. A registration waiting on the user is a warning, with the walk to
        // Login Items under it, never a status row.
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

    @Test func aWarningWithoutARepairIsItsOwnFact() {
        // The item a warning draws is chosen here, exhaustively: a repair becomes the
        // button, and a warning with none is drawn as its fact. Kills a fact mapped to
        // the wrong one — or losing the neighbour's name on the way.
        #expect(MenuStatus.Warning.betterDisplayAheadAndSilent.item == .fact(.betterDisplayAheadAndSilent))
        #expect(MenuStatus.Warning.anotherAppAhead("Some Other App").item == .fact(.anotherAppAhead("Some Other App")))
        #expect(MenuStatus.Warning.mediaControlsBlocked.item == .fact(.mediaControlsBlocked))
        #expect(MenuStatus.Warning.accessibilityMissing.item == .repair(.grantAccessibility))
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
        // the neighbour's row, or the suspension warning. The pointer row is not
        // in this block — the Indicators footer carries it; the gate stays here,
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
