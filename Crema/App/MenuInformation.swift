import SwiftUI

/// The menu's information block: what Crema is doing, then what needs attention,
/// closed by the separator that divides both from the actions below.
///
/// A view of its own for two reasons: it owns the OBSERVED preference reads the
/// status needs (@AppStorage below), so a Settings toggle rebuilds this block and
/// not the whole scene; and the App's body stays the scene, where the Release-only
/// updater item lives. Same shape DemoMenu already ships in this menu.
///
/// READ-ONLY, as a contract and not a habit: this body is re-evaluated whenever
/// SwiftUI invalidates it — which is NOT the same as the user opening the menu —
/// so any side effect here would be domain mutation driven by rendering. The
/// readings behind `menuStatus` that live outside this process are documented
/// read-only where they are defined, and the expensive one collapses a burst of
/// rebuilds into a single reading, because each one resets the latency counters of
/// every tap in the system (MediaKeyChainNotice.Cache).
///
/// What is deliberately NOT here: the track playing. It would have to be read from
/// `coordinator.nowPlaying`, whose position advances once a second, so this block —
/// and every reading behind it — would rebuild once a second for a menu nobody is
/// looking at. It lives in NowPlayingMenuSection, off its own mirrors
/// (docs/DECISIONS.md: menu-reads-mirrors).
///
/// No glyphs in any sentence below, in either direction. "⚠️" carried the meaning
/// the sentence has to carry anyway (and VoiceOver reads it mid-sentence as noise),
/// and stacked into a wall whenever two conditions fired at once; "✓" collided with
/// the platform's own vocabulary — a checkmark in an NSMenu means a CHECKED item,
/// so a title starting with one reads as a toggle that is on. AppKit's own status
/// menus state informational rows as plain disabled sentences.
/// (docs/DECISIONS.md: menu-status-before-warnings)
@MainActor
struct MenuInformation: View {
    let core: AppCore

    /// Observed rather than read through Preferences: the row below asserts the
    /// feature is in effect, and an unobserved read would keep asserting it after
    /// the Settings toggle flipped, until something unrelated rebuilt this body.
    @AppStorage(Preferences.suppressesNativeOSDKey) private var suppresses = false
    /// The style comes from the key the Settings picker declares into, for the same
    /// reason, and through Preferences' own resolver — the shipped default and the
    /// degradation of a rawValue a future version retires are stated once, there.
    @AppStorage(Preferences.declaredStyleKey) private var declaredStyle = Preferences.defaultDeclaredStyle.rawValue

    var body: some View {
        let status = core.menuStatus(
            style: Preferences.declaredStyle(fromRawValue: declaredStyle),
            suppressionEnabled: suppresses
        )
        // Each case appears at most once, so the case is its own stable identity.
        ForEach(status.rows, id: \.self) { row in
            Text(text(for: row))
        }
        if !status.warnings.isEmpty {
            Divider()
            ForEach(Array(status.warnings.enumerated()), id: \.offset) { index, warning in
                if status.separatesWarning(at: index) { Divider() }
                Text(text(for: warning))
                if let advice = warning.advice {
                    Text(text(for: advice))
                }
                if let action = warning.action {
                    Button(title(for: action)) { perform(action) }
                }
            }
        }
        Divider()
    }

    private func text(for row: MenuStatus.Row) -> String {
        switch row {
        case .style(let style):
            String(localized: "menu.status.style", defaultValue: "Style: \(style.displayName)")
        case .styleFallsBackToCard:
            // The same sentence the Settings footer uses for the same fact, word for
            // word: one name per concept, in each language.
            String(
                localized: "menu.status.styleFallsBack",
                defaultValue: "No connected display has a notch, so every one is drawing Card."
            )
        case .replacingSystemIndicators:
            String(
                localized: "menu.status.replacingIndicators",
                defaultValue: "Replacing the system volume and brightness indicators."
            )
        case .brightnessFromBetterDisplay:
            String(
                localized: "menu.betterDisplay.drawing",
                defaultValue: "The screen brightness indicator comes from BetterDisplay."
            )
        case .brightnessFollowsPointer:
            // Crema is the subject, never "the brightness keys": a sentence about
            // the KEY would assert what macOS and other apps do with it
            // (docs/DECISIONS.md: brightness-key-target-in-the-menu). And the second
            // clause stops at "left to the system" — this row appears only where no
            // neighbour is ahead or reporting, so promising that the other display
            // gets adjusted would be the false half of a true sentence.
            String(
                localized: "menu.status.brightnessFollowsPointer",
                defaultValue: "Crema adjusts the built-in display while the pointer is on it — on any other display, the key is left to the system."
            )
        case .brightnessNoBuiltIn:
            String(
                localized: "menu.status.brightnessNoBuiltIn",
                defaultValue: "Crema can't control screen brightness — it works only with the built-in display, and none is in use."
            )
        case .opensAtLogin:
            String(localized: "menu.status.opensAtLogin", defaultValue: "Crema opens at login.")
        }
    }

