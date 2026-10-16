#if DEBUG
import AppKit
import Foundation
import os

/// The demo, driven from outside the process: the site's capture script
/// (`scripts/site-capture/`) puts the real surfaces in each state by posting
/// commands, one plain line each, as a distributed notification. Debug and
/// demo sources only; it reaches nothing a Release build has.
///
/// Commands: `play`, `pause`, `next`, `seek <seconds>`, `invoke`,
/// `hud <volume|screenBrightness|keyboardBrightness> <0…1>`, `route <case>`,
/// `style <notch|card|classic>`, `place <HUDPlacement>`, `indicator <slider|filled>`,
/// `tour <step|close>`, `appearance <dark|light>`, `quit`. An unknown line is logged and ignored.
@MainActor
enum DemoRemote {
    static let notification = Notification.Name("com.colatte.crema.demo")
    private static var observation: NSObjectProtocol?
    private static let logger = Logger.crema("DemoRemote")

    static func start(core: AppCore) {
        guard observation == nil, core.demo != nil else { return }
        observation = DistributedNotificationCenter.default().addObserver(
            forName: notification, object: nil, queue: .main
        ) { [weak core] note in
            let line = note.object as? String ?? ""
            MainActor.assumeIsolated {
                guard let core else { return }
                run(line, on: core)
            }
        }
    }

    private static func run(_ line: String, on core: AppCore) {
        guard let demo = core.demo else { return }
        let words = line.split(separator: " ").map(String.init)
        let command = words.first ?? ""
        let argument = words.count > 1 ? words[1] : ""
        let value = words.count > 2 ? Double(words[2]) : nil
        if runMedia(command, argument, value, on: demo, core: core) || runSetting(command, argument, on: core) { return }
        logger.notice("demo remote: unknown command \(line, privacy: .public)")
    }

    /// The player and the indicators: what the demo sources themselves stand in for.
    private static func runMedia(_ command: String, _ argument: String, _ value: Double?, on demo: DemoEngine, core: AppCore) -> Bool {
        switch command {
        case "play": demo.media.demoSetPlaying(true)
        case "pause": demo.media.demoSetPlaying(false)
        case "next": demo.media.demoNextTrack()
        case "seek": if let seconds = Double(argument) { demo.media.demoSeek(to: seconds) }
        case "invoke": core.coordinator.invoke()
        case "hud":
            if let kind = SystemHUD.Kind.allCases.first(where: { argument == "\($0)" }), let value {
                demo.hud.demoSet(kind, to: value)
            }
        case "route":
            if let route = AudioOutputRoute.allCases.first(where: { argument == "\($0)" }) {
                demo.hud.demoSetOutputDevice(route)
            }
        default: return false
        }
        return true
    }

    /// The settings a capture changes, through the same AppCore calls Settings makes.
    private static func runSetting(_ command: String, _ argument: String, on core: AppCore) -> Bool {
        switch command {
        case "style": if let style = Style(rawValue: argument) { core.setStyleEverywhere(style) }
        case "place": if let placement = HUDPlacement(rawValue: argument) { core.chooseHUDPlacement(placement) }
        case "indicator": if let style = HUDIndicatorStyle(rawValue: argument) { core.setHUDIndicatorStyle(style) }
        case "tour":
            if argument == "close" {
                core.closeWelcomeTour()
            } else if let step = WelcomeTourStep(rawValue: argument) {
                core.showWelcomeTour(at: step)
            }
        case "appearance": NSApp.appearance = NSAppearance(named: argument == "dark" ? .darkAqua : .aqua)
        case "quit": NSApp.terminate(nil)
        default: return false
        }
        return true
    }
}
#endif
