import CoreGraphics
import Foundation

/// Screen-brightness border: DisplayServices private framework via dlopen/dlsym
/// (see BrightnessConversion.swift for the full spike rationale, including why
/// CoreDisplay and IOKit were discarded). The symbol resolver is injectable so
/// the "symbol missing → degrade" path is testable without the real framework.
final class DisplayServicesBridge: BrightnessBackend, Sendable {
    typealias SymbolResolver = (_ name: String) -> UnsafeMutableRawPointer?
    /// Nil means "there is no built-in panel attached right now" — clamshell.
    typealias DisplayProvider = @Sendable () -> UInt32?

    // @Sendable on the C function types lets the compiler verify this class's
    // Sendable conformance (all storage is `let`) instead of taking @unchecked.
    private typealias GetFn = @Sendable @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @Sendable @convention(c) (UInt32, Float) -> Int32

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    /// Names the BUILT-IN panel, resolved per operation and never frozen at init.
    ///
    /// Two separate lessons live here. The identity: `display == nil` means the
    /// internal display everywhere else in this app, and `CGMainDisplayID()` means
    /// the display carrying the menu bar — a role the user moves in Settings →
    /// Displays → Arrange, and one an external monitor commonly holds. Measured on
    /// an external: `DisplayServicesGetBrightness` returns 1000, so read() answered
    /// nil and write() false for every key and every drag, silently, with a
    /// perfectly controllable panel sitting right there. The stability: CGDisplayID
    /// values are reassigned across sleep/wake and reconfiguration, so a captured
    /// ID goes stale and rots the path until relaunch (which is why a restart once
    /// "cured" it and a toggle did not).
    ///
    /// Naming the built-in panel is also what makes per-operation resolution
    /// unambiguous rather than a straddle: the identity can no longer change
    /// between the read and the write of one apply-verify cycle, only the numeric
    /// ID standing for it — which re-resolving is precisely how we track. It is a
    /// cheap enumeration, so paying it twice costs nothing and needs no
    /// registration or callback bookkeeping. Injectable so a test can move the ID
    /// mid-run, or take it away entirely.
    private let displayProvider: DisplayProvider
    private let getFn: GetFn?
    private let setFn: SetFn?

    init(
        displayProvider: @escaping DisplayProvider = { ScreenTranslation.builtInDisplayID() },
        resolver: SymbolResolver = DisplayServicesBridge.defaultResolver
    ) {
        self.displayProvider = displayProvider
        getFn = resolver("DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFn.self) }
        setFn = resolver("DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFn.self) }
    }

    /// Both symbols must resolve, or the whole feature degrades.
    var isAvailable: Bool { getFn != nil && setFn != nil }

    /// No built-in panel (clamshell) degrades honestly to nil/false rather than
    /// falling back to whatever display happens to be main — the app promises never
    /// to touch an external panel, and reaching for one here would break that
    /// promise at the exact moment the honest answer costs the user nothing they
    /// can see.
    func read() -> Float? {
        guard let getFn, let display = displayProvider() else { return nil }
        var value: Float = 0
        return getFn(display, &value) == 0 ? value : nil
    }

    func write(_ value: Float) -> Bool {
        guard let setFn, let display = displayProvider() else { return false }
        return setFn(display, value) == 0
    }

    static func defaultResolver(_ name: String) -> UnsafeMutableRawPointer? {
        guard let handle = dlopen(frameworkPath, RTLD_NOW) else { return nil }
        return dlsym(handle, name)
    }
}
