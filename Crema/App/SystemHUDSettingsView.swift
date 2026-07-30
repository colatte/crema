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
        }
        .formStyle(.grouped)
    }
}
