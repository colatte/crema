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
}
