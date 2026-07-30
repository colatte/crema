import SwiftUI

struct PermissionsSettingsView: View {
    let core: AppCore

    private var granted: Bool { core.permissionMonitor.isGranted }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Label(
                        granted
                            ? String(localized: "settings.permissions.granted", defaultValue: "Granted")
                            : String(localized: "settings.permissions.notGranted", defaultValue: "Not granted"),
                        systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(granted ? .green : .orange)
                } label: {
                    Text(String(localized: "settings.permissions.accessibility", defaultValue: "Accessibility"))
                }

                if !granted {
                    Button(String(localized: "settings.permissions.grant", defaultValue: "Grant Accessibility Access…")) {
                        core.requestAccessibilityAccess()
                    }
                }
            } footer: {
                Text(String(
                    localized: "settings.permissions.footer",
                    // swiftlint:disable:next line_length
                    defaultValue: "Crema needs Accessibility access to capture the media keys — for its volume and brightness HUDs and to replace the system indicators. Without it the app still runs; it just can't react to those keys. Granting is picked up automatically, no relaunch needed."
                ))
                .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }
}
