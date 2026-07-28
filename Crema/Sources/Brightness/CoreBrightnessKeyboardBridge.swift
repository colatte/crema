import Foundation
import ObjectiveC.runtime

/// Keyboard-backlight border: CoreBrightness's private `KeyboardBrightnessClient`
/// via dlopen + the ObjC runtime (see BrightnessConversion.swift for the spike
/// rationale). The class resolver is injectable so the "class missing → degrade"
/// path is testable without instantiating the real client. The built-in
/// keyboard ID is enumerated (copyKeyboardBacklightIDs + isKeyboardBuiltIn:),
/// never hardcoded.
final class CoreBrightnessKeyboardBridge: BrightnessBackend, @unchecked Sendable {
    typealias ClassResolver = (_ name: String) -> AnyClass?

    private typealias GetFn = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetFn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    // `copy`-family method returns +1; take it as Unmanaged and consume the
    // retain, or ARC (assuming +0 for a C pointer) would leak one retention.
    private typealias CopyFn = @convention(c) (AnyObject, Selector) -> Unmanaged<NSArray>?
    private typealias BuiltInFn = @convention(c) (AnyObject, Selector, UInt64) -> Bool

    private struct Resolved {
        let client: NSObject
        let keyboardID: UInt64
        let getSel: Selector
        let setSel: Selector
        let getFn: GetFn
        let setFn: SetFn
    }

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"

    private let resolved: Resolved?

    init(resolver: ClassResolver = CoreBrightnessKeyboardBridge.defaultResolver) {
        resolved = Self.resolve(resolver)
    }

    /// Available only when the class resolved and a built-in keyboard was found.
    var isAvailable: Bool { resolved != nil }

    func read() -> Float? {
        guard let r = resolved else { return nil }
        let value = r.getFn(r.client, r.getSel, r.keyboardID)
        return value >= 0 ? value : nil
    }

    func write(_ value: Float) -> Bool {
        guard let r = resolved else { return false }
        return r.setFn(r.client, r.setSel, value, r.keyboardID)
    }

    static func defaultResolver(_ name: String) -> AnyClass? {
        _ = dlopen(frameworkPath, RTLD_NOW)   // ensures the class is registered
        return NSClassFromString(name)
    }

    private static func resolve(_ resolver: ClassResolver) -> Resolved? {
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

        let idsArray = copyFn(client, copySel)?.takeRetainedValue()
        let ids = (idsArray as? [NSNumber])?.map(\.uint64Value) ?? []
        guard let keyboardID = KeyboardBacklightSelection.builtInID(from: ids, isBuiltIn: {
            builtInFn(client, builtInSel, $0)
        }) else { return nil }

        return Resolved(
            client: client,
            keyboardID: keyboardID,
            getSel: getSel,
            setSel: setSel,
            getFn: unsafeBitCast(client.method(for: getSel)!, to: GetFn.self),
            setFn: unsafeBitCast(client.method(for: setSel)!, to: SetFn.self)
        )
        // swiftlint:enable force_unwrapping
    }
}
