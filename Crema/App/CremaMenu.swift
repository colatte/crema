import AppKit
import SwiftUI

/// Everything the menu has to SAY, in the sections it says it in: the switch and
/// the style submenu with the facts about them written under each, then what needs
/// attention, then the media. Which sections exist, in what order, and behind which
/// gate is decided in one pure place (MenuStatus) rather than in the shape of this
/// body; the app's own actions come after it, unconditional, in the scene body.
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
/// No glyphs in any line below. "⚠️" carries the meaning the line has to carry
/// anyway (and VoiceOver reads it mid-sentence as noise); "✓" collides with the
/// platform's own vocabulary — a checkmark in an NSMenu means a CHECKED item, which
/// is why the two facts that ARE a checked item (the replacement, the declared
/// style) ship as a Toggle and a Picker. Separators come from the sections and
/// never from a `Divider`: next to a section's own, a `Divider` doubles it
/// (measured, scripts/probes/menu-sections-and-subtitles.swift).
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

    var body: some View {
        let status = core.menuStatus(
            style: Preferences.declaredStyle(fromRawValue: declaredStyle),
            suppressionEnabled: suppresses
        )
        ForEach(status.blocks, id: \.self) { block in
            self.block(block, in: status)
        }
    }

    @ViewBuilder
    private func block(_ block: MenuStatus.Block, in status: MenuStatus) -> some View {
        switch block {
        case .controls:
            // Titled with the Indicators tab's own name: the section is that tab's
            // two controls, and one concept keeps one name across the app.
            Section(String(localized: "menu.section.indicators", defaultValue: "Indicators")) {
                replacementSwitch(note: status.note(on: .replacementSwitch).map(text(for:)))
                StyleMenu(core: core, note: status.note(on: .styleMenu).map(text(for:)))
            }
        case .warnings:
            // Untitled: each warning names itself, and a heading over them would be
            // a second alarm on top of the first.
            Section {
                // Each case appears at most once, so the offset is a stable identity.
                ForEach(Array(status.warnings.enumerated()), id: \.offset) { _, warning in
                    warningItem(warning)
                }
            }
        case .media:
            NowPlayingMenuSection(coordinator: core.coordinator)
        }
    }

    /// The app's headline feature is opt-in and ships OFF, and a status line is a
    /// fact — so without this switch a fresh install's menu would never name the
    /// feature at all. A real Toggle is also the one place a checkmark belongs in an
    /// NSMenu, and every AppKit status menu the glyph rule cites (Wi-Fi, Bluetooth,
    /// Sound) leads with its switch. The write stays behind a click, so the
    /// read-only contract on this body holds. Disabled on the one gate every
    /// switch for the feature reads (`AppCore.suppressionAvailable`), whose two
    /// values the status block already receives — no new observation enters this
    /// expensive body for it.
    @ViewBuilder
    private func replacementSwitch(note: String?) -> some View {
        let isOn = Binding(get: { suppresses }, set: { core.setNativeOSDSuppression($0) })
        let title = String(localized: "settings.hud.suppress", defaultValue: "Replace the system indicators")
        if MenuItemNote.isSubtitle {
            Toggle(isOn: isOn) {
                Text(title)
                if let note { Text(note) }
            }
            .disabled(!core.suppressionAvailable)
        } else {
            Toggle(isOn: isOn) { Text(title) }
                .disabled(!core.suppressionAvailable)
            if let note { Text(note) }
        }
    }

    /// One warning, one item. With a repair, the repair IS the item and the fact is
    /// its subtitle — the button says what to do, the line under it says why, and no
    /// sentence sits apart from the button that answers it. Without one, the fact is
    /// a disabled item and what it costs is its subtitle. Which of the two comes
    /// from the warning's own `item`, so a fact and its repair cannot drift apart.
    @ViewBuilder
    private func warningItem(_ warning: MenuStatus.Warning) -> some View {
        switch warning.item {
        case .repair(let action):
            MenuItemNote.item(title(for: action), note: note(for: warning)) { perform(action) }
        case .fact(let fact):
            MenuItemNote.item(text(for: fact), note: note(for: warning), action: nil)
        }
    }

    /// A fact written under its control, so a fragment rather than a sentence: no
    /// final period, the control above it is the subject.
    private func text(for row: MenuStatus.Row) -> String {
        switch row {
        case .styleFallsBackToCard:
            // The words the per-display rows in Settings use for the same fact:
            // what is drawn, then why.
            String(
                localized: "menu.status.styleFallsBack",
                defaultValue: "Using Card, since no display has a notch"
            )
        case .brightnessFromBetterDisplay:
            String(
                localized: "menu.betterDisplay.drawing",
                defaultValue: "External display brightness comes from BetterDisplay"
            )
        case .brightnessNoBuiltIn:
            // Under the switch, Crema is the subject, never "the brightness keys": a
            // line about the KEY would assert what macOS and other apps do with it
            // (docs/DECISIONS.md: brightness-key-target-in-the-menu).
            String(
                localized: "menu.status.brightnessNoBuiltIn",
                defaultValue: "Without the built-in display, macOS shows its own brightness indicator"
            )
        }
    }

    /// The title of a warning that has no repair to be titled by.
    private func text(for fact: MenuStatus.Fact) -> String {
        switch fact {
        case .betterDisplayAheadAndSilent:
            String(localized: "menu.betterDisplay.silent", defaultValue: "BetterDisplay receives the brightness keys")
        case .anotherAppAhead(let app):
            // Stated as the fact it is — a position in the chain, not a
            // malfunction — because from inside the app the symptom is
            // indistinguishable from a broken tap, and no user can diagnose it
            // unaided (docs/DECISIONS.md: media-key-chain-contention).
            String(localized: "menu.mediaKeysPrecededBy", defaultValue: "\(app) gets the volume and brightness keys before Crema")
        case .mediaControlsBlocked:
            String(
                localized: "menu.mediaControlsBlocked",
                defaultValue: "The music app didn’t respond to the last command"
            )
        }
    }

    /// The line under a warning's item: the fact a repair answers, or what a fact
    /// with no repair costs. Every one fits the menu's ~72-character line
    /// (docs/DECISIONS.md: menu-status-before-warnings); the one with a variable
    /// part is measured at its widest on `suspendedText`.
    private func note(for warning: MenuStatus.Warning) -> String {
        switch warning {
        case .accessibilityMissing:
            String(
                localized: "menu.accessibilityWarning",
                defaultValue: "Without it, Crema can’t react to the volume or brightness keys"
            )
        case .suppressionSuspended(let domains):
            suspendedText(domains)
        case .betterDisplayAheadAndSilent:
            // The neighbour's setting in its own words, so the reader finds it there.
            String(
                localized: "menu.betterDisplay.silent.detail",
                defaultValue: "Turn on “OSD notification” in BetterDisplay to see Crema’s indicator"
            )
        case .anotherAppAhead:
            String(
                localized: "menu.mediaKeysPrecededBy.detail",
                defaultValue: "So some of Crema’s indicators may not appear"
            )
        case .nowPlayingUnavailable:
            // States the requirement, never a verdict: nothing here knows whether
            // consent is the reason, and reading that state would put a poll behind a
            // body whose rebuild costs the tap-chain read. The item above it is the
            // walk to the tab where it is granted.
            String(
                localized: "menu.nowPlayingUnavailable",
                defaultValue: "Crema can’t see what’s playing — allow Automation to ask the music app"
            )
        case .mediaControlsBlocked:
            String(
                localized: "menu.mediaControlsBlocked.detail",
                defaultValue: "It isn’t accepting controls right now"
            )
        // Both name the control in its own words, quoted: the switch is labelled
        // "Open Crema at login" in General, and a warning that renames the thing it
        // is about sends the reader looking for a setting that is not there.
        case .loginItemRevoked:
            String(
                localized: "menu.loginItem.revoked",
                defaultValue: "“Open Crema at login” was turned off by the update"
            )
        case .loginItemNeedsApproval:
            String(
                localized: "menu.loginItem.needsApproval",
                defaultValue: "“Open Crema at login” is waiting for your approval"
            )
        }
    }

    /// The line naming the domains whose native indicator is back. Joined with a
    /// locale-aware list format (", " vs " and " vs " e "); the ORDER comes from the
    /// model, which sorts by the enum's declaration, so the same set never reads two
    /// different ways.
    ///
    /// The list is a closed set of three, so the widest line is measurable — all
    /// three joined, 70 characters in English and 68 in Portuguese, under the
    /// ceiling `MenuLineWidthTests` holds every menu line to
    /// (docs/DECISIONS.md: menu-status-before-warnings).
    private func suspendedText(_ domains: [OSDSuppressionDomain]) -> String {
        let names = domains.map(localizedDomainName).formatted(.list(type: .and))
        return String(localized: "menu.osdSuspended.warning", defaultValue: "Shown by macOS again: \(names)")
    }

    private func localizedDomainName(_ domain: OSDSuppressionDomain) -> String {
        switch domain {
        case .volume:
            String(localized: "osd.domain.volume", defaultValue: "volume")
        case .screenBrightness:
            String(localized: "osd.domain.screenBrightness", defaultValue: "screen brightness")
        case .keyboardBrightness:
            String(localized: "osd.domain.keyboardBrightness", defaultValue: "keyboard brightness")
        }
    }

    private func title(for action: MenuStatus.Action) -> String {
        switch action {
        case .grantAccessibility:
            String(localized: "menu.grantAccessibility", defaultValue: "Grant Accessibility Access…")
        case .retrySuppression:
            String(localized: "menu.osdSuspended.retry", defaultValue: "Try Again")
        case .openPermissionsTab:
            String(localized: "menu.openPermissions", defaultValue: "Open Permissions…")
        case .reactivateLoginItem:
            String(localized: "menu.loginItem.reactivate", defaultValue: "Turn it back on")
        case .openLoginItemsSettings:
            String(localized: "menu.loginItem.openSettings", defaultValue: "Open Login Items Settings…")
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
    /// button under the sentence that explains the problem. Brought forward first,
    /// or the window opens behind whatever is frontmost (`AppCore.bringForward`).
    private func openPermissionsTab() {
        core.settingsNavigation.request(.permissions)
        core.bringForward()
        openSettings()
    }
}
