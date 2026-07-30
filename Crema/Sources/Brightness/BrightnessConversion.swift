// Brightness border — knowledge captured from the throwaway spike (spikes/
// was deleted; this is the durable record):
//   • Screen read/write: DisplayServicesGetBrightness / DisplayServicesSetBrightness
//     (DisplayServices.framework, PrivateFrameworks) via dlopen + dlsym.
//   • Keyboard read/write: KeyboardBrightnessClient (CoreBrightness.framework,
//     PrivateFrameworks) via dlopen + ObjC runtime.
//   • Discarded after empirical testing on macOS 26 / Apple Silicon — do not
//     use: CoreDisplay (CoreDisplay_Display_GetUserBrightness returns a fixed
//     1.0, wrong semantics) and IOKit IODisplayGetFloatParameter (service dead
//     on Apple Silicon). Both proven not to work on this hardware.
//   • The keyboard ID is opaque and varies per machine — it is enumerated via
//     copyKeyboardBacklightIDs + isKeyboardBuiltIn:, never hardcoded.
//   • Every private-symbol lookup is checked: a nil dlsym / missing ObjC class
//     means the backend reports unavailable and the feature degrades — no crash.

/// Pure conversions between the raw private-API float and the domain's 0...1,
/// mirroring VolumeConversion. Same defensive clamp: the domain never receives
/// a value outside 0...1, even if the system reports NaN/±inf.
enum BrightnessConversion {
    /// Raw system value → domain value. Non-finite input degrades to 0.
    static func normalize(_ raw: Float) -> Double {
        guard !raw.isNaN else { return 0 }
        return Double(min(max(raw, 0), 1))
    }

    /// Domain/slider value → value for the system, same defensive clamp.
    static func denormalize(_ value: Double) -> Float {
        guard !value.isNaN else { return 0 }
        return Float(min(max(value, 0), 1))
    }
}
