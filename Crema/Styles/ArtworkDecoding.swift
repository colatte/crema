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

    /// What a cover may be before ImageIO decodes it. The bytes are whatever the
    /// player published (any app, and websites when browser media is on), parsed
    /// inside the process that holds Accessibility, so the gate narrows which
    /// parsers they reach and how much they hand them: a known still format, a
    /// byte ceiling, and pixel sides read from the header before the thumbnail is
    /// asked for. A cover outside it shows the placeholder. WebP stays out on
    /// purpose: no player observed here sends it, and it is a parser to keep closed.
    static let allowedTypes: Set<String> = ["public.jpeg", "public.png", "public.heic", "public.heif"]
    static let maxBytes = 4 * 1024 * 1024
    static let maxSourceSide = 4096

    static func thumbnail(from bytes: [UInt8]?, maxSide: Int) -> CGImage? {
        guard let bytes, bytes.count <= maxBytes,
              let source = CGImageSourceCreateWithData(Data(bytes) as CFData, nil),
              let type = CGImageSourceGetType(source) as String?, allowedTypes.contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...maxSourceSide).contains(width), (1...maxSourceSide).contains(height) else {
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
