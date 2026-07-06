import CoreGraphics
import Foundation

/// Screen-brightness border: DisplayServices private framework via dlopen/dlsym
/// (see BrightnessConversion.swift for the full spike rationale, including why
/// CoreDisplay and IOKit were discarded). The symbol resolver is injectable so
/// the "symbol missing → degrade" path is testable without the real framework.
final class DisplayServicesBridge: ScreenBrightnessBackend, @unchecked Sendable {
    typealias SymbolResolver = (_ name: String) -> UnsafeMutableRawPointer?

    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    private let display: UInt32
    private let getFn: GetFn?
    private let setFn: SetFn?

    init(display: UInt32 = CGMainDisplayID(), resolver: SymbolResolver = DisplayServicesBridge.defaultResolver) {
        self.display = display
        getFn = resolver("DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFn.self) }
        setFn = resolver("DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFn.self) }
    }

    /// Both symbols must resolve, or the whole feature degrades.
    var isAvailable: Bool { getFn != nil && setFn != nil }

    func read() -> Float? {
        guard let getFn else { return nil }
        var value: Float = 0
        return getFn(display, &value) == 0 ? value : nil
    }

    func write(_ value: Float) -> Bool {
        guard let setFn else { return false }
        return setFn(display, value) == 0
    }

    static func defaultResolver(_ name: String) -> UnsafeMutableRawPointer? {
        guard let handle = dlopen(frameworkPath, RTLD_NOW) else { return nil }
        return dlsym(handle, name)
    }
}
