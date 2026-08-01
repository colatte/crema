/// What the WindowManager needs to know about one connected screen. Built at
/// the AppKit border (ScreenTranslation) from NSScreen/CGDisplay; pure above it.
struct ScreenDescription: Equatable, Sendable {
    /// Stable identity across sessions/reconnections (display UUID).
    var id: DisplayUUID
    /// What AppKit calls this display (`NSScreen.localizedName`), carried
    /// verbatim — the name macOS itself shows for it, which is the only one a
    /// per-display row can use without teaching the user a second vocabulary.
    /// Deliberately without a default: a description built with no name would
    /// reach the UI as an untitled row nobody notices. If the string ever
    /// arrives empty, choosing a stand-in label is the VIEW's job (it needs
    /// localization), never this border's.
    var name: String
    var geometry: ScreenGeometry
    /// Built-in display? Feeds the "show now playing here" default.
    var isInternal: Bool
}
