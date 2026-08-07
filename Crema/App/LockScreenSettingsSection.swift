import SwiftUI

/// The lock-screen surface's one control, in its own file because
/// `SettingsView.swift` sits against the 500-line ceiling it already broke
/// once — the bigger tabs and the per-display row moved out for the same reason.
///
/// It lives in the Now Playing tab rather than a tab of its own: it IS now
/// playing, drawn somewhere else. A separate tab would suggest a separate
/// feature and put two answers to "where does my music show up" a click apart.
struct LockScreenSettingsSection: View {
    let core: AppCore
    @AppStorage(Preferences.showsLockScreenWidgetKey) private var showsWidget = false
    @AppStorage(Preferences.fetchesHighResolutionArtworkKey) private var fetchesArtwork = false

    var body: some View {
        Section {
            // The toggle is ABSENT rather than greyed where the path does not
            // exist, and the sentence below takes its place. A disabled switch
            // would invite the user to hunt for what unlocks it; there is
            // nothing to find, because the answer is this build of macOS.
            if core.lockScreenWidgetIsSupported {
                Toggle(isOn: $showsWidget) {
                    Text(String(
                        localized: "settings.lockScreen.widget",
                        defaultValue: "Show what's playing on the lock screen"
                    ))
                }
                .onChange(of: showsWidget) { _, new in core.setShowsLockScreenWidget(new) }

                // Nested under the widget rather than beside it: it improves
                // one surface and means nothing without it, and offering a
                // network toggle to someone who is not using the feature is
                // asking a question that has no consequence.
                if showsWidget {
                    Toggle(isOn: $fetchesArtwork) {
                        Text(String(
                            localized: "settings.lockScreen.artwork",
                            defaultValue: "Fetch a larger cover"
                        ))
                    }
                    .onChange(of: fetchesArtwork) { _, new in core.setFetchesHighResolutionArtwork(new) }
                }
            } else {
                Text(String(
                    localized: "settings.lockScreen.unsupported",
                    defaultValue: "This version of macOS doesn't offer a way to draw on the lock screen, so Crema leaves it alone."
                ))
                .settingsFootnote()
            }
        } header: {
            Text(String(localized: "settings.lockScreen", defaultValue: "Lock Screen"))
        } footer: {
            if core.lockScreenWidgetIsSupported {
                // Says the cost in a sentence, the way the suppression footer
                // does: this one draws over a security surface, and the user
                // should know that before switching it on rather than after.
                Text(String(
                    localized: "settings.lockScreen.widget.footer",
                    // swiftlint:disable:next line_length
                    defaultValue: "A card above your login shows the cover, the title and the controls while music plays. Click it and the cover fills the screen. It never asks for your password or reads anything you type."
                ))
                .settingsFootnote()

                if showsWidget {
                    // The cost, said plainly and before the switch is flipped:
                    // players hand over a small cover, and the only way to a
                    // bigger one is to ask someone who has it.
                    Text(String(
                        localized: "settings.lockScreen.artwork.footer",
                        // swiftlint:disable:next line_length
                        defaultValue: "Players hand over a small cover, which looks soft filling a screen. Crema can ask Apple's public search for a larger one — no account, but it does send the track name. Off by default."
                    ))
                    .settingsFootnote()
                }
            }
        }
    }
}
