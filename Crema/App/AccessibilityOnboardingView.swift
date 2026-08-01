import SwiftUI

/// The Accessibility permission on its own, reachable from the menu whenever
/// someone wants it back. First launch belongs to the welcome tour, which walks
/// this same permission as one of its steps (docs/DECISIONS.md:
/// the-tour-configures-instead-of-pointing), so this window is the MANUAL path
/// and nothing presents it automatically.
///
/// It explains why the permission is needed, deep-links to the exact Settings
/// pane, and reflects a grant live — the monitor keeps polling, so no relaunch
/// is needed. Its sentences are the ones the tour's permission step reuses:
/// one permission asked for in one set of words.
@MainActor
struct AccessibilityOnboardingView: View {
    let monitor: AccessibilityPermissionMonitor
    let openSettings: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: monitor.isGranted ? "checkmark.circle.fill" : "accessibility")
                .font(.system(size: 44))
                .foregroundStyle(monitor.isGranted ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))

            Text(String(localized: "onboarding.title", defaultValue: "Crema needs Accessibility access"))
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(String(
                localized: "onboarding.body",
                // swiftlint:disable:next line_length
                defaultValue: "Crema uses the Accessibility permission to capture the volume and brightness keys so it can show its own indicators. Without it the app keeps working — it just can't react to those keys."
            ))
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)

            Text(String(
                localized: "onboarding.grantDetection",
                defaultValue: "Granting is picked up automatically — no relaunch needed. If capture still doesn't start, relaunch Crema."
            ))
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(String(localized: "onboarding.notNow", defaultValue: "Not Now")) {
                    dismiss()
                }
                if monitor.isGranted {
                    Button(String(localized: "onboarding.done", defaultValue: "Done")) {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(String(localized: "onboarding.openSettings", defaultValue: "Open System Settings…")) {
                        openSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 6)
        }
        .padding(28)
        .frame(width: 440)
    }
}
