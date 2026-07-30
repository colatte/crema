import Foundation
import ObjectiveC.runtime

/// Keyboard-backlight border: CoreBrightness's private `KeyboardBrightnessClient`
/// via dlopen + the ObjC runtime (see BrightnessConversion.swift for the spike
/// rationale). The class resolver is injectable so the "class missing → degrade"
/// path is testable without instantiating the real client. The built-in
/// keyboard ID is enumerated (copyKeyboardBacklightIDs + isKeyboardBuiltIn:),
/// never hardcoded — and re-enumerated per operation, never frozen at init:
/// the IDs live on the other side of the client's connection, and a frozen one
/// is the display bridge's stale-ID death waiting on the keyboard path
/// (docs/DECISIONS.md: J2-display-id-stale — this closes the latent sibling it
/// names). One enumeration per operation at key-press cadence is negligible.
/// The injectable provider lets a test freeze the ID and reproduce the death.
final class CoreBrightnessKeyboardBridge: BrightnessBackend, @unchecked Sendable {
    typealias ClassResolver = (_ name: String) -> AnyClass?
    typealias KeyboardIDProvider = () -> UInt64?

    private typealias GetFn = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetFn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    // `copy`-family method returns +1; take it as Unmanaged and consume the
    // retain, or ARC (assuming +0 for a C pointer) would leak one retention.
    private typealias CopyFn = @convention(c) (AnyObject, Selector) -> Unmanaged<NSArray>?
    private typealias BuiltInFn = @convention(c) (AnyObject, Selector, UInt64) -> Bool

    private struct Resolved {
        let client: NSObject
        let getSel: Selector
        let setSel: Selector
        let getFn: GetFn
        let setFn: SetFn
        let keyboardID: KeyboardIDProvider
    }

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"

    private let resolved: Resolved?

    init(
        resolver: ClassResolver = CoreBrightnessKeyboardBridge.defaultResolver,
        keyboardIDProvider: KeyboardIDProvider? = nil
    ) {
        resolved = Self.resolve(resolver, keyboardIDProvider: keyboardIDProvider)
    }

    /// The backlight belongs to the one keyboard, not to a screen, so its bar is a
    /// control for no display and must keep appearing on all of them — its
    /// actuator does not even take a display. This is why the target is a property
    /// of the BACKEND and not a branch on the HUD kind: both channels share one
    /// source type and one emit line (docs/DECISIONS.md: hud-target-is-a-role).
    var target: SystemHUD.Target { .noDisplay }

    /// Available only when the class resolved and a built-in keyboard was found.
    var isAvailable: Bool { resolved != nil }

    func read() -> Float? {
        guard let r = resolved, let id = r.keyboardID() else { return nil }
        let value = r.getFn(r.client, r.getSel, id)
        return value >= 0 ? value : nil
    }

    func write(_ value: Float) -> Bool {
        guard let r = resolved, let id = r.keyboardID() else { return false }
        return r.setFn(r.client, r.setSel, value, id)
    }

    static func defaultResolver(_ name: String) -> AnyClass? {
        _ = dlopen(frameworkPath, RTLD_NOW)   // ensures the class is registered
        return NSClassFromString(name)
    }

    private static func resolve(
        _ resolver: ClassResolver,
        keyboardIDProvider: KeyboardIDProvider?
    ) -> Resolved? {
        guard let cls = resolver("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        let client = cls.init()

        let getSel = NSSelectorFromString("brightnessForKeyboard:")
        let setSel = NSSelectorFromString("setBrightness:forKeyboard:")
        let copySel = NSSelectorFromString("copyKeyboardBacklightIDs")
        let builtInSel = NSSelectorFromString("isKeyboardBuiltIn:")
        guard client.responds(to: getSel), client.responds(to: setSel),
              client.responds(to: copySel), client.responds(to: builtInSel)
        else { return nil }

        // The responds(to:) guard above proves each selector exists, so
        // client.method(for:) is guaranteed non-nil here.
        // swiftlint:disable force_unwrapping
        let copyFn = unsafeBitCast(client.method(for: copySel)!, to: CopyFn.self)
        let builtInFn = unsafeBitCast(client.method(for: builtInSel)!, to: BuiltInFn.self)

        let enumerate: KeyboardIDProvider = {
            let idsArray = copyFn(client, copySel)?.takeRetainedValue()
            let ids = (idsArray as? [NSNumber])?.map(\.uint64Value) ?? []
            return KeyboardBacklightSelection.builtInID(from: ids) {
                builtInFn(client, builtInSel, $0)
            }
        }
        let provider = keyboardIDProvider ?? enumerate
        // Availability still requires a built-in keyboard NOW; operations
        // re-resolve, so a later change degrades per call, never fatally.
        guard provider() != nil else { return nil }

        return Resolved(
            client: client,
            getSel: getSel,
            setSel: setSel,
            getFn: unsafeBitCast(client.method(for: getSel)!, to: GetFn.self),
            setFn: unsafeBitCast(client.method(for: setSel)!, to: SetFn.self),
            keyboardID: provider
        )
        // swiftlint:enable force_unwrapping
    }
}
