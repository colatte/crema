import AppKit
import Testing
@testable import Crema

/// The tour's arrow at the menu bar icon: where it stands, and which window
/// is taken for the icon.
@MainActor
struct MenuBarPointerPanelTests {

    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    /// Under the icon's middle, below it with a gap, on whole points — an icon
    /// of odd width puts its middle on a half point, and the arrow must not.
    @Test func theArrowStandsCentredUnderTheIconOnWholePoints() {
        let icon = CGRect(x: 934, y: 949, width: 33, height: 33)

        let frame = MenuBarPointerPanel.frame(pointingAt: icon)

        #expect(frame.size == MenuBarPointerPanel.size)
        #expect(abs(frame.midX - icon.midX) <= 0.5)
        #expect(frame.maxY < icon.minY)
        #expect(frame.origin.x == frame.origin.x.rounded())
        #expect(frame.origin.y == frame.origin.y.rounded())
    }

    /// The app's own surfaces stand above the status level and its windows
    /// below it; only the status-level window on a screen is the icon.
    @Test func theIconIsTheStatusLevelWindowOnAScreen() {
        let icon = CGRect(x: 934, y: 949, width: 34, height: 33)
        let windows: [(level: NSWindow.Level, frame: CGRect)] = [
            (NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3), CGRect(x: 604, y: 802, width: 304, height: 140)),
            (.normal, CGRect(x: 755, y: 159, width: 560, height: 552)),
            (.floating, CGRect(x: 0, y: 0, width: 44, height: 56)),
            (.statusBar, icon),
        ]

        #expect(StatusItemLocation.frame(among: windows, screens: [screen]) == icon)
    }

    /// Not built yet, or put away by macOS where no screen is: no arrow, rather
    /// than an arrow pointing at nothing.
    @Test func noIconOnAnyScreenIsNoAnswer() {
        let offscreen = CGRect(x: -4000, y: 4000, width: 34, height: 33)

        #expect(StatusItemLocation.frame(among: [], screens: [screen]) == nil)
        #expect(StatusItemLocation.frame(among: [(.statusBar, offscreen)], screens: [screen]) == nil)
        #expect(StatusItemLocation.frame(among: [(.statusBar, .zero)], screens: [screen]) == nil)
    }

    /// The icon is built a moment after launch, so a miss is asked again on the
    /// injected clock — and after the last attempt nothing is left running.
    @Test func aMissedIconIsAskedForAgainThenLeftAlone() async {
        let clock = TestSleepClock()
        let asked = Tally()
        let pointer = MenuBarPointerPanel(locate: { asked.count += 1; return nil }, clock: clock)

        pointer.show()
        for _ in 0..<MenuBarPointerPanel.attempts {
            await clock.waitForSleep(delay: MenuBarPointerPanel.retryInterval)
            clock.advance(delay: MenuBarPointerPanel.retryInterval)
        }

        #expect(await eventually { asked.count == MenuBarPointerPanel.attempts })
        await settle()
        #expect(clock.pendingSleeps == 0)
        #expect(asked.count == MenuBarPointerPanel.attempts)
    }

    /// Hiding mid-search ends it: the tour leaving its last step must not leave
    /// an arrow that turns up a second later.
    @Test func hidingStopsTheSearch() async {
        let clock = TestSleepClock()
        let asked = Tally()
        let pointer = MenuBarPointerPanel(locate: { asked.count += 1; return nil }, clock: clock)

        pointer.show()
        await clock.waitForSleep(delay: MenuBarPointerPanel.retryInterval)
        pointer.hide()
        clock.advance(delay: MenuBarPointerPanel.retryInterval)
        await settle()

        #expect(asked.count == 1)
        #expect(clock.pendingSleeps == 0)
    }
}
