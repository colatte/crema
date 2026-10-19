import SwiftUI

struct SystemHUDSettingsView: View {
    let core: AppCore
    @AppStorage(Preferences.suppressesNativeOSDKey) private var suppress = false

    // Written out rather than left to the memberwise initializer, which inherits
    // the private access of the property above and so cannot be called from the
    // window that builds this tab.
    init(core: AppCore) {
        self.core = core
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $suppress) {
                    Text(String(localized: "settings.hud.suppress", defaultValue: "Replace the system indicators"))
                }
                .disabled(!core.suppressionAvailable)
                .onChange(of: suppress) { _, new in core.setNativeOSDSuppression(new) }

                if !core.permissionMonitor.isGranted {
                    // The fix belongs under the line that explains the problem —
                    // the house rule for the menu, applied here. Without it the
                    // person for whom this whole tab is inert reads the longest
                    // sentence in the window and is sent to another tab to find a
                    // button that already exists. Same button, same key.
                    Button(String(
                        localized: "settings.permissions.grant",
                        defaultValue: "Grant Accessibility Access…"
                    )) {
                        core.requestAccessibilityAccess()
                    }
                }
            } footer: {
                SuppressionNotes(core: core)
                    .settingsFootnote()
            }

            // Explaining the integration is always worth doing — that is what a
            // settings pane is for, and someone seeing two bars or none has nowhere
            // else to look. What is NOT always said is that it is WORKING: that
            // sentence appears only once a payload has actually arrived, because a
            // neighbour being installed, or even running, proves nothing about
            // whether its OSD integration is switched on
            // (docs/DECISIONS.md: betterdisplay-osd-source). The claim is
            // observable, so it flips with this window open: the person reading
            // this line is usually the one switching that setting on in the other
            // app, and an answer that only arrives on the next open reads as no.
            // The negative names the channel and not a fault — the common case is a
            // Mac with no BetterDisplay on it, where nothing is wrong and there is
            // nothing to switch on.
            Section {
                LabeledContent {
                    Text(core.betterDisplayIsReporting
                        ? String(
                            localized: "settings.hud.betterDisplay.receiving",
                            defaultValue: "Receiving"
                        )
                        : String(
                            localized: "settings.hud.betterDisplay.notReceiving",
                            defaultValue: "No signal"
                        ))
                        .foregroundStyle(core.betterDisplayIsReporting ? .primary : .secondary)
                } label: {
                    Text(String(
                        localized: "settings.hud.betterDisplay",
                        defaultValue: "BetterDisplay integration"
                    ))
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(
                        localized: "settings.hud.betterDisplay.footer",
                        // swiftlint:disable:next line_length - one line, so check-catalog.py reads the defaultValue
                        defaultValue: "With BetterDisplay 4.2.1 or newer, Crema can show the brightness indicator for an external display. Nothing to enable here."
                    ))
                    handoffNote
                }
                .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }

    /// What Crema does to BetterDisplay's own switches, or, when it could not, what
    /// the person does by hand. Switches are named in the neighbour's own words,
    /// because its window is where they are found.
    private var handoffNote: Text {
        switch core.neighbourOSDHandoff?.status {
        case .unanswered:
            // Silence is the request channel being off, the one switch Crema
            // cannot reach from here; with it on, the rest is done for them.
            Text(String(
                localized: "settings.hud.betterDisplay.unanswered",
                // swiftlint:disable:next line_length - one line, so check-catalog.py reads the defaultValue
                defaultValue: "BetterDisplay isn’t responding to Crema. In BetterDisplay, go to Settings → Application → Integration and turn on “Enable CLI access and notification based integration”."
            ))
        case .refused:
            // It answers and says no, so the setup is the person's: the two
            // switches Crema would have set, the second being what stops two bars
            // from appearing at once.
            Text(String(
                localized: "settings.hud.betterDisplay.howTo",
                // swiftlint:disable:next line_length - one line, so check-catalog.py reads the defaultValue
                defaultValue: "In BetterDisplay, go to Settings → Application → Integration and turn on “Dispatch OSD notifications”. Then, in Settings → Keyboard → OSD, turn off “Show brightness, volume, mute OSD” so only Crema’s indicator appears."
            ))
        case .idle, .inPlace, nil:
            Text(String(
                localized: "settings.hud.betterDisplay.handoff",
                // swiftlint:disable:next line_length - one line, so check-catalog.py reads the defaultValue
                defaultValue: "While Crema replaces the system indicators, it sets up BetterDisplay for you: it turns on “Dispatch OSD notifications” and turns off BetterDisplay’s own indicator. When you quit Crema, everything goes back to how it was."
            ))
        }
    }
}
