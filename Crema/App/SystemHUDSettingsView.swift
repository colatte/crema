import SwiftUI

struct SystemHUDSettingsView: View {
    let core: AppCore
    @AppStorage(Preferences.suppressesNativeOSDKey) private var suppress = false

    private var canSuppress: Bool {
        core.permissionMonitor.isGranted && core.osdSuppressor != nil
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $suppress) {
                    Text(String(localized: "settings.hud.suppress", defaultValue: "Replace the system indicators"))
                }
                .disabled(!canSuppress)
                .onChange(of: suppress) { _, new in core.setNativeOSDSuppression(new) }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(
                        localized: "settings.hud.suppress.footer",
                        defaultValue: "Hides the built-in volume and brightness HUDs and shows Crema's instead."
                    ))
                    // The indicator-style picker lives in General, beside the
                    // Style picker it depends on — this line is the trail for
                    // whoever comes to the HUD tab looking for it.
                    Text(String(
                        localized: "settings.hud.appearanceHint",
                        defaultValue: "The indicator's appearance is set in the General tab."
                    ))
                    if !canSuppress {
                        Text(String(
                            localized: "settings.hud.suppress.needsPermission",
                            defaultValue: "Requires Accessibility access — grant it in the Permissions tab."
                        ))
                        .foregroundStyle(.orange)
                    }
                }
                .settingsFootnote()
            }

            // Explaining the integration is always worth doing — that is what a
            // settings pane is for, and someone seeing two bars or none has nowhere
            // else to look. What is NOT always said is that it is WORKING: that
            // sentence appears only once a payload has actually arrived, because a
            // neighbour being installed, or even running, proves nothing about
            // whether its OSD integration is switched on
            // (docs/DECISIONS.md: betterdisplay-osd-source).
            Section {
                LabeledContent {
                    Text(core.betterDisplayIsReporting
                        ? String(
                            localized: "settings.hud.betterDisplay.receiving",
                            defaultValue: "Receiving"
                        )
                        : String(
                            localized: "settings.hud.betterDisplay.notReceiving",
                            defaultValue: "Not receiving"
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
                        // swiftlint:disable:next line_length
                        defaultValue: "With BetterDisplay 4.2.1 or newer, Crema can show the brightness indicator for an external display. Nothing to enable here."
                    ))
                    // Named as the two switches they are, in the neighbour's own
                    // words, because this is the one place a user can act on it —
                    // and the second is what stops two bars from appearing at once.
                    Text(String(
                        localized: "settings.hud.betterDisplay.howTo",
                        // swiftlint:disable:next line_length
                        defaultValue: "In BetterDisplay, turn on Settings → Application → Integration → OSD notification, and turn its own OSD off in that same panel."
                    ))
                }
                .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }
}
