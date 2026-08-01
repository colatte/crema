import AppKit
import SwiftUI

/// Everything the menu has to SAY, in the four blocks it says it in: the switch and
/// the style submenu, then what Crema is doing, then what needs attention, then the
/// media. Which blocks exist, in what order, and behind which gate is decided in
/// one pure place (MenuStatus) rather than in the shape of this body; what is left
/// below the closing separator is the app's own actions, which are unconditional.
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
/// What is deliberately NOT read here: the track playing. It would have to come
/// from `coordinator.nowPlaying`, whose position advances once a second, so this
/// block — and every reading behind it — would rebuild once a second for a menu
/// nobody is looking at. The media block instantiates NowPlayingMenuSection, which
/// reads its own mirrors in its own body, so a track change repaints that view and
/// leaves the readings here alone (docs/DECISIONS.md: menu-reads-mirrors).
///
/// No glyphs in any sentence below, in either direction. "⚠️" carried the meaning
/// the sentence has to carry anyway (and VoiceOver reads it mid-sentence as noise),
/// and stacked into a wall whenever two conditions fired at once; "✓" collided with
/// the platform's own vocabulary — a checkmark in an NSMenu means a CHECKED item,
/// which is why the two facts that ARE a checked item (the replacement, the declared
/// style) ship as a Toggle and a Picker instead of as sentences. AppKit's own status
/// menus state informational rows as plain disabled sentences.
/// (docs/DECISIONS.md: menu-status-before-warnings)
@MainActor
struct CremaMenu: View {
    let core: AppCore
    @Environment(\.openSettings) private var openSettings

    /// Observed rather than read through Preferences: the Toggle below SHOWS this
    /// value, and an unobserved read would keep showing the old one after the
    /// Settings switch flipped, until something unrelated rebuilt this body.
    @AppStorage(Preferences.suppressesNativeOSDKey) private var suppresses = false
    /// The declaration the fallback row is derived from — `menuStatus` answers "no
    /// connected display honours Notch" against it — read through Preferences' own
    /// resolver, where the shipped default and the degradation of a rawValue a
    /// future version retires are stated once. Observed for the same reason as
    /// above: the row would go stale the moment the Style submenu declared a new one.
    @AppStorage(Preferences.declaredStyleKey) private var declaredStyle = Preferences.defaultDeclaredStyle.rawValue

    /// Whether the app can replace anything at all: without the Accessibility
    /// grant there is no tap, and without a suppressor there is nothing to engage.
    /// The same two values the Settings toggle gates on, and the same two the
    /// status block already receives — no new observation enters this expensive
    /// body for the switch.
    private var canSuppress: Bool {
        core.permissionMonitor.isGranted && core.osdSuppressor != nil
    }

    var body: some View {
        let status = core.menuStatus(
            style: Preferences.declaredStyle(fromRawValue: declaredStyle),
            suppressionEnabled: suppresses
        )
        // The index is the identity here, because the separator rule is stated over
        // it: each block appears at most once, and which one leads depends on what
        // the app has to say.
        ForEach(Array(status.blocks.enumerated()), id: \.offset) { index, block in
            if status.separatesBlock(at: index) { Divider() }
            self.block(block, in: status)
        }
        // Closes the group against the app's own actions below. They are not blocks:
        // nothing gates them, and one of them exists only in Release.
        Divider()
    }

    @ViewBuilder
    private func block(_ block: MenuStatus.Block, in status: MenuStatus) -> some View {
        switch block {
        case .controls:
            // The app's headline feature is opt-in and ships OFF, and a status row is
            // a fact — the block below can only speak about the replacement once it
            // is already in effect, so without this switch a fresh install's menu
            // would never name the feature at all. A real Toggle is also the one
            // place a checkmark belongs in an NSMenu — the rule above bans the glyph
            // INSIDE a sentence precisely because a checked item is what it means
            // here, and every AppKit status menu that rule cites (Wi-Fi, Bluetooth,
            // Sound) leads with its switch. The write stays behind a click, so the
            // read-only contract on this body holds.
            Toggle(isOn: Binding(get: { suppresses }, set: { core.setNativeOSDSuppression($0) })) {
                Text(String(localized: "settings.hud.suppress", defaultValue: "Replace the system indicators"))
            }
            .disabled(!canSuppress)
            StyleMenu(core: core)
        case .status:
            // Each case appears at most once, so the case is its own stable identity.
            ForEach(status.rows, id: \.self) { row in
                sentence(text(for: row))
            }
        case .warnings:
            ForEach(Array(status.warnings.enumerated()), id: \.offset) { index, warning in
                if status.separatesWarning(at: index) { Divider() }
                sentence(text(for: warning))
                if let advice = warning.advice {
                    sentence(text(for: advice))
                }
                // Every button here comes from the warning's own action, so a fact
                // and its repair cannot drift apart: a button hardcoded beside one
                // warning is how a repair ends up under a sentence it does not fix,
                // with the exhaustive switch in MenuStatus still compiling.
                if let action = warning.action {
                    Button(title(for: action)) { perform(action) }
                }
            }
        case .media:
            NowPlayingMenuSection(coordinator: core.coordinator)
        }
    }

