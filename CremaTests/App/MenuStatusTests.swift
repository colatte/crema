import Testing
@testable import Crema

/// What the menu says, and in what order. The hierarchy is the decision (status
/// first, warnings only when they exist) and the gating is where it rots in
/// silence — a row that restates a preference promises something the app is not
/// doing, a row that restates the DECLARED style promises a shape the display is
/// not drawing, and a row that names the brightness target while a neighbour draws
/// the bar is plainly false — so all of it lives in MenuStatus and is pinned here,
/// not in a view body no test can reach
/// (docs/DECISIONS.md: menu-status-before-warnings).
struct MenuStatusTests {

    /// A healthy app on hardware that honours the declaration, with every fact
    /// overridable one at a time.
    private func status(
        style: Style = .notch,
        fallsBackToCard: Bool = false,
        accessibilityGranted: Bool = true,
        suppressionEnabled: Bool = true,
        suppressionAvailable: Bool = true,
        suspendedDomains: Set<OSDSuppressionDomain> = [],
        chainNotice: MediaKeyChainNotice = .quiet,
        brightnessTarget: BrightnessKeyTargetNotice = .quiet,
        nowPlayingActive: Bool = true,
        mediaCommandsAvailable: Bool = true,
        loginOutcome: LoginItemReconciler.Outcome = .quiet,
        loginRegistered: Bool = true
    ) -> MenuStatus {
        MenuStatus(
            style: style,
            fallsBackToCard: fallsBackToCard,
            accessibilityGranted: accessibilityGranted,
            suppressionEnabled: suppressionEnabled,
            suppressionAvailable: suppressionAvailable,
            suspendedDomains: suspendedDomains,
            chainNotice: chainNotice,
            brightnessTarget: brightnessTarget,
            nowPlayingActive: nowPlayingActive,
            mediaCommandsAvailable: mediaCommandsAvailable,
            loginOutcome: loginOutcome,
            loginRegistered: loginRegistered
        )
    }

    @Test func aHealthyAppSaysWhatItIsDoingAndWarnsAboutNothing() {
        #expect(status().rows == [.style(.notch), .replacingSystemIndicators, .opensAtLogin])
        #expect(status().warnings.isEmpty)
    }

    @Test func theStatusBlockNeverGoesEmpty() {
        // Everything off or broken: the style row still opens the menu, so the
        // anchor line never moves under the pointer.
        let broken = status(
            accessibilityGranted: false,
            suppressionEnabled: false,
            suppressionAvailable: false,
            nowPlayingActive: false,
            mediaCommandsAvailable: false,
            loginRegistered: false
        )
        #expect(broken.rows == [.style(.notch)])
    }

