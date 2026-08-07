import AppKit
import Testing
@testable import Crema

/// The border's degradation, exercised without the real framework — the same
/// shape `BrightnessBridgeDegradeTests` uses for DisplayServices and
/// CoreBrightness, and for the same reason: the only honest observer of the
/// real SkyLight is a locked Mac, so what a test can own is the decision the
/// app makes when a symbol is not there.
@MainActor
struct SkyLightSpaceTests {

    /// A resolver that hands back a distinct non-nil pointer per name, so
    /// `unsafeBitCast` has something to bite on. The functions are never called
    /// — `isAvailable` is a question about resolution, not about behaviour.
    private static func resolvingAll(_ name: String) -> UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: abs(name.hashValue) | 1)
    }

    @Test func aFrameworkThatResolvesNothingIsUnavailable() {
        // The macOS that renamed or dropped the space API. The feature has to
        // report itself off rather than put a window into a space that was
        // never raised.
        let bridge = SkyLightSpaceBridge(resolver: { _ in nil })
        #expect(!bridge.isAvailable)
    }

    @Test func allFiveSymbolsAreRequired() {
        #expect(SkyLightSpaceBridge(resolver: Self.resolvingAll).isAvailable)
    }

    /// One missing symbol is the case that matters, and it is why `isAvailable`
    /// is an `&&` of five rather than a check on the one call `adopt` makes.
    ///
    /// Half this sequence is worse than none of it: create the space, fail to
    /// raise it, move the window in, and the surface sits at absolute level 0
    /// behind the shield — drawing correctly, in a place nobody will ever see
    /// it. That failure looks exactly like success from inside the process.
    @Test func anyOneMissingSymbolTakesTheWholeBorderDown() {
        let required = [
            "SLSMainConnectionID",
            "SLSSpaceCreate",
            "SLSSpaceSetAbsoluteLevel",
            "SLSShowSpaces",
            "SLSSpaceAddWindowsAndRemoveFromSpaces",
        ]
        for missing in required {
            let bridge = SkyLightSpaceBridge(resolver: { name in
                name == missing ? nil : Self.resolvingAll(name)
            })
            #expect(!bridge.isAvailable, "a missing \(missing) must take the border down")
        }
    }

    @Test func theNamesAreTheOnesTheProbeProved() {
        // The five the hardware probes ran, spelled here so a rename in the
        // bridge fails a test instead of failing silently on a locked Mac.
        var asked: [String] = []
        _ = SkyLightSpaceBridge(resolver: { name in
            asked.append(name)
            return Self.resolvingAll(name)
        })
        #expect(asked.sorted() == [
            "SLSMainConnectionID",
            "SLSShowSpaces",
            "SLSSpaceAddWindowsAndRemoveFromSpaces",
            "SLSSpaceCreate",
            "SLSSpaceSetAbsoluteLevel",
        ])
    }
}

/// A raised space that records instead of calling WindowServer.
@MainActor
final class RecordingRaisedSpace: RaisedSpace {
    var isAvailable: Bool
    private(set) var adopted: [Int] = []

    init(isAvailable: Bool = true) { self.isAvailable = isAvailable }

    func adopt(_ window: NSWindow) { adopted.append(window.windowNumber) }
}

/// The panel's contract with the space. Not the pixels — those need a locked
/// Mac — but the two decisions the code makes on its own.
@MainActor
struct LockScreenPanelTests {

    @Test func anUnavailableSpaceRefusesToBuildThePanel() {
        // Building anyway would put a window on the desktop that the user never
        // asked for and cannot see the point of: the whole premise is the other
        // side of the shield, and without the space there is no other side.
        let harness = CoordinatorHarness()
        let space = RecordingRaisedSpace(isAvailable: false)
        let panel = LockScreenPanel(
            screen: NSScreen.screens[0],
            coordinator: harness.coordinator,
            space: space,
            lowPower: LowPowerModeMirror(),
            artwork: LockArtworkResolver(lookup: MockArtworkLookup(), enabled: false)
        )
        #expect(panel == nil)
        #expect(space.adopted.isEmpty)
    }

    @Test func everyWindowServerEdgeReassertsTheSpace() {
        // Whether a raised space survives a display sleep is state living beyond
        // this process, which the J7 lesson says cannot be audited from inside
        // it. So the panel does not ask — it re-adopts on every edge, and the
        // call is idempotent precisely so that costs nothing.
        let harness = CoordinatorHarness()
        let space = RecordingRaisedSpace()
        let panel = LockScreenPanel(
            screen: NSScreen.screens[0],
            coordinator: harness.coordinator,
            space: space,
            lowPower: LowPowerModeMirror(),
            artwork: LockArtworkResolver(lookup: MockArtworkLookup(), enabled: false)
        )
        #expect(panel != nil)
        let afterInit = space.adopted.count
        #expect(afterInit == 1)

        panel?.reassertSpace()
        panel?.reassertSpace()
        #expect(space.adopted.count == afterInit + 2)
        // Always the same window: re-adopting must repair the one that exists,
        // never quietly start tracking a different one.
        #expect(Set(space.adopted).count == 1)

        panel?.close()
    }

    @Test func theTopologyEdgeReadoptsEvenWhenTheFrameDidNotMove() {
        // The common hotplug leaves the MAIN screen's frame untouched — a second
        // display appears beside it. The version that returned early there made
        // the one edge most likely to have reconfigured the WindowServer the one
        // edge that re-asserted nothing, while three comments said it did.
        let harness = CoordinatorHarness()
        let space = RecordingRaisedSpace()
        let screen = NSScreen.screens[0]
        let panel = LockScreenPanel(
            screen: screen,
            coordinator: harness.coordinator,
            space: space,
            lowPower: LowPowerModeMirror(),
            artwork: LockArtworkResolver(lookup: MockArtworkLookup(), enabled: false)
        )
        #expect(space.adopted.count == 1)

        panel?.setFrame(screen.frame)
        #expect(space.adopted.count == 2)

        panel?.close()
    }

    @Test func thePanelIsBornTakingNoClicksAtAll() {
        // The window is the size of the display and transparency does not pass a
        // click through (measured for the desktop panels, which carry the same
        // machinery). Over the lock shield the pixels it covers are the password
        // field's, so the starting value is the only safe one — and it is what
        // the routing degrades TO if the cursor monitors never fire there.
        let harness = CoordinatorHarness()
        let panel = LockScreenPanel(
            screen: NSScreen.screens[0],
            coordinator: harness.coordinator,
            space: RecordingRaisedSpace(),
            lowPower: LowPowerModeMirror(),
            artwork: LockArtworkResolver(lookup: MockArtworkLookup(), enabled: false)
        )
        #expect(panel?.capturesMouse == false)

        panel?.close()
    }
}
