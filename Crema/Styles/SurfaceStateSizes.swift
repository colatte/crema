import CoreGraphics
import SwiftUI

/// Surface size per presentable state, derived from the style's frame rule (the
/// one source of truth for dimensions). The panel injects them so the view sizes
/// its surface within the fixed window instead of filling it: the window never
/// resizes and every visible motion is SwiftUI's, which is what keeps the
/// surface rounded on every frame (see NSPanelPresentationPanel).
struct SurfaceStateSizes: Equatable {
    var compact: CGSize
    var expanded: CGSize
    var hud: CGSize
}

private struct SurfaceStateSizesKey: EnvironmentKey {
    static let defaultValue: SurfaceStateSizes? = nil
}

private struct SurfaceSizeReporterKey: EnvironmentKey {
    static let defaultValue: (@MainActor (CGSize) -> Void)? = nil
}

extension EnvironmentValues {
    /// Nil when no panel injected sizes (the view then fills its container).
    var surfaceStateSizes: SurfaceStateSizes? {
        get { self[SurfaceStateSizesKey.self] }
        set { self[SurfaceStateSizesKey.self] = newValue }
    }

    /// Panel-injected callback reporting the rendered surface size. A
    /// width-hugging surface adapts to content, so the rule frame alone can't
    /// place the click-interactive region — the drawn size is the truth.
    var surfaceSizeReporter: (@MainActor (CGSize) -> Void)? {
        get { self[SurfaceSizeReporterKey.self] }
        set { self[SurfaceSizeReporterKey.self] = newValue }
    }
}
