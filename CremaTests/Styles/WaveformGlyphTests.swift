import CoreGraphics
import Testing
@testable import Crema

/// The glyph's two decisions, each as a table written independently of the rule it
/// checks — the glyph's own `&&` chain would agree with any mutation of itself.
///
/// The PULSE has two vetoes and they are not interchangeable: Reduce Motion is the
/// standing accessibility preference over every animation in the app, and Low
/// Power Mode is the system asking that nothing be spent on motion. A `&&
/// !lowPower` deletion is the mutation that goes silent — the bars keep dancing
/// forever and nothing else in the app reads the mirror. Both are read live inside
/// the body, which is why the `@State` phase is keyed on this rule and not on
/// `animating`.
///
/// The FORM is a separate question with a separate answer, and the second half of
/// this file is where the two are held apart: a veto takes the movement away, not
/// the fact that something is playing.
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
        // repeatForever pulse on a surface that sits over the menu bar is exactly
        // the kind of spend it means. Deleting `&& !lowPower` from the rule leaves
        // every other assertion in the suite green.
        #expect(!WaveformGlyph.dances(animating: true, reduceMotion: false, lowPower: true))
    }

    // MARK: - The form, which the vetoes do not decide

    @Test func aVetoedGlyphStillSaysPlaying() {
        // The bug this rule exists for: with the pulse vetoed and every bar at
        // rest, playing and paused drew the same four 4 pt stubs — and on the
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

    @Test func theHeightsBehindALivePulseAreItsFloorAndNotTheSilhouette() {
        // Playing with no veto, the height declared here is the value the endless
        // autoreverse animates AWAY from. Hand it the silhouette and the bar the
        // profile puts at peak would pulse from peak to peak — a bar that stops
        // moving while its neighbours dance, which no other assertion would catch.
        let flat = [CGFloat](repeating: WaveformGlyph.Configuration.standard.restHeight, count: 4)
        #expect(WaveformGlyph.stillHeights(animating: true, reduceMotion: false, lowPower: false) == flat)
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
}
