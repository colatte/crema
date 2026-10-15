import SwiftUI

/// What the Accessibility permission lets Crema do, and what it never sees: one
/// list for both windows that ask for it (the tour's permission step and the
/// standalone window), so one permission is asked for in one set of words.
///
/// What it never sees is a fact of the tap, not a promise: the tap listens to
/// system-defined events only, the special keys, and no typing reaches it
/// (CGEventTapMediaKeySource). Volume is not on the list because it needs no
/// grant — Core Audio reports it either way.
struct AccessibilityPurposeList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "accessibility.purpose.lead", defaultValue: "With this access, Crema can:"))
            Bullet(symbol: "sun.max", text: String(
                localized: "accessibility.purpose.brightness",
                defaultValue: "Show its own indicator when you press a brightness key"
            ))
            Bullet(symbol: "eye.slash", text: String(
                localized: "accessibility.purpose.replace",
                defaultValue: "Replace the system indicators, if you choose to"
            ))
            // Set apart from the list above it, in the same column: what the app
            // never sees is no part of what the grant lets it do.
            Bullet(symbol: "lock", text: String(
                localized: "accessibility.purpose.privacy",
                defaultValue: "It only listens to keys like volume and brightness, never to what you type."
            ))
            .padding(.top, 8)
        }
        .multilineTextAlignment(.leading)
        .foregroundStyle(.secondary)
    }
}

/// One item of the list, its symbol in a column of fixed width so every line's
/// text starts at the same place whatever the symbol's own width.
private struct Bullet: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
