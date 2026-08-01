import Foundation

/// Capability: where the desktop picture the user is looking at lives on disk.
///
/// Only the URL crosses this line — NSScreen, NSWorkspace and the decoded bitmap
/// all stay on the system side of it. What comes up is a value anything can
/// compare, which is what lets the caching above it (`WallpaperTileStore`) be a
/// unit test instead of a trip to the window server.
///
/// `nil` is an answer, not an error: there may be no screen to ask, and macOS
/// names no file for some desktops. Callers degrade — the style tiles draw their
/// own desk — rather than guess.
@MainActor
protocol DesktopPictureSource {
    func desktopPictureURL() -> URL?
}
