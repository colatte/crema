import CoreGraphics
import Testing
@testable import Crema

/// The closed Style enum: dispatch stays pure and testable per case.
@MainActor
struct StyleTests {

    private let geometry = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))
    private let notched = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeTop: 32,
        auxLeft: 663.5,
        auxRight: 663.5
    )
    private let track = CoordinatorHarness.playingTrack()

    @Test func coversTheThreeSpecStyles() {
        #expect(Style.allCases == [.notch, .card, .classic])
    }

    @Test func rawValueRoundTripsForPreferencesPersistence() {
        for style in Style.allCases {
            #expect(Style(rawValue: style.rawValue) == style)
        }
    }

    @Test func cardCaseDispatchesToTheCardFrameRule() {
        let states: [PresentationState] = [
            .hidden,
            .nowPlaying(track, expanded: false),
            .nowPlaying(track, expanded: true),
            .hud(SystemHUD(kind: .volume, value: 0.5)),
        ]
        for state in states {
            #expect(Style.card.frame(for: state, on: geometry) == CardStyle().frame(for: state, on: geometry))
        }
    }

    @Test func notchCaseDispatchesToTheNotchFrameRule() {
        let states: [PresentationState] = [
            .hidden,
            .nowPlaying(track, expanded: false),
            .nowPlaying(track, expanded: true),
            .hud(SystemHUD(kind: .volume, value: 0.5)),
        ]
        for state in states {
            #expect(Style.notch.frame(for: state, on: notched) == NotchStyle().frame(for: state, on: notched))
        }
    }

    @Test func cardAndClassicHaveDeterministicFramesForEveryState() {
        let states: [PresentationState] = [
            .hidden,
            .nowPlaying(track, expanded: false),
            .nowPlaying(track, expanded: true),
            .hud(SystemHUD(kind: .screenBrightness, value: 0.8)),
        ]
        for style in [Style.card, .classic] {
            for state in states {
                #expect(style.frame(for: state, on: geometry) == style.frame(for: state, on: geometry))
            }
        }
    }
}