    private func text(for warning: MenuStatus.Warning) -> String {
        switch warning {
        case .accessibilityMissing:
            String(
                localized: "menu.accessibilityWarning",
                defaultValue: "Accessibility access is missing — Crema can't react to the volume or brightness keys."
            )
        case .suppressionSuspended(let domains):
            suspendedText(domains)
        case .betterDisplayAheadAndSilent:
            String(
                localized: "menu.betterDisplay.silent",
                defaultValue: "BetterDisplay receives the brightness keys. Turn on its OSD notification integration and Crema can show the indicator."
            )
        case .anotherAppAhead(let app):
            // Stated as the fact it is — a position in the chain, not a
            // malfunction — because from inside the app the symptom is
            // indistinguishable from a broken tap, and no user can diagnose it
            // unaided (docs/DECISIONS.md: media-key-chain-contention).
            String(
                localized: "menu.mediaKeysPrecededBy",
                defaultValue: "\(app) receives the media keys before Crema — some of Crema's indicators may not appear."
            )
        case .nowPlayingUnavailable:
            String(
                localized: "menu.nowPlayingUnavailable",
                defaultValue: "Now Playing is unavailable — no media source is reporting."
            )
        case .mediaControlsBlocked:
            String(
                localized: "menu.mediaControlsBlocked",
                defaultValue: "The last playback command didn't get through — the player stays view-only."
            )
        case .loginItemRevoked:
            String(
                localized: "menu.loginItem.revoked",
                defaultValue: "Open at login was turned off because the app changed since you enabled it."
            )
        case .loginItemNeedsApproval:
            String(
                localized: "menu.loginItem.needsApproval",
                defaultValue: "Open at login is waiting for your approval."
            )
        }
    }

    /// The trail out of the one dead end a user can act on. States the requirement,
    /// never a verdict: nothing here knows whether consent is the reason, and
    /// reading that state would put a poll behind a body whose rebuild costs the
    /// tap-chain read.
    private func text(for advice: MenuStatus.Advice) -> String {
        switch advice {
        case .automationForBackupReader:
            String(
                localized: "menu.nowPlayingUnavailable.fallbackHint",
                defaultValue: "Crema's backup reader needs Automation access — see the Permissions tab"
            )
        }
    }

    /// The sentence naming the domains whose native indicator is back. Joined with
    /// a locale-aware list format (", " vs " and " vs " e "); the ORDER comes from
    /// the model, which sorts by the enum's declaration, so the same set never reads
    /// two different ways.
    private func suspendedText(_ domains: [OSDSuppressionDomain]) -> String {
        let names = domains.map(localizedDomainName).formatted(.list(type: .and))
        return String(
            localized: "menu.osdSuspended.warning",
            defaultValue: "The system indicator is back for \(names) — Crema couldn't apply the change."
        )
    }

    private func localizedDomainName(_ domain: OSDSuppressionDomain) -> String {
        switch domain {
        case .volume:
            String(localized: "osd.domain.volume", defaultValue: "Volume")
        case .screenBrightness:
            String(localized: "osd.domain.screenBrightness", defaultValue: "Screen brightness")
        case .keyboardBrightness:
            String(localized: "osd.domain.keyboardBrightness", defaultValue: "Keyboard brightness")
        }
    }

    private func title(for action: MenuStatus.Action) -> String {
        switch action {
        case .grantAccessibility:
            String(localized: "menu.grantAccessibility", defaultValue: "Grant Accessibility Access…")
        case .retrySuppression:
            String(localized: "menu.osdSuspended.retry", defaultValue: "Try to reactivate now")
        case .reactivateLoginItem:
            String(localized: "menu.loginItem.reactivate", defaultValue: "Turn it back on")
        case .openLoginItemsSettings:
            String(localized: "menu.loginItem.openSettings", defaultValue: "Open Login Items settings…")
        }
    }

    /// The only writes this view makes, every one of them behind a click — the body
    /// itself stays read-only.
    private func perform(_ action: MenuStatus.Action) {
        switch action {
        case .grantAccessibility: core.presentAccessibilityOnboarding()
        case .retrySuppression: core.retryOSDSuppression()
        case .reactivateLoginItem: core.reactivateLoginItem()
        case .openLoginItemsSettings: core.openLoginItemsSettings()
        }
    }
}
