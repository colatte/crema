import SwiftUI

/// The launch-at-login switch, one for both windows that carry it (the General
/// tab and the tour's last step): a view onto the real registration, never a wish
/// that outran it. Each caller keeps the two mirrors and the note under the
/// switch, laid out its own way.
struct LaunchAtLoginToggle: View {
    let core: AppCore
    @Binding var isOn: Bool
    @Binding var needsApproval: Bool

    var body: some View {
        Toggle(isOn: Self.binding(isOn: $isOn, needsApproval: $needsApproval, apply: core.setLaunchesAtLogin)) {
            Text(String(localized: "settings.general.launchAtLogin", defaultValue: "Open Crema at login"))
        }
    }

    /// A custom binding rather than `onChange`: the setter routes the intent
    /// through `apply` and shows the status the attempt returns, so a failed
    /// registration snaps the switch back and a pending approval keeps it on with
    /// the caller's note — and a write inside the setter cannot re-fire it.
    static func binding(
        isOn: Binding<Bool>,
        needsApproval: Binding<Bool>,
        apply: @escaping @MainActor (Bool) -> (enabled: Bool, needsApproval: Bool)
    ) -> Binding<Bool> {
        Binding(
            get: { isOn.wrappedValue },
            set: { wanted in
                (isOn.wrappedValue, needsApproval.wrappedValue) = apply(wanted)
            }
        )
    }
}
