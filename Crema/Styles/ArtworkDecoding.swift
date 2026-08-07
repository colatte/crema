import CoreGraphics
import Foundation
import ImageIO

/// Cover decode via ImageIO thumbnailing: `CGImageSourceCreateThumbnailAtIndex`
/// forces an eager decode bounded to `maxSide` pixels — unlike `NSImage(data:)`,
/// which parses the header and defers the full-size bitmap decode to the first
/// main-thread draw (a frame hitch mid-crossfade with real 100–500 KB covers).
/// The result is an immutable CGImage, safe to hand across tasks.
enum ArtworkDecoding {
    /// Comfortably above the largest artwork slot at 2× (88 pt → 176 px), so
    /// the decode is bounded no matter how large the source cover is.
    static let displayMaxSide = 256

    /// The lock screen's own bound. A 300 pt cover at 2× is 600 px, and the
    /// backdrop behind it is the same decode blurred past recognition, so one
    /// image serves both. Kept apart from `displayMaxSide` rather than raising
    /// it: every thumbnail in the app would pay for a size only this surface
    /// needs, and the desktop skins never show artwork above 88 pt.
    static let lockScreenMaxSide = 1024

    static func thumbnail(from bytes: [UInt8]?, maxSide: Int) -> CGImage? {
        guard let bytes,
              let source = CGImageSourceCreateWithData(Data(bytes) as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
