import SwiftUI

/// The notes under "Replace the system indicators", for both windows that carry
/// the switch (the Indicators tab and the tour's key test): what it does, where
/// brightness stops, and which of two absences holds it back. One view, because
/// which warning shows is a decision, and a decision spelled in two places is
/// one that changes in one of them.
struct SuppressionNotes: View {
    let core: AppCore
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(String(
                localized: "settings.hud.suppress.footer",
                defaultValue: "Hides the system volume and brightness indicators and shows Crema’s instead."
            ))
            // Unconditional, and deliberately not routed through
            // `brightnessKeyTargetNotice`: that answer needs a
            // MediaKeyChainNotice, whose every read resets the latency counters of
            // every tap on the machine — a body is rebuilt whenever SwiftUI likes,
            // so binding it here would turn a window into a periodic system-wide
            // probe. The sentence above, alone, is flatly false in two whole
            // arrangements: with the pointer on any other display, and on a Mac
            // with no built-in panel at all
            // (docs/DECISIONS.md: brightness-key-follows-the-pointer).
            Text(String(
                localized: "settings.hud.suppress.footer.brightnessScope",
                // swiftlint:disable:next line_length - one line, so check-catalog.py reads the defaultValue
                defaultValue: "Brightness is only replaced on the built-in display, while the pointer is on it. With the pointer on another display, macOS shows its own."
            ))
            // Two different absences behind one disabled switch, and only one of
            // them is the reader's to fix. Told apart because a joint gate says
            // "needs Accessibility access" to someone who has already granted it —
            // accusing the user of withholding the one thing they did, with no way
            // to make the sentence go away.
            if !core.permissionMonitor.isGranted {
                Text(String(
                    localized: "settings.hud.suppress.needsPermission",
                    defaultValue: "Needs Accessibility access — until then the system’s own indicators stay."
                ))
                .foregroundStyle(.orange)
            } else if core.osdSuppressor == nil {
                Text(String(
                    localized: "settings.hud.suppress.unavailable",
                    defaultValue: "System indicator replacement isn’t available on this Mac."
                ))
                .foregroundStyle(.orange)
            }
        }
    }
}
