import CoreGraphics
import Foundation
import ImageIO

/// Cover decode via ImageIO thumbnailing, bounded to `maxSide` pixels and
/// finished before the image is handed back — unlike `NSImage(data:)`, which
/// parses the header and defers the full-size bitmap decode to the first
/// main-thread draw (a frame hitch mid-crossfade with real 100–500 KB covers).
/// The result is an immutable CGImage, safe to hand across tasks.
///
/// The bound and the eagerness are two different options, and only the bound is
/// free. `kCGImageSourceShouldCacheImmediately` defaults to FALSE — ImageIO's
/// own header says "image decoding will happen at rendering time" — so a
/// thumbnail requested without it comes back correctly sized and still
/// undecoded, and the pixels land on whichever thread draws it. That is the main
/// thread, which is exactly the hitch this type exists to avoid, and it would
/// have made the `blockingCall` hop around every caller decorative: the hop
/// would move the PARSE off the main actor and leave the decode behind.
enum ArtworkDecoding {
    /// Comfortably above the largest artwork slot at 2× (88 pt → 176 px), so
    /// the decode is bounded no matter how large the source cover is.
    static let displayMaxSide = 256

    static func thumbnail(from bytes: [UInt8]?, maxSide: Int) -> CGImage? {
        guard let bytes,
              let source = CGImageSourceCreateWithData(Data(bytes) as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // The line that makes the off-main hop mean something (see above).
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
