#if DEBUG
import SwiftUI

/// Debug-only menu-bar section. The app runs on real system sources by default;
/// this toggle swaps in the demo engine (relaunch) to exercise the UI without
/// hardware or real media. The demo buttons only appear when it's active.
@MainActor
struct DemoMenu: View {
    let core: AppCore
    @State private var style: Style = .notch
    @AppStorage("CremaUseDemoSources") private var useDemoSources = false
    @AppStorage("CremaObserveAdapter") private var observeAdapter = false
    @AppStorage("CremaDisableAdapter") private var disableAdapter = false

    var body: some View {
        Toggle(
            String(localized: "demo.useDemoSources", defaultValue: "Demo: Use Demo Sources (relaunch to apply)"),
            isOn: $useDemoSources
        )
        Toggle(
            String(localized: "demo.observeAdapter", defaultValue: "Demo: Log now-playing adapter stream (relaunch to apply)"),
            isOn: $observeAdapter
        )
        Toggle(
            String(localized: "demo.disableAdapter", defaultValue: "Demo: Force now-playing JXA fallback (relaunch to apply)"),
            isOn: $disableAdapter
        )
        if let demo = core.demo {
            Button(String(localized: "demo.playPause", defaultValue: "Demo: Play/Pause")) {
                demo.media.demoTogglePlayPause()
            }
            Button(String(localized: "demo.nextTrack", defaultValue: "Demo: Next Track")) {
                demo.media.demoNextTrack()
            }
            Button(String(localized: "demo.hud.volume", defaultValue: "Demo: Volume HUD")) {
                demo.hud.demoKeyPress(.volume)
            }
            Button(String(localized: "demo.hud.screenBrightness", defaultValue: "Demo: Screen Brightness HUD")) {
                demo.hud.demoKeyPress(.screenBrightness)
            }
            Button(String(localized: "demo.hud.keyboardBrightness", defaultValue: "Demo: Keyboard Brightness HUD")) {
                demo.hud.demoKeyPress(.keyboardBrightness)
            }
        }
        Picker(String(localized: "demo.stylePicker", defaultValue: "Style (All Displays)"), selection: $style) {
            ForEach(Style.allCases, id: \.self) { style in
                Text(style.displayName).tag(style)
            }
        }
        .onChange(of: style) { _, newStyle in
            core.setStyleEverywhere(newStyle)
        }
    }
}
#endif
