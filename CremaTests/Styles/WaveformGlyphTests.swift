import CoreGraphics
import Testing
@testable import Crema

/// The glyph's rules, each checked against values written independently of the
/// rule — the glyph's own `&&` chain would agree with any mutation of itself.
///
/// The PULSE has two vetoes and they are not interchangeable: Reduce Motion is the
/// standing accessibility preference over every animation in the app, and Low
/// Power Mode is the system asking that nothing be spent on motion. A `&&
/// !lowPower` deletion is the mutation that goes silent — the bars keep dancing
/// forever and nothing else in the app reads the mirror. Both are read live inside
/// the body, so the pulse stops the moment either flips.
///
/// The FORM is a separate question with a separate answer, held apart from the
/// pulse here: a veto takes the movement away, not the fact that something is
/// playing. And the pulse's SHAPE is a function of the clock, checked at points of
/// its curve and against the one promise that form exists for: no bar leaves the
/// rest…peak span.
@MainActor
struct WaveformGlyphTests {

    @Test func playbackWithNoVetoIsTheOnlyWayTheBarsDance() {
        #expect(WaveformGlyph.dances(animating: true, reduceMotion: false, lowPower: false))
        // Paused is paused: nothing about the vetoes can start a pulse that
        // playback did not ask for.
        #expect(!WaveformGlyph.dances(animating: false, reduceMotion: false, lowPower: false))
    }

    @Test func reduceMotionVetoesTheDance() {
        // The accessibility preference outranks playback, at any moment and not
        // only at the next transport event — a user who switches it on with the
        // surface already up must see the bars settle.
        #expect(!WaveformGlyph.dances(animating: true, reduceMotion: true, lowPower: false))
    }

    @Test func lowPowerModeVetoesTheDance() {
        // Low Power Mode asks the whole system to stop spending on motion, and a
        // perpetual pulse on a surface that sits over the menu bar is exactly
        // the kind of spend it means. The veto is
        // `SurfaceAnimation.allowsPerpetualMotion`'s, pinned there as well; this is
        // the glyph asking it.
        #expect(!WaveformGlyph.dances(animating: true, reduceMotion: false, lowPower: true))
    }

    // MARK: - The form, which the vetoes do not decide

    @Test func aVetoedGlyphStillSaysPlaying() {
        // The bug this rule exists for: with the pulse vetoed and every bar at
        // rest, playing and paused draw the same four 4 pt stubs — and on the
        // compact surfaces this glyph is the ONLY thing that says playing at all.
        // The vetoes forbid movement and spending, not information.
        let playing = WaveformGlyph.stillHeights(animating: true, reduceMotion: true, lowPower: false)
        let paused = WaveformGlyph.stillHeights(animating: false, reduceMotion: true, lowPower: false)
        #expect(playing != paused)
        #expect(WaveformGlyph.stillHeights(animating: true, reduceMotion: false, lowPower: true) == playing)
    }

