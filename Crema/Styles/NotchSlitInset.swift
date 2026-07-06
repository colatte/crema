import SwiftUI

private struct NotchSlitInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Height of the physical notch slit (points) on the display this surface
    /// renders on. The notch content insets below it so nothing lands on the
    /// camera's dead-zone pixels; the panel injects it from
    /// `ScreenGeometry.safeTop` (0 off a notched display — the notch style only
    /// renders where it's > 0). This is rendering context, not domain: it flows
    /// down through the environment, so the view stays a pure function of state.
    var notchSlitInset: CGFloat {
        get { self[NotchSlitInsetKey.self] }
        set { self[NotchSlitInsetKey.self] = newValue }
    }
}
