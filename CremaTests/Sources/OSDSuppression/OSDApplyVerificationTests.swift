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
