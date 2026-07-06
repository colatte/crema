/// What the WindowManager needs to know about one connected screen. Built at
/// the AppKit border (ScreenTranslation) from NSScreen/CGDisplay; pure above it.
struct ScreenDescription: Equatable, Sendable {
    /// Stable identity across sessions/reconnections (display UUID).
    var id: DisplayUUID
    var geometry: ScreenGeometry
    /// Built-in display? Feeds the "show now playing here" default.
    var isInternal: Bool
}
