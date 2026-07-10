import CoreGraphics
import Foundation

/// The CGEventTap primitives the media-key source needs, behind a protocol so
/// the install / health-check / revive decisions are unit-testable without a
/// real tap (mirrors the injectable `SymbolResolver` in DisplayServicesBridge).
///
/// The returned token is opaque: it bundles the mach port and its run-loop
/// source, and only the live implementation knows their concrete types. The
/// source stores the token and hands it back for every subsequent operation.
protocol EventTapOperating: Sendable {
    /// Creates the tap, wires its run-loop source, enables it, and returns an
    /// opaque token. Nil means creation failed (retry later).
    func install(
        mask: CGEventMask,
        callback: @escaping CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer
    ) -> AnyObject?
    /// Whether the tap is currently enabled. The system can disable a consuming
    /// tap (timeout, secure-input transitions) without a delivered callback, so
    /// the source polls this rather than trusting install state.
    func isEnabled(_ token: AnyObject) -> Bool
    func setEnabled(_ token: AnyObject, _ enabled: Bool)
    func uninstall(_ token: AnyObject)
}

/// The real CoreGraphics-backed tap operations.
struct LiveEventTapOperating: EventTapOperating {
    /// Bundles the port with its run-loop source so the source treats the pair
    /// as one opaque handle; keeps CGEventTap types out of the source's state.
    private final class Token {
        let port: CFMachPort
        let source: CFRunLoopSource
        init(port: CFMachPort, source: CFRunLoopSource) {
            self.port = port
            self.source = source
        }
    }

    func install(
        mask: CGEventMask,
        callback: @escaping CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer
    ) -> AnyObject? {
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        ) else { return nil }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return nil
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return Token(port: port, source: source)
    }

    func isEnabled(_ token: AnyObject) -> Bool {
        guard let token = token as? Token else { return false }
        return CGEvent.tapIsEnabled(tap: token.port)
    }

    func setEnabled(_ token: AnyObject, _ enabled: Bool) {
        guard let token = token as? Token else { return }
        CGEvent.tapEnable(tap: token.port, enable: enabled)
    }

    func uninstall(_ token: AnyObject) {
        guard let token = token as? Token else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), token.source, .commonModes)
        CGEvent.tapEnable(tap: token.port, enable: false)
        CFMachPortInvalidate(token.port)
    }
}
