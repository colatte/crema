import Testing
@testable import Crema

/// The graceful-degradation contract: when the private symbol/class is missing
/// (a future macOS moved the API), the real bridges report unavailable and the
/// feature degrades. Tested via the injectable resolver so no real private API
/// is touched (the nil resolver replaces dlopen/dlsym / NSClassFromString).
struct BrightnessBridgeDegradeTests {

    @Test func displayServicesBridgeDegradesWhenSymbolsMissing() {
        let bridge = DisplayServicesBridge(resolver: { _ in nil })
        #expect(!bridge.isAvailable)
        #expect(bridge.read() == nil)
        #expect(bridge.write(0.5) == false)
    }

    @Test func keyboardBridgeDegradesWhenClassMissing() {
        let bridge = CoreBrightnessKeyboardBridge(resolver: { _ in nil })
        #expect(!bridge.isAvailable)
        #expect(bridge.read() == nil)
        #expect(bridge.write(0.5) == false)
    }
}
