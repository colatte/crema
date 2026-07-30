import Testing
@testable import Crema

/// Which screen each brightness channel's readings speak for. The two channels
/// share one source type and one emit line, so the answer cannot come from a
/// `kind` branch there — it is a constant of the technology, declared by the
/// bridge that touches it, and this is where that declaration is pinned
/// (docs/DECISIONS.md: hud-target-is-a-role).
///
/// Both bridges are built with a resolver that finds nothing, so no private API
/// is touched: the target is a constant and does not depend on availability.
struct BrightnessChannelTargetTests {

    @Test func theScreenBridgeSpeaksForTheBuiltInPanel() {
        // DisplayServices governs Apple-controlled panels only, and this bridge
        // resolves the built-in display for every read and write, so its bar
        // describes the internal screen and belongs on that panel alone.
        let bridge = DisplayServicesBridge(displayProvider: { nil }, resolver: { _ in nil })
        #expect(bridge.target == .builtIn)
    }

    @Test func theKeyboardBridgeSpeaksForNoDisplay() {
        // The backlight belongs to the one keyboard; its actuator takes no display
        // at all, so scoping its bar to a panel would hide feedback and buy no aim.
        let bridge = CoreBrightnessKeyboardBridge(resolver: { _ in nil })
        #expect(bridge.target == .noDisplay)
    }
}