    /// One menu item per line of a sentence, broken where the catalog breaks it.
    ///
    /// An NSMenu is exactly as wide as its widest item, so a single 116-character
    /// status row opened this menu at roughly 1500 pt (measured in the field,
    /// 2026-07-31; that row has since left the block, the ceiling it bought governs
    /// every line here) — the ceiling is about 72 characters a line, and the break
    /// points live beside the text in the catalog, where each translation breaks at
    /// its own clause. Stacked plain items, never a centred paragraph: informational rows are
    /// leading-aligned everywhere else in this menu and in the system's own
    /// (docs/DECISIONS.md: menu-status-before-warnings).
    @ViewBuilder
    private func sentence(_ text: String) -> some View {
        // The index is the identity, as in the block list above: two lines of one
        // sentence can read identically, and the whole list is replaced when the
        // sentence changes.
        ForEach(Array(text.split(separator: "\n").enumerated()), id: \.offset) { _, line in
            Text(String(line))
        }
    }

    private func text(for row: MenuStatus.Row) -> String {
        switch row {
        case .styleFallsBackToCard:
            // The same sentence the Settings footer uses for the same fact, word for
            // word: one name per concept, in each language.
            String(
                localized: "menu.status.styleFallsBack",
                defaultValue: "No connected display has a notch, so every one is drawing Card."
            )
        case .brightnessFromBetterDisplay:
            String(
                localized: "menu.betterDisplay.drawing",
                defaultValue: "The screen brightness indicator comes from BetterDisplay."
            )
        case .brightnessNoBuiltIn:
            // Crema is the subject, never "the brightness keys": a sentence about
            // the KEY would assert what macOS and other apps do with it
            // (docs/DECISIONS.md: brightness-key-target-in-the-menu).
            String(
                localized: "menu.status.brightnessNoBuiltIn",
                defaultValue: "Crema can't control screen brightness —\nit works only with the built-in display, and none is in use."
            )
        }
    }

    private func text(for warning: MenuStatus.Warning) -> String {
        switch warning {
        case .accessibilityMissing:
            String(
                localized: "menu.accessibilityWarning",
                defaultValue: "Accessibility access is missing —\nCrema can't react to the volume or brightness keys."
            )
        case .suppressionSuspended(let domains):
            suspendedText(domains)
        case .betterDisplayAheadAndSilent:
            String(
                localized: "menu.betterDisplay.silent",
                defaultValue: "BetterDisplay receives the brightness keys.\nTurn on its OSD notification integration and\nCrema can show the indicator."
            )
        case .anotherAppAhead(let app):
            // Stated as the fact it is — a position in the chain, not a
            // malfunction — because from inside the app the symptom is
            // indistinguishable from a broken tap, and no user can diagnose it
            // unaided (docs/DECISIONS.md: media-key-chain-contention).
            String(
                localized: "menu.mediaKeysPrecededBy",
                defaultValue: "\(app) receives the media keys before Crema —\nsome of Crema's indicators may not appear."
            )
        case .nowPlayingUnavailable:
            String(
                localized: "menu.nowPlayingUnavailable",
                defaultValue: "Now Playing is unavailable —\nno media source is reporting."
            )
        case .mediaControlsBlocked:
            String(
                localized: "menu.mediaControlsBlocked",
                defaultValue: "The last playback command didn't get through —\nthe player stays view-only."
            )
        case .loginItemRevoked:
            String(
                localized: "menu.loginItem.revoked",
                defaultValue: "Open at login was turned off\nbecause the app changed since you enabled it."
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
    /// tap-chain read. It stops AT the requirement and no longer names the tab —
    /// the button right under it is the walk there.
    private func text(for advice: MenuStatus.Advice) -> String {
        switch advice {
        case .automationForBackupReader:
            String(
                localized: "menu.nowPlayingUnavailable.fallbackHint",
                defaultValue: "Crema's backup reader needs Automation access."
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
            defaultValue: "The system indicator is back for \(names) —\nCrema couldn't apply the change."
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
        case .openPermissionsTab:
            String(localized: "menu.openPermissions", defaultValue: "Open Permissions…")
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
        case .openPermissionsTab: openPermissionsTab()
        case .reactivateLoginItem: core.reactivateLoginItem()
        case .openLoginItemsSettings: core.openLoginItemsSettings()
        }
    }

    /// Opens the window ON the tab that carries the fix rather than naming that tab
    /// in a sentence — the same move the Indicators tab makes by putting the grant
    /// button under the sentence that explains the problem. The activation is what
    /// an accessory app needs for the window not to open behind whatever is
    /// frontmost (SettingsMenuButton documents the same requirement).
    private func openPermissionsTab() {
        core.settingsNavigation.request(.permissions)
        NSApp.activate()
        openSettings()
    }
}