    @Test func aPausedGlyphIsFlatAtRestUnderEveryVeto() {
        // Paused is paused, and it is flat: nothing about the vetoes may draw a
        // silhouette playback did not ask for.
        let flat = [CGFloat](repeating: WaveformGlyph.Configuration.standard.restHeight, count: 4)
        for reduceMotion in [false, true] {
            for lowPower in [false, true] {
                #expect(
                    WaveformGlyph.stillHeights(animating: false, reduceMotion: reduceMotion, lowPower: lowPower) == flat,
                    "reduceMotion=\(reduceMotion) lowPower=\(lowPower)"
                )
            }
        }
    }

    @Test func theSilhouetteIsStaggeredAcrossTheRestToPeakSpan() {
        // Written out rather than recomputed from the profile: four bars at four
        // different heights is what makes the row read as levels instead of the
        // flat block four equal bars draw, and the numbers are the standard
        // tuning's own span (4…12) at the profile's fractions.
        let vetoed = WaveformGlyph.stillHeights(animating: true, reduceMotion: true, lowPower: false)
        #expect(vetoed == [4, 12, 8, 10])
        // Zero movement is the whole point: the profile is a shape, not a phase,
        // so the same inputs answer the same heights every time.
        #expect(WaveformGlyph.stillHeights(animating: true, reduceMotion: true, lowPower: false) == vetoed)
    }

    @Test func aHiddenSurfaceStopsThePulseAndKeepsTheSilhouette() {
        // A hidden surface still draws the glyph it faded out with, so it vetoes
        // the pulse as Reduce Motion does: no motion nobody sees, and the same
        // silhouette, so nothing settles during the fade.
        #expect(!WaveformGlyph.dances(animating: true, reduceMotion: false, lowPower: false, shown: false))
        #expect(WaveformGlyph.stillHeights(animating: true, reduceMotion: false, lowPower: false, shown: false)
            == WaveformGlyph.stillHeights(animating: true, reduceMotion: true, lowPower: false))
    }

    @Test func theSilhouetteFollowsATuningItDoesNotHardcode() {
        // A skin that diverges (Configuration is per call site) gets its own span
        // and its own bar count — the fractions are the constant, not the points.
        var wide = WaveformGlyph.Configuration.standard
        wide.barCount = 6
        wide.restHeight = 10
        wide.peakHeight = 20
        let heights = WaveformGlyph.stillHeights(
            animating: true, reduceMotion: false, lowPower: true, config: wide
        )
        #expect(heights == [10, 20, 15, 17.5, 10, 20])
    }

    /// One row of the table, written out rather than computed — a row that
    /// recomputed the rule would agree with any mutation of it.
    private struct Row {
        let animating: Bool
        let reduceMotion: Bool
        let lowPower: Bool
        let dances: Bool
    }

    @Test func theTwoVetoesCompose() {
        // The whole truth table: each veto alone stops the pulse and the two
        // together do too, so the composition can only be a conjunction — an `||`
        // anywhere in it, or one veto folded into the other, would let a row with
        // exactly one veto set dance.
        let table = [
            Row(animating: true, reduceMotion: false, lowPower: false, dances: true),
            Row(animating: true, reduceMotion: true, lowPower: false, dances: false),
            Row(animating: true, reduceMotion: false, lowPower: true, dances: false),
            Row(animating: true, reduceMotion: true, lowPower: true, dances: false),
            Row(animating: false, reduceMotion: false, lowPower: false, dances: false),
            Row(animating: false, reduceMotion: true, lowPower: false, dances: false),
            Row(animating: false, reduceMotion: false, lowPower: true, dances: false),
            Row(animating: false, reduceMotion: true, lowPower: true, dances: false),
        ]
        for row in table {
            #expect(
                WaveformGlyph.dances(
                    animating: row.animating, reduceMotion: row.reduceMotion, lowPower: row.lowPower
                ) == row.dances,
                "animating=\(row.animating) reduceMotion=\(row.reduceMotion) lowPower=\(row.lowPower)"
            )
        }
    }

    // MARK: - The pulse's shape, a function of the clock

    /// Equal within float rounding: the curve's turning points come out of `cos`,
    /// which lands a few ulps off exact zero and one.
    private func isClose(_ height: CGFloat, _ expected: CGFloat) -> Bool {
        abs(height - expected) < 1e-9
    }

    @Test func aBarRisesFromRestToPeakInOneStrokeAndFallsBackInTheNext() {
        // The standard tuning written out: 4…12 pt, half a second a stroke.
        #expect(isClose(WaveformGlyph.pulseHeight(bar: 0, at: 0), 4))
        #expect(isClose(WaveformGlyph.pulseHeight(bar: 0, at: 0.25), 8))
        #expect(isClose(WaveformGlyph.pulseHeight(bar: 0, at: 0.5), 12))
        #expect(isClose(WaveformGlyph.pulseHeight(bar: 0, at: 0.75), 8))
        #expect(isClose(WaveformGlyph.pulseHeight(bar: 0, at: 1), 4))
    }

    @Test func eachBarIsAQuarterStrokeBehindTheOneBeforeIt() {
        // Four bars over one stroke: each touches rest 0.125 s after its left
        // neighbour, so one rises while another falls and no two move together.
        for bar in 0..<4 {
            #expect(isClose(WaveformGlyph.pulseHeight(bar: bar, at: 0.125 * Double(bar)), 4), "bar \(bar)")
        }
        #expect(WaveformGlyph.pulseHeight(bar: 0, at: 0.3) != WaveformGlyph.pulseHeight(bar: 1, at: 0.3))
    }

    @Test func noBarEverLeavesTheRestToPeakSpan() {
        // The promise this form exists for: no bar dips under rest, out of sight.
        // Sampled at uneven steps near zero and at the reference-date magnitude the
        // view's clock really passes, where the phase is billions of radians.
        let now = 783_000_000.0
        for step in 0..<2000 {
            for base in [0, now] {
                let time = base + Double(step) * 0.0137
                for bar in 0..<4 {
                    let height = WaveformGlyph.pulseHeight(bar: bar, at: time)
                    #expect((4...12).contains(height), "bar \(bar) at \(time): \(height)")
                }
            }
        }
    }

    @Test func thePulseRepeatsEveryTwoStrokes() {
        for time in [0.1, 0.37, 2.9] {
            #expect(isClose(WaveformGlyph.pulseHeight(bar: 2, at: time), WaveformGlyph.pulseHeight(bar: 2, at: time + 1)))
        }
        // At the clock's real magnitude a Double carries the phase to about 1e-5 pt
        // of height: a thousandth of a point is the bound, far under a pixel.
        let late = 783_000_000.21
        let drift = abs(WaveformGlyph.pulseHeight(bar: 2, at: late) - WaveformGlyph.pulseHeight(bar: 2, at: late + 1))
        #expect(drift < 0.001)
    }
}
