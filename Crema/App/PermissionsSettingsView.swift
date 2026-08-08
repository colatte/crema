import SwiftUI

/// The permissions Crema can honestly report on, in the order they matter:
/// Accessibility, without which the media-key HUDs are dead, and Automation,
/// which only the now-playing BACKUP reader uses. The two rows are deliberately
/// not styled alike — the first warns because a feature is off, the second states
/// a fact in the neutral style, because a missing Automation grant costs a backup
/// reader most installs never reach. Alarming there would send people to fix
/// something that is not broken (docs/DECISIONS.md: automation-is-fallback-only).
///
/// Neither row asks the system for anything as it renders. Accessibility is
/// mirrored by a poll started at launch; the Automation state comes from a monitor
/// this tab starts and stops, and the read behind it is the NON-prompting
/// question — the prompting one lives behind the button, where the user's click is
/// what asks for it.
///
/// Split out of SettingsView.swift because that file is at its length ceiling; the
/// other tabs still live there.
struct PermissionsSettingsView: View {
    let core: AppCore

    private var granted: Bool { core.permissionMonitor.isGranted }
    /// Nil until the first read lands: "no answer yet" is a state this row says
    /// out loud, never one it renders as a refusal.
    private var automation: AutomationPermissionState? { core.automationMonitor.state }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    // The colour lives on the GLYPH, never on the word. Tinting the
                    // whole Label put the one line people open this tab to read at
                    // roughly 2.2:1 against a light grouped row — under the 4.5:1
                    // floor for body text, and invisible in the failure it survived
                    // by looking fine in dark mode. It is also why the glyph is
                    // hidden from VoiceOver: it repeats the word beside it, and a
                    // state carried by colour alone is not a state at all.
                    Label {
                        Text(
                            granted
                                ? String(localized: "settings.permissions.granted", defaultValue: "Granted")
                                : String(localized: "settings.permissions.notGranted", defaultValue: "Not granted")
                        )
                        .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(granted ? Color.green : Color.orange)
                            .accessibilityHidden(true)
                    }
                } label: {
                    Text(String(localized: "settings.permissions.accessibility", defaultValue: "Accessibility"))
                }

                if !granted {
                    Button(String(localized: "settings.permissions.grant", defaultValue: "Grant Accessibility Access…")) {
                        core.requestAccessibilityAccess()
                    }
                }
            } header: {
                Text(String(localized: "settings.permissions.accessibility.header", defaultValue: "Required"))
            } footer: {
                Text(String(
                    localized: "settings.permissions.footer",
                    // swiftlint:disable:next line_length
                    defaultValue: "Crema needs Accessibility access to capture the media keys — for its volume and brightness indicators and to replace the system's. Without it the app still runs; it just can't react to those keys. Granting is picked up automatically, no relaunch needed."
                ))
                .settingsFootnote()
            }

            Section {
                LabeledContent {
                    // No badge at all, which is the rule and not an omission: the
                    // symbol column belongs to the permission the app REQUIRES. A
                    // glyph here ranked an optional permission alongside it, and the
                    // shapes ranked it WRONG — a refusal got a harsher mark (✗) than
                    // the required grant's warning, and the resting state of a Mac
                    // with no music app open got a question mark against a machine
                    // where nothing is wrong. Words carry it, the way the other
                    // optional integration already states "Receiving" one tab over.
                    Text(automationStatus)
                        .foregroundStyle(automation == .granted ? .primary : .secondary)
                } label: {
                    Text(String(localized: "settings.permissions.automation", defaultValue: "Automation"))
                }

                switch automation?.nextStep ?? .quiet {
                case .ask(let enabled):
                    // Visible-but-disabled instead of hidden while there is nobody
                    // to ask about (no music app open): the footer says why, and a
                    // button that vanishes reads as a path that does not exist.
                    Button(String(
                        localized: "settings.permissions.automation.request",
                        defaultValue: "Request Automation Access…"
                    )) {
                        core.requestAutomationAccess()
                    }
                    .disabled(!enabled)
                case .openSettings:
                    Button(String(
                        localized: "settings.permissions.automation.openSettings",
                        defaultValue: "Open Automation Settings…"
                    )) {
                        core.openAutomationSettings()
                    }
                case .quiet:
                    EmptyView()
                }
            } header: {
                // With the badge gone, the word is what ranks the two sections —
                // and a word survives a screenshot, greyscale and colour blindness,
                // which an orange-versus-grey ranking does not.
                Text(String(localized: "settings.permissions.automation.header", defaultValue: "Optional"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(
                        localized: "settings.permissions.automation.footer",
                        // swiftlint:disable:next line_length
                        defaultValue: "Only Crema's backup reader needs this — it asks \(musicApps) what is playing. The usual reader needs no permission, so Now Playing works either way."
                    ))
                    automationDetail
                }
                .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        // Watching is scoped to this tab, not to the app's life: each pass is a
        // blocking round trip to the consent daemon per app, and no other part of
        // the app reads the answer. Both ends are idempotent, so a duplicated or
        // missing edge costs at most one poll while Settings is open in front of
        // the user.
        .onAppear { core.watchAutomationPermission(true) }
        .onDisappear { core.watchAutomationPermission(false) }
    }

    /// The apps the backup reader scripts, from their single source, joined by
    /// the locale's own "or" list format, and NOT translated.
    ///
    /// Checked rather than assumed, because the obvious objection is that Apple
    /// localizes its own app names — `Music.app`'s `InfoPlist.loctable` really
    /// does map `pt` → "Música". Measured on a Mac with `AppleLanguages =
    /// ("pt-BR")` (2026-08-07): `FileManager.displayName` and the bundle's
    /// `localizedInfoDictionary` both return **"Music"**, which is also what the
    /// Dock shows. The table has `pt` and `pt_PT` and no `pt-BR`, and macOS does
    /// not fall back for this.
    ///
    /// So resolving the installed bundle's name would cost a LaunchServices
    /// lookup on every body pass and produce the same three letters. If a
    /// future macOS starts showing "Música" here, that lookup is the fix and
    /// this paragraph is the reason it was not done sooner.
    private var musicApps: String {
        JXAPlayerScript.players.map(\.name).formatted(.list(type: .or))
    }

    /// One short sentence per state, and never the word "denied" for an absence of
    /// an answer. `targetNotRunning` gets its own words rather than "Unknown": it
    /// is the resting state of a machine with no music app open (macOS answers
    /// `procNotFound` and nothing else), so it is the line most users will read,
    /// and it has a different button below it than `unknown` does.
    private var automationStatus: String {
        switch automation {
        case nil: String(localized: "settings.permissions.checking", defaultValue: "Checking…")
        case .granted: String(localized: "settings.permissions.granted", defaultValue: "Granted")
        case .denied: String(localized: "settings.permissions.notGranted", defaultValue: "Not granted")
        case .undecided: String(localized: "settings.permissions.notRequested", defaultValue: "Not requested yet")
        case .targetNotRunning:
            String(localized: "settings.permissions.automation.noAppOpen", defaultValue: "No music app open")
        case .unknown: String(localized: "settings.permissions.unknown", defaultValue: "Unknown")
        }
    }

    /// The one sentence that changes with the state — silent where the status words
    /// already say everything, and never in the warning colour.
    @ViewBuilder
    private var automationDetail: some View {
        switch automation {
        case .denied:
            Text(String(
                localized: "settings.permissions.automation.denied",
                defaultValue: "Turned off in System Settings. Now Playing still works through the usual reader."
            ))
        case .undecided:
            Text(String(
                localized: "settings.permissions.automation.undecided",
                defaultValue: "macOS hasn't asked you about this yet. Request it and macOS shows its own dialog."
            ))
        case .targetNotRunning:
            Text(String(
                localized: "settings.permissions.automation.noTarget",
                defaultValue: "macOS only answers about an app that is open — open \(musicApps) to check."
            ))
        case .unknown:
            Text(String(
                localized: "settings.permissions.automation.unknown",
                defaultValue: "macOS didn't answer. Crema checks again while this tab is open."
            ))
        case nil, .granted:
            EmptyView()
        }
    }
}
