import AppKit

/// The desktop picture as NSWorkspace reports it. Thin border: it asks AppKit
/// for one URL and hands it up untouched.
///
/// ONE screen, deliberately — `NSScreen.main` (the one with the key window, so
/// the desk around the Settings window the user is reading), falling back to the
/// first connected display when nothing is key. The picture behind a style tile
/// is SCENERY, not a claim about a particular display: the tile shows a style
/// declared for every screen, so asking each display for its own wallpaper would
/// answer a question nobody asked and force a per-tile choice that means nothing.
/// Reopening gate: the day a tile NAMES a display — a per-display preview — the
/// picture stops being scenery and becomes a claim about that screen, and this
/// takes the display as an argument.
///
/// The URL can point at something ImageIO will not open (a dynamic or aerial
/// desktop). Nothing is done about it here: this reports what the system says,
/// and the decode above treats "unreadable" exactly like "no answer".
struct WorkspaceDesktopPictureSource: DesktopPictureSource {
    func desktopPictureURL() -> URL? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)
    }
}
