import Testing
@testable import Crema

/// The "has permission?" logic behind a protocol, tested with a mock
/// in both directions; polling runs on the injectable clock (no real sleeps).
@MainActor
struct AccessibilityPermissionMonitorTests {

    @Test func reflectsTheInitialStateImmediately() {
        let granted = AccessibilityPermissionMonitor(
            permission: MockAccessibilityPermission(granted: true),
            clock: TestSleepClock()
        )
        #expect(granted.isGranted)

        let denied = AccessibilityPermissionMonitor(
            permission: MockAccessibilityPermission(granted: false),
            clock: TestSleepClock()
        )
        #expect(!denied.isGranted)
    }

    @Test func detectsAGrantWithoutRelaunch() async {
        let permission = MockAccessibilityPermission(granted: false)
        let clock = TestSleepClock()
        let monitor = AccessibilityPermissionMonitor(permission: permission, clock: clock)
        monitor.start()
        #expect(!monitor.isGranted)

        permission.granted = true
        await clock.waitForSleep()
        clock.advance()

        #expect(await eventually { monitor.isGranted })
    }

    @Test func detectsARevocationToo() async {
        let permission = MockAccessibilityPermission(granted: true)
        let clock = TestSleepClock()
        let monitor = AccessibilityPermissionMonitor(permission: permission, clock: clock)
        monitor.start()
        #expect(monitor.isGranted)

        permission.granted = false
        await clock.waitForSleep()
        clock.advance()

        #expect(await eventually { !monitor.isGranted })
    }
}
