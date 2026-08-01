import Testing
@testable import Crema

/// The pulse's whole decision, as a table written independently of the rule it
/// checks — the glyph's own `&&` chain would agree with any mutation of itself.
///
/// The rule has two vetoes and they are not interchangeable: Reduce Motion is the
/// standing accessibility preference over every animation in the app, and Low
/// Power Mode is the system asking that nothing be spent on motion. A `&&
/// !lowPower` deletion is the mutation that goes silent — the bars keep dancing
/// forever and nothing else in the app reads the mirror. Both are read live inside
/// the body, which is why the `@State` phase is keyed on this rule and not on
/// `animating`.
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
