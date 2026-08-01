import Observation
import SwiftUI

/// Low Power Mode as the surfaces read it: a reference box the panel injects into
/// its view, rendering context like the slit inset and the display policy — never
/// domain state. It lives here rather than in `App/` because the skins are what
/// read it, and a style must never have to name a type from the composition root.
///
/// The write is guarded because the source emits a reading on every power-state
/// edge, and the system posts one for any power-source change — the charger going
/// in or out with Low Power Mode untouched. An unchanged write to an @Observable
/// property still rebuilds every view reading it, and the reader here is a surface
/// that redraws over the menu bar.
@Observable
@MainActor
final class LowPowerModeMirror {
    private(set) var isLowPower = false

    func report(_ lowPower: Bool) {
        if lowPower != isLowPower { isLowPower = lowPower }
    }
}

private struct LowPowerModeKey: EnvironmentKey {
    static let defaultValue: LowPowerModeMirror? = nil
}

extension EnvironmentValues {
    /// The Low Power Mode mirror for this surface; nil means nobody wired one, which
    /// reads as no veto — deliberately not a default instance, which would be a
    /// second mirror nothing ever reports into.
    var lowPowerMode: LowPowerModeMirror? {
        get { self[LowPowerModeKey.self] }
        set { self[LowPowerModeKey.self] = newValue }
    }
}
