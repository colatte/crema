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
            // Mac with no BetterDisplay on it, where nothing is wrong and nothing on
            // this side turns anything on.
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
                    // Named as the two switches they are, in the neighbour's own
                    // words, because this is the one place a user can act on it —
                    // and the second is what stops two bars from appearing at once.
                    Text(String(
                        localized: "settings.hud.betterDisplay.howTo",
                        // swiftlint:disable:next line_length - one line, so check-catalog.py reads the defaultValue
                        defaultValue: "In BetterDisplay, turn on Settings → Application → Integration → OSD notification, and turn its own OSD off in that same panel."
                    ))
                }
                .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }
}
