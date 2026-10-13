import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Crema

/// The gate a cover passes before ImageIO decodes it: the bytes are whatever the
/// player published, parsed in the process that holds Accessibility.
struct ArtworkDecodingTests {

    private func encoded(width: Int, height: Int, as type: String) throws -> [UInt8] {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return [UInt8](data as Data)
    }

    @Test func theFormatsPlayersSendDecode() throws {
        for type in ["public.png", "public.jpeg"] {
            let bytes = try encoded(width: 32, height: 32, as: type)
            #expect(ArtworkDecoding.thumbnail(from: bytes, maxSide: 16) != nil, "\(type)")
        }
    }

    @Test func aFormatOutsideTheListIsRefused() throws {
        let tiff = try encoded(width: 32, height: 32, as: "public.tiff")
        #expect(ArtworkDecoding.thumbnail(from: tiff, maxSide: 16) == nil)
    }

    @Test func aSourceWiderThanTheBoundIsRefusedBeforeTheThumbnail() throws {
        let wide = try encoded(width: ArtworkDecoding.maxSourceSide + 1, height: 1, as: "public.png")
        #expect(ArtworkDecoding.thumbnail(from: wide, maxSide: 16) == nil)
    }

    @Test func moreBytesThanTheCeilingAreRefused() throws {
        var padded = try encoded(width: 32, height: 32, as: "public.png")
        padded += [UInt8](repeating: 0, count: ArtworkDecoding.maxBytes + 1 - padded.count)
        #expect(ArtworkDecoding.thumbnail(from: padded, maxSide: 16) == nil)
    }
}
