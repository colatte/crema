import CoreGraphics
import Foundation

/// Screen-brightness border: DisplayServices private framework via dlopen/dlsym
/// (see BrightnessConversion.swift for the full spike rationale, including why
/// CoreDisplay and IOKit were discarded). The symbol resolver is injectable so
/// the "symbol missing → degrade" path is testable without the real framework.
final class DisplayServicesBridge: ScreenBrightnessBackend, @unchecked Sendable {
    typealias SymbolResolver = (_ name: String) -> UnsafeMutableRawPointer?
    typealias DisplayProvider = @Sendable () -> UInt32

    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    /// Resolved per operation, never frozen at init: CGDisplayID values are not
    /// stable across display sleep/wake and reconfiguration on modern macOS, and
    /// a captured ID goes stale the first time the main display is re-enumerated
    /// (clamshell, external plug, or a plain wake). Get/SetBrightness against a
    /// stale ID fail, so a launch-frozen ID silently rots the whole brightness
    /// path until relaunch (which is exactly why a restart "cured" it and a
    /// toggle did not). CGMainDisplayID() is a cheap C call, so re-reading it on
    /// every read/write is free and correct across any reconfiguration without
    /// any registration/callback bookkeeping. Injectable so a test can simulate
    /// the ID going stale mid-run.
    private let displayProvider: DisplayProvider
    private let getFn: GetFn?
    private let setFn: SetFn?

    init(
        displayProvider: @escaping DisplayProvider = { CGMainDisplayID() },
        resolver: SymbolResolver = DisplayServicesBridge.defaultResolver
    ) {
        self.displayProvider = displayProvider
        getFn = resolver("DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFn.self) }
        setFn = resolver("DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFn.self) }
    }

    /// Both symbols must resolve, or the whole feature degrades.
    var isAvailable: Bool { getFn != nil && setFn != nil }

    func read() -> Float? {
        guard let getFn else { return nil }
        var value: Float = 0
        return getFn(displayProvider(), &value) == 0 ? value : nil
    }

    func write(_ value: Float) -> Bool {
        guard let setFn else { return false }
        return setFn(displayProvider(), value) == 0
    }

    static func defaultResolver(_ name: String) -> UnsafeMutableRawPointer? {
        guard let handle = dlopen(frameworkPath, RTLD_NOW) else { return nil }
        return dlsym(handle, name)
    }
}
