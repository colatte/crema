import Testing
@testable import Crema

/// Graceful degradation: without the Accessibility permission the
/// source reports unavailable and never touches the CGEventTap API (the guard
/// runs before any tap creation), while the app keeps running.
struct MediaKeySourceAvailabilityTests {

    @Test func unavailableWithoutAccessibilityPermission() async {
        let permission = MockAccessibilityPermission(granted: false)
        let source = CGEventTapMediaKeySource(permission: permission, clock: TestSleepClock())

        #expect(await !source.isAvailable())
    }

    @Test func availabilityFollowsThePermission() async {
        let permission = MockAccessibilityPermission(granted: false)
        let clock = TestSleepClock()
        let source = CGEventTapMediaKeySource(permission: permission, clock: clock)
        #expect(await !source.isAvailable())

        // The poll's first check must have already run (and seen granted ==
        // false) before the flip — otherwise it could race us and reach the
        // real CGEvent API inside a unit test. After waitForSleep the task is
        // parked on the test clock, which this test never advances.
        await clock.waitForSleep()

        permission.granted = true
        #expect(await source.isAvailable())
    }
}
