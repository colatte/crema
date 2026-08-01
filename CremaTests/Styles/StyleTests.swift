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

    /// The rawValues ARE the persistence format (Preferences stores them per
    /// display): renaming a case silently orphans every stored choice, so the
    /// literals are pinned — a failure here means writing a migration, never
    /// just renaming the case.
    @Test func rawValuesAreThePersistedFormat() {
        #expect(Style.notch.rawValue == "notch")
        #expect(Style.card.rawValue == "card")
        #expect(Style.classic.rawValue == "classic")
    }

    /// The render rule every reader shares (`Style.resolved(on:)`): panels are
    /// built through it and Settings gates its Card-scoped controls on it, so the
    /// declared style and the drawn one cannot disagree by accident
    /// (docs/DECISIONS.md: rendered-style-gates-settings).
    @Test func notchRendersAsCardExactlyWhereThereIsNoSlit() {
        #expect(Style.notch.resolved(on: geometry) == .card)
        #expect(Style.notch.resolved(on: notched) == .notch)
    }

    @Test func theSlitlessFallbackTouchesTheNotchStyleOnly() {
        for style in [Style.card, .classic] {
            #expect(style.resolved(on: geometry) == style)
            #expect(style.resolved(on: notched) == style)
        }
    }

    /// The same rule read as a yes/no, for a reader that has to SAY whether a
    /// display honours the choice instead of drawing it. The table is written out
    /// rather than derived from `resolved`, which would restate the implementation
    /// instead of checking it: only the notch skin needs hardware, so it is the
    /// only one a slitless panel refuses.
    @Test func aStyleIsHonouredExactlyWhereItResolvesToItself() {
        #expect(Style.notch.isHonoured(on: notched))
        #expect(!Style.notch.isHonoured(on: geometry))
        #expect(Style.card.isHonoured(on: notched))
        #expect(Style.card.isHonoured(on: geometry))
        #expect(Style.classic.isHonoured(on: notched))
        #expect(Style.classic.isHonoured(on: geometry))
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

    @Test func cardNowPlayingMetricsStayPinnedIndependentOfTheHUD() {
        // Literal anti-drift pins: the now-playing surface (sizes + its radius)
        // is derived independently of the HUD strip, so a HUD resize must never
        // leak into these. The two radii are separate knobs on purpose — the
        // short HUD would read as a capsule at the now-playing radius.
        #expect(CardMetrics.compact == CGSize(width: 280, height: 64))
        #expect(CardMetrics.expanded == CGSize(width: 280, height: 128))
        #expect(CardMetrics.compactMinWidth == 180)
        #expect(CardMetrics.compactMaxWidth == 280)
        #expect(CardMetrics.expandedMinWidth == 240)
        #expect(CardMetrics.expandedMaxWidth == 280)
        #expect(CardMetrics.cornerRadius == 20)
        #expect(CardMetrics.hudSystemSize == CGSize(width: 210, height: 42))
        #expect(CardMetrics.hudSystemCornerRadius == 12)
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
                // A pure rule is deterministic: the same inputs must yield an equal frame.
                // swiftlint:disable:next identical_operands
                #expect(style.frame(for: state, on: geometry) == style.frame(for: state, on: geometry))
            }
        }
    }
}
