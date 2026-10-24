import CoreGraphics
import Testing
@testable import Crema

/// The monitor's own arm/disarm behaviour, which nothing else in the suite sees:
/// the region math is pinned in SurfaceHoverModelTests and the panel's retarget
/// in NSPanelPresentationPanelTests, while the pending exit that disarming
/// reports lives only here — a mutation deleting it leaves every other test green. That
/// report is what keeps the Coordinator's pointer record true when a display
/// stops being armed: a silent reset leaves the record holding a pointer that is
/// not on any surface, and the timers keyed on it (the HUD waits for the pointer
/// to leave before reverting) then never fire again
/// (docs/DECISIONS.md: hover-follows-the-eye).
///
/// Driven through the injected cursor, so the real NSEvent monitors that arming
/// installs cannot decide the outcome: a host event re-samples the same fake
/// point, and `sample` forwards transitions only. Their handlers are runloop
/// callouts on the main thread, and these tests never await, so none can even
/// interleave with the assertions.
@MainActor
struct SurfaceHoverMonitorTests {

    /// The fake pointer and the report log in one box — the two closures the
    /// monitor takes are the two halves of one story: where the cursor is, and
    /// what the monitor said about it.
    @MainActor
    private final class Pointer {
        var location: CGPoint
        private(set) var reports: [Bool] = []
        /// Whether each report came from a mouse event, in step with `reports`.
        private(set) var byMovement: [Bool] = []

        init(_ location: CGPoint) { self.location = location }

        func report(_ inside: Bool, _ moved: Bool) {
            reports.append(inside)
            byMovement.append(moved)
        }
    }

    private let regions = SurfaceHoverRegions.around(CGRect(x: 100, y: 100, width: 200, height: 60))
    private let insideSurface = CGPoint(x: 200, y: 130)
    private let farOutside = CGPoint(x: 900, y: 700)

    private func monitor(at location: CGPoint) -> (SurfaceHoverMonitor, Pointer) {
        let pointer = Pointer(location)
        let monitor = SurfaceHoverMonitor(
            regions: regions,
            cursorLocation: { pointer.location },
            report: { pointer.report($0, $1) }
        )
        return (monitor, pointer)
    }

    @Test func disarmingReportsThePendingExitExactlyOnce() throws {
        let (monitor, pointer) = self.monitor(at: insideSurface)
        monitor.setActive(true)
        // Precondition, not the claim: arming samples immediately, so a cursor
        // already inside is committed without waiting for a move.
        try #require(pointer.reports == [true])

        monitor.setActive(false)

        #expect(pointer.reports == [true, false])
        // Disarming again says nothing: the exit was already spent, and a second
        // false would teach the mirror a transition that never happened.
        monitor.stop()
        #expect(pointer.reports == [true, false])
    }

    @Test func disarmingWithThePointerOutsideStaysQuiet() throws {
        let (monitor, pointer) = self.monitor(at: farOutside)
        monitor.setActive(true)
        try #require(pointer.reports.isEmpty)

        monitor.setActive(false)

        // The exit is PENDING, never unconditional: this display never held the
        // pointer, so reporting its departure would move the global record on
        // behalf of a hover that no panel ever had.
        #expect(pointer.reports.isEmpty)
    }

    @Test func rearmingResamplesTheCursorAfterADisarm() throws {
        let (monitor, pointer) = self.monitor(at: insideSurface)
        monitor.setActive(true)
        monitor.setActive(false)
        try #require(pointer.reports == [true, false])

        // The pointer never moved, so re-arming can only re-commit because the
        // disarm cleared the inside flag as it reported it. A reset that kept the
        // flag would read the same point as "no transition" and arm silent,
        // leaving the surface unholdable under a cursor that is sitting on it.
        monitor.setActive(true)

        #expect(pointer.reports == [true, false, true])
        monitor.stop()
    }

    @Test func armingSamplesWhereTheCursorIsNow() throws {
        let (monitor, pointer) = self.monitor(at: insideSurface)
        monitor.setActive(true)
        monitor.setActive(false)
        try #require(pointer.reports == [true, false])

        // The pointer left while this display was disarmed, and nothing observed
        // it: the event monitors only exist while armed. So arming has to ask
        // where the cursor is NOW instead of resuming what it last knew.
        pointer.location = farOutside
        monitor.setActive(true)

        #expect(pointer.reports == [true, false])
        monitor.stop()
    }

    @Test func theArmingSampleIsNoMovement() {
        // A surface armed under a resting cursor learns where the cursor is, and
        // that is all it learns: nobody moved it, so the arrival holds no HUD
        // (docs/DECISIONS.md: hud-capsule-track).
        let (monitor, pointer) = self.monitor(at: insideSurface)
        monitor.setActive(true)

        #expect(pointer.reports == [true])
        #expect(pointer.byMovement == [false])
        monitor.stop()
    }

    @Test func aMouseEventConfirmsAStillPointerOnce() throws {
        let (monitor, pointer) = self.monitor(at: insideSurface)
        monitor.setActive(true)
        try #require(pointer.byMovement == [false])

        // The first mouse event with the pointer still inside is the movement the
        // arming sample lacked; the ones after it change nothing.
        monitor.pointerMoved()
        monitor.pointerMoved()

        #expect(pointer.reports == [true, true])
        #expect(pointer.byMovement == [false, true])
        monitor.stop()
    }

    @Test func aPointerThatMovesInArrivesByMovement() throws {
        let (monitor, pointer) = self.monitor(at: farOutside)
        monitor.setActive(true)
        try #require(pointer.reports.isEmpty)

        pointer.location = insideSurface
        monitor.pointerMoved()
        monitor.pointerMoved()

        #expect(pointer.reports == [true])
        #expect(pointer.byMovement == [true])
        monitor.stop()
    }

    @Test func aRegionGrowingUnderAStillPointerIsNoMovement() throws {
        let (monitor, pointer) = self.monitor(at: CGPoint(x: 500, y: 130))
        monitor.setActive(true)
        try #require(pointer.reports.isEmpty)

        // The surface came to the cursor, not the cursor to the surface.
        monitor.updateRegions(.around(CGRect(x: 100, y: 100, width: 600, height: 60)))

        #expect(pointer.reports == [true])
        #expect(pointer.byMovement == [false])
        monitor.stop()
    }
}
