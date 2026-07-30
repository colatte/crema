import CoreGraphics
import Testing
@testable import Crema

/// Which display a brightness key acts on: the one under the pointer
/// (docs/DECISIONS.md: brightness-key-follows-the-pointer). Pure over values, so
/// every arrangement is a test instead of a hardware trip — including the ones
/// nobody can stage on demand: a pointer exactly on the seam between two displays,
/// a reading that lands on none, and a mirror set where two displays claim the
/// same rectangle.
///
/// Every rect and every pointer here is in CoreGraphics' global display space:
/// origin at the top-left of the main display, y growing DOWN. That is the one
/// space the rule works in — the same one `CGEvent.location` and `CGDisplayBounds`
/// answer in — so a monitor placed ABOVE the laptop has a NEGATIVE y.
struct BrightnessKeyTargetingTests {
    /// The laptop, main display, at the origin of the space.
    private static let laptop = BrightnessKeyDisplay(
        bounds: CGRect(x: 0, y: 0, width: 1512, height: 982), isBuiltIn: true
    )
    /// The monitor to the RIGHT of the laptop.
    private static let monitorBeside = BrightnessKeyDisplay(
        bounds: CGRect(x: 1512, y: 0, width: 2560, height: 1440), isBuiltIn: false
    )
    /// The monitor ABOVE the laptop — the arrangement where the laptop's menu bar
    /// and the monitor's bottom row sit on the same line.
    private static let monitorAbove = BrightnessKeyDisplay(
        bounds: CGRect(x: 0, y: -1440, width: 2560, height: 1440), isBuiltIn: false
    )

    private static func target(_ pointer: CGPoint?, _ displays: [BrightnessKeyDisplay]) -> BrightnessKeyTarget {
        BrightnessKeyTargeting.target(pointer: pointer, among: displays)
    }

    @Test func thePointerOnTheLaptopAimsAtTheLaptop() {
        #expect(Self.target(CGPoint(x: 100, y: 100), [Self.laptop, Self.monitorBeside]) == .builtIn)
    }

    @Test func thePointerOnTheMonitorNeverFallsBackToTheLaptop() {
        // The reported bug as a test: the key used to dim the laptop while the
        // user was reading the monitor. There is no fallback to the built-in
        // panel, because that fallback IS the bug.
        #expect(Self.target(CGPoint(x: 2000, y: 100), [Self.laptop, Self.monitorBeside]) == .anotherDisplay)
    }

    @Test func oneDisplayAnswersItselfAndIsNotAFallbackToTheBuiltIn() {
        // The Mac with a single panel: the pointer disambiguates nothing there, so
        // a failed reading must not disable its keys.
        #expect(Self.target(nil, [Self.laptop]) == .builtIn)
        #expect(Self.target(CGPoint(x: 9999, y: 9999), [Self.laptop]) == .builtIn)
        // And clamshell needs no branch of its own: the single display is the
        // external one and is answered as such, never promoted to the shut panel.
        let clamshell = BrightnessKeyDisplay(
            bounds: CGRect(x: 0, y: 0, width: 2560, height: 1440), isBuiltIn: false
        )
        #expect(Self.target(nil, [clamshell]) == .anotherDisplay)
        #expect(Self.target(CGPoint(x: 100, y: 100), [clamshell]) == .anotherDisplay)
    }

    @Test func aPointerOnTheVerticalSeamBelongsToExactlyOneDisplay() {
        // Half-open bounds, the way CoreGraphics tiles them. Without a convention
        // both rects claim the seam and list order decides — and the laptop is
        // first, so the monitor would silently lose every press on its left edge.
        let pair = [Self.laptop, Self.monitorBeside]
        #expect(Self.target(CGPoint(x: 1512, y: 482), pair) == .anotherDisplay)
        #expect(Self.target(CGPoint(x: 1511, y: 482), pair) == .builtIn)
    }

    @Test func thePointerOnTheMenuBarBelongsToTheDisplayUnderIt() {
        // With the monitor placed above, the laptop's top row IS the seam. In this
        // space that row is the laptop's minY, which the laptop owns; the flipped
        // convention would hand every menu-bar press to the monitor.
        let stack = [Self.laptop, Self.monitorAbove]
        #expect(Self.target(CGPoint(x: 700, y: 0), stack) == .builtIn)
        #expect(Self.target(CGPoint(x: 700, y: -1), stack) == .anotherDisplay)
        // Mid-laptop and mid-monitor, so a sign error cannot pass by owning only
        // the seam.
        #expect(Self.target(CGPoint(x: 700, y: 500), stack) == .builtIn)
        #expect(Self.target(CGPoint(x: 700, y: -500), stack) == .anotherDisplay)
    }

    @Test func aPointerOnNoDisplayNamesNoneRatherThanGuessing() {
        let pair = [Self.laptop, Self.monitorBeside]
        // Past the right edge of both, and below the bottom of both: display
        // transitions really produce these, and answering would move a screen on a
        // guess.
        #expect(Self.target(CGPoint(x: 5000, y: 100), pair) == .unknown)
        #expect(Self.target(CGPoint(x: 100, y: 2000), pair) == .unknown)
        // A reading that failed is the same answer, for the same reason.
        #expect(Self.target(nil, pair) == .unknown)
        // And so is a list with nothing in it.
        #expect(Self.target(CGPoint(x: 100, y: 100), []) == .unknown)
    }

    @Test func aMirrorSetAnswersTheBuiltInWhicheverWayItIsListed() {
        // Mirroring reports the same rectangle once per display. Both contain the
        // point, so without an explicit tie-break the answer is whichever the
        // system happened to list first — and half the time that hands back the
        // key for a screen the built-in panel is itself lighting.
        let projector = BrightnessKeyDisplay(bounds: Self.laptop.bounds, isBuiltIn: false)
        #expect(Self.target(CGPoint(x: 100, y: 100), [projector, Self.laptop]) == .builtIn)
        #expect(Self.target(CGPoint(x: 100, y: 100), [Self.laptop, projector]) == .builtIn)
    }
}
