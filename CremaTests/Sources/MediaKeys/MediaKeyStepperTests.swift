import Testing
@testable import Crema

/// The suppression stepper: with the native key consumed, this arithmetic is
/// the user's volume/brightness control — it must match the native feel
/// (16 steps; Option+Shift quarter-steps) and never escape 0...1.
struct MediaKeyStepperTests {

    @Test func coarseStepIsOneSixteenth() {
        #expect(MediaKeyStepper.next(from: 0.5, key: .volumeUp, fine: false) == 0.5 + 1.0 / 16.0)
        #expect(MediaKeyStepper.next(from: 0.5, key: .volumeDown, fine: false) == 0.5 - 1.0 / 16.0)
        #expect(MediaKeyStepper.next(from: 0.5, key: .screenBrightnessUp, fine: false) == 0.5 + 1.0 / 16.0)
        #expect(MediaKeyStepper.next(from: 0.5, key: .keyboardBrightnessDown, fine: false) == 0.5 - 1.0 / 16.0)
    }

    @Test func fineStepIsOneSixtyFourth() {
        #expect(MediaKeyStepper.next(from: 0.5, key: .volumeUp, fine: true) == 0.5 + 1.0 / 64.0)
        #expect(MediaKeyStepper.next(from: 0.5, key: .screenBrightnessDown, fine: true) == 0.5 - 1.0 / 64.0)
    }

    @Test func clampsAtBothEnds() {
        #expect(MediaKeyStepper.next(from: 0, key: .volumeDown, fine: false) == 0)
        #expect(MediaKeyStepper.next(from: 1, key: .volumeUp, fine: false) == 1)
        #expect(MediaKeyStepper.next(from: 0.99, key: .volumeUp, fine: false) == 1)
        #expect(MediaKeyStepper.next(from: 0.01, key: .screenBrightnessDown, fine: true) == 0)
    }

    @Test func muteIsNotAStep() {
        #expect(MediaKeyStepper.next(from: 0.5, key: .mute, fine: false) == nil)
    }

    /// The consumption path swallows both phases of an owned key: a key-up
    /// decodes to the same key the down did, phase ignored — an orphan up
    /// reaching the system would confuse its key pairing.
    @Test func ownedKeyDecodeIgnoresThePhase() {
        // data1 layout: keyCode in the high word; 0x0A down / 0x0B up in the
        // second byte of the low word.
        let volumeUpDown = (0 << 16) | 0x0A00
        let volumeUpUp = (0 << 16) | 0x0B00
        #expect(MediaKeyTranslation.mediaKey(fromData1: volumeUpDown) == .volumeUp)
        #expect(MediaKeyTranslation.mediaKey(fromData1: volumeUpUp) == nil)   // stream: down-only
        #expect(MediaKeyTranslation.ownedKey(ignoringPhaseFromData1: volumeUpDown) == .volumeUp)
        #expect(MediaKeyTranslation.ownedKey(ignoringPhaseFromData1: volumeUpUp) == .volumeUp)
    }

    @Test func foreignKeysAreNeverOwned() {
        // Play/pause (NX_KEYTYPE_PLAY = 16) is not ours in either decode —
        // suppression must never swallow keys it does not reapply.
        let playDown = (16 << 16) | 0x0A00
        #expect(MediaKeyTranslation.mediaKey(fromData1: playDown) == nil)
        #expect(MediaKeyTranslation.ownedKey(ignoringPhaseFromData1: playDown) == nil)
    }
}
