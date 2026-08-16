import Testing
@testable import Crema

/// The self-check's pure verdict: a consumed key whose write silently did
/// nothing must read as failure (it strands the user), while boundary no-ops
/// and hardware quantization must not produce false alarms.
struct OSDApplyVerificationTests {

    @Test func exactApplicationPasses() {
        #expect(OSDApplyVerification.verified(before: 0.5, target: 0.5625, after: 0.5625))
    }

    @Test func unreadableReadBackFails() {
        #expect(!OSDApplyVerification.verified(before: 0.5, target: 0.5625, after: nil))
    }

    @Test func boundaryPinnedStepIsSuccess() {
        // Volume-up at 1.0: the step has nowhere to go — the native handler
        // no-ops there too, and disengaging over it would be a false alarm.
        #expect(OSDApplyVerification.verified(before: 1.0, target: 1.0, after: 1.0))
        #expect(OSDApplyVerification.verified(before: 0.0, target: 0.0, after: 0.0))
    }

    @Test func quantizedMovementInTheCommandedDirectionPasses() {
        // Keyboard backlight has coarse hardware levels: the write lands on
        // the device's own grid, short of the exact target — still alive.
        #expect(OSDApplyVerification.verified(before: 0.5, target: 0.5625, after: 0.53))
    }

    @Test func aDeadWriteFails() {
        #expect(!OSDApplyVerification.verified(before: 0.5, target: 0.5625, after: 0.5))
    }

    @Test func movementAgainstTheCommandFails() {
        #expect(!OSDApplyVerification.verified(before: 0.5, target: 0.5625, after: 0.45))
    }

    @Test func withinToleranceOfTheTargetPasses() {
        let justOff = 0.5625 - OSDApplyVerification.tolerance / 2
        #expect(OSDApplyVerification.verified(before: 0.5, target: 0.5625, after: justOff))
    }

    @Test func aStepClampedNearTheBoundaryVerifiesAgainstTheClampedTarget() {
        // before 0.98, volume-up: the target clamps to 1.0 (a shortened but
        // real step) — landing there passes, a dead write staying at 0.98
        // fails (the 0.02 shortfall exceeds the tolerance band).
        #expect(OSDApplyVerification.verified(before: 0.98, target: 1.0, after: 1.0))
        #expect(!OSDApplyVerification.verified(before: 0.98, target: 1.0, after: 0.98))
    }

    @Test func theToleranceBandIsAnAcceptedBlindSpotForDeadWrites() {
        // Documented trade-off (see the tolerance comment): a dead write
        // whose clamped target sits within the band of the current value
        // passes — tightening would false-alarm on quantized hardware. The
        // next full step falls outside the band and catches it.
        let nearlyPinned = 1.0 - OSDApplyVerification.tolerance / 2
        #expect(OSDApplyVerification.verified(before: nearlyPinned, target: 1.0, after: nearlyPinned))
    }
}

/// Telling "the HAL has not published yet" apart from "the write failed".
///
/// Apple documents the first as the general case — AudioObjectSetPropertyData:
/// "the value of the property should not be considered changed until the HAL
/// has called the listeners as many properties values are changed
/// asynchronously" (AudioHardware.h:302). Reading back on the next line and
/// calling an unmoved value a failure accuses a healthy device: the domain
/// suspends and the menu says Crema cannot change a volume it just changed.
struct OSDApplyAsynchronyTests {

    @Test func nothingMovedIsAmbiguousRatherThanFailed() {
        // The exact signature: the step asked for a change and the read came
        // back at the pre-write value.
        #expect(OSDApplyVerification.mayBeAsynchronous(before: 0.5, target: 0.5625, after: 0.5))
    }

    @Test func movingTheWrongWayIsARealDisagreement() {
        // Something wrote, and it was not us — or not what we asked. Looking
        // again would only launder it.
        #expect(!OSDApplyVerification.mayBeAsynchronous(before: 0.5, target: 0.5625, after: 0.4375))
    }

    @Test func stoppingShortIsARealDisagreement() {
        // A device that quantizes still MOVES, which `verified` already accepts.
        // What it must not do is look ambiguous and earn a second read.
        #expect(!OSDApplyVerification.mayBeAsynchronous(before: 0.5, target: 0.5625, after: 0.52))
    }

    @Test func aStepWithNowhereToGoIsNotAmbiguous() {
        // Volume-up at 1: `verified` already returns true for target == before,
        // so this must never claim a second read is worth taking.
        #expect(!OSDApplyVerification.mayBeAsynchronous(before: 1, target: 1, after: 1))
    }

    @Test func anUnreadableValueIsNotAmbiguityEither() {
        // A nil read is a READ failure and says nothing about the write — the
        // line the apply cycle already draws before this is consulted.
        #expect(!OSDApplyVerification.mayBeAsynchronous(before: 0.5, target: 0.5625, after: nil))
    }

    @Test func theTwoRulesDisagreeOnlyWhereTheSecondReadIsWorthTaking() {
        // Whatever `verified` already accepts must never be called ambiguous:
        // a second read on a healthy apply is latency on every keypress.
        let cases: [(Double, Double, Double)] = [
            (0.5, 0.5625, 0.5625), (0.5, 0.5625, 0.52), (1, 1, 1), (0.5, 0.4375, 0.4375),
        ]
        for (before, target, after) in cases where
            OSDApplyVerification.verified(before: before, target: target, after: after) {
            #expect(!OSDApplyVerification.mayBeAsynchronous(before: before, target: target, after: after))
        }
    }
}
