import AppKit
import ImageIO

/// The desktop picture behind the style tiles, read once per file.
///
/// A wallpaper is a several-megapixel file and a tile is 108 pt of it, so the
/// price of the picture is the decode — bounded to a thumbnail, and paid once
/// per URL. Same file, same answer, no second read; and a read that FAILED is
/// remembered exactly like one that succeeded, because a view body runs whenever
/// SwiftUI decides to and an unreadable desktop would otherwise be re-opened on
/// every one of them.
///
/// Main actor with a synchronous decode, by design: the tiles seed this at view
/// construction — which SwiftUI repeats per tab visit, not once per window — so
/// what keeps the repeat cheap is the cache above (a re-seed on an unchanged
/// desktop is a URL read plus a dictionary hit, never a decode). The consequence
/// is the deal the Settings mirrors already take — a wallpaper changed while the
/// window is open shows up on the next construction that finds a new URL.
///
/// `nil` means "draw the fallback desk" (`TileBackdrop.fallback`) and never means
/// "draw the last one": when the border has no answer, the remembered image stays
/// in the cache but is not returned — a picture of a desk the app can no longer
/// confirm is a picture of nothing.
@MainActor
final class WallpaperTileStore {
    private let source: any DesktopPictureSource
    private let loadImage: @MainActor (URL) -> NSImage?

    /// The two halves of one cache: which file was answered for, and the answer
    /// itself — nil included, which is what keeps a failure from being retried.
    private var cachedURL: URL?
    private var cachedImage: NSImage?

    init(
        source: (any DesktopPictureSource)? = nil,
        loadImage: (@MainActor (URL) -> NSImage?)? = nil
    ) {
        // Built here rather than as default arguments: a default argument is
        // evaluated in a NONISOLATED context, and both of these are main-actor
        // bound (the source reads NSScreen) — the same reason AppCore builds its
        // login item inside init.
        self.source = source ?? WorkspaceDesktopPictureSource()
        self.loadImage = loadImage ?? Self.thumbnail(at:)
    }

    /// The picture to put behind a tile, or nil to draw the fallback desk.
    func backdrop() -> NSImage? {
        // The border is asked every time: the answer is what is worth caching,
        // never the question — a wallpaper the user just changed is a different
        // URL, and a store that stopped asking could not see it.
        guard let url = source.desktopPictureURL() else { return nil }
        if url != cachedURL {
            cachedURL = url
            cachedImage = loadImage(url)
        }
        return cachedImage
    }

    /// Roughly twice the tile's 108 pt width, so a 2× display gets a sharp
    /// picture and not one pixel more is decoded. The point is the ceiling
    /// itself: without it a 6K desktop becomes a full-size bitmap in memory to
    /// draw a thumbnail of.
    static let thumbnailMaxPixelSize = 220

    /// Production decode. `CGImageSourceCreateThumbnailAtIndex` forces an eager
    /// decode bounded to `thumbnailMaxPixelSize`, where `NSImage(contentsOf:)`
    /// would hand back a lazy full-size image whose real cost lands on the first
    /// draw, on the main thread, inside the Settings window — the same reason
    /// cover art is decoded this way (`ArtworkDecoding`).
    ///
    /// Failure is silent by contract: a dynamic or aerial desktop, or a file that
    /// moved, is one the tiles draw their own desk for.
    static func thumbnail(at url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