    @Test func aDeclarationNothingHonoursIsSaidOutLoudRightAfterItself() {
        // A Mac with no slit — the shipped default declares Notch and every panel
        // draws Card. "Style: Notch" alone would be false there. The pair is
        // adjacent on purpose: the second line only means anything read against the
        // first (docs/DECISIONS.md: rendered-style-gates-settings).
        let notchless = status(fallsBackToCard: true)
        #expect(notchless.rows.prefix(2) == [.style(.notch), .styleFallsBackToCard])
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

    @Test func aWishWithoutTheMeansIsNotStatus() {
        // The preference persists with no permission or no suppressor in the graph
        // (demo sources) and nothing engages — the row must not claim it does.
        #expect(!status(suppressionAvailable: false).rows.contains(.replacingSystemIndicators))
        #expect(!status(suppressionEnabled: false).rows.contains(.replacingSystemIndicators))
    }

    @Test func aSuspendedDomainReplacesTheClaimWithTheNews() {
        // Suppression is engaged and one channel's native indicator is back: the
        // flat claim is false for that channel, and the warning is what the user
        // needs. Domains in declared order, so the same set never reads two ways.
        let suspended = status(suspendedDomains: [.keyboardBrightness, .volume])
        #expect(!suspended.rows.contains(.replacingSystemIndicators))
        #expect(suspended.warnings == [.suppressionSuspended([.volume, .keyboardBrightness])])
    }

    @Test func theBrightnessTargetIsStatusAndNeverCollidesWithTheNeighboursRow() {
        // Correct behavior nobody can see reads as a bug, so it is said — as a fact,
        // in the status block, never a warning
        // (docs/DECISIONS.md: brightness-key-target-in-the-menu).
        #expect(status(brightnessTarget: .builtInAmongOthers).rows.contains(.brightnessBuiltInOnly))
        #expect(status(brightnessTarget: .builtInAmongOthers).warnings.isEmpty)
        #expect(status(brightnessTarget: .noBuiltInDisplay).rows.contains(.brightnessNoBuiltIn))
        #expect(!status().rows.contains(.brightnessBuiltInOnly))
        // The composition upstream stands the target down for any chain answer but
        // `.quiet`, so the two brightness rows are mutually exclusive by
        // construction — this pins that they never both appear.
        let drawing = status(chainNotice: .drawingFromBetterDisplay, brightnessTarget: .quiet)
        #expect(drawing.rows.contains(.brightnessFromBetterDisplay))
        #expect(!drawing.rows.contains(.brightnessBuiltInOnly))
        #expect(!drawing.rows.contains(.brightnessNoBuiltIn))
    }

    @Test func approvalPendingIsNotOpeningAtLogin() {
        // A non-throwing register() can park for approval: nothing opens at login
        // yet, so the row would be a promise macOS has not kept.
        let pending = status(loginOutcome: .needsApproval, loginRegistered: false)
        #expect(!pending.rows.contains(.opensAtLogin))
        #expect(pending.warnings == [.loginItemNeedsApproval])
    }

    @Test func warningsComeInAFixedOrderMostUrgentFirst() {
        // Everything wrong at once — the shape a fresh, broken install really takes.
        // Accessibility leads because without it no media key arrives at all;
        // launch-at-login trails because it is about the next launch.
        let bad = status(
            style: .card,
            accessibilityGranted: false,
            suspendedDomains: [.volume],
            chainNotice: .anotherAppAhead("Some Other App"),
            nowPlayingActive: false,
            mediaCommandsAvailable: false,
            loginOutcome: .revokedByUpdate,
            loginRegistered: false
        )
        #expect(bad.warnings == [
            .accessibilityMissing,
            .suppressionSuspended([.volume]),
            .anotherAppAhead("Some Other App"),
            .nowPlayingUnavailable,
            .mediaControlsBlocked,
            .loginItemRevoked,
        ])
        #expect(bad.rows == [.style(.card)])
    }

    @Test func onlyAWarningWithARepairOffersOne() {
        // The PAIRING itself: a retry button under the login warning would ship
        // green otherwise, since the menu's switch is compile-checked for
        // exhaustiveness and not for correctness.
        #expect(MenuStatus.Warning.accessibilityMissing.action == .grantAccessibility)
        #expect(MenuStatus.Warning.suppressionSuspended([.volume]).action == .retrySuppression)
        #expect(MenuStatus.Warning.loginItemRevoked.action == .reactivateLoginItem)
        #expect(MenuStatus.Warning.loginItemNeedsApproval.action == .openLoginItemsSettings)
        // Naming who is ahead in the tap chain is all the app can honestly do, and
        // no button revives a dead media source.
        #expect(MenuStatus.Warning.anotherAppAhead("Some Other App").action == nil)
        #expect(MenuStatus.Warning.betterDisplayAheadAndSilent.action == nil)
        #expect(MenuStatus.Warning.nowPlayingUnavailable.action == nil)
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
            loginOutcome: .revokedByUpdate,
            loginRegistered: false
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
        let plain = status(nowPlayingActive: false, mediaCommandsAvailable: false)
        #expect(plain.warnings == [.nowPlayingUnavailable, .mediaControlsBlocked])
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
        // the laptop moved the laptop, same build, same chain order. A flat "Crema
        // drives the built-in only" is true about Crema and useless to the person
        // reading it, because the screen they are looking at responds.
        //
        // So the sentence appears only where Crema is the one that writes: opted in,
        // available, and no domain suspended. Everywhere else another row speaks —
        // the neighbour's, or the suspension warning.
        for target in [BrightnessKeyTargetNotice.builtInAmongOthers, .noBuiltInDisplay] {
            #expect(status(brightnessTarget: target).rows.contains {
                $0 == .brightnessBuiltInOnly || $0 == .brightnessNoBuiltIn
            }, "\(target) should speak while Crema applies")

            for silenced in [
                status(suppressionEnabled: false, brightnessTarget: target),
                status(suppressionAvailable: false, brightnessTarget: target),
                status(suspendedDomains: [.screenBrightness], brightnessTarget: target),
            ] {
                #expect(!silenced.rows.contains {
                    $0 == .brightnessBuiltInOnly || $0 == .brightnessNoBuiltIn
                }, "\(target) must stay silent where Crema does not apply")
            }
        }
    }
}
