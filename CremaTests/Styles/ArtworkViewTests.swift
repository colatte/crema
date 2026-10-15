import AppKit
import SwiftUI
import Testing
@testable import Crema

/// A cover slot draws; it does not decode (`artworkImage(from:)` does, once per
/// skin).
@MainActor
struct ArtworkViewTests {

    private func solidRedPNG() throws -> [UInt8] {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        image.unlockFocus()
        return try Array(#require(
            image.tiffRepresentation
                .flatMap { NSBitmapImageRep(data: $0) }
                .flatMap { $0.representation(using: .png, properties: [:]) }
        ))
    }

    private func centre(of image: CGImage) -> (red: UInt8, green: UInt8, blue: UInt8) {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(
                x: -CGFloat(image.width / 2), y: -CGFloat(image.height / 2),
                width: CGFloat(image.width), height: CGFloat(image.height)
            ))
        }
        return (pixel[0], pixel[1], pixel[2])
    }

    /// The slot draws the cover its skin decoded above the branches, so a branch
    /// inserted after the decode — HUD to now playing, compact to expanded —
    /// shows the cover in its very first frame instead of the placeholder.
    @Test func aFreshlyInsertedSlotDrawsTheCoverInItsFirstFrame() throws {
        let cover = try #require(ArtworkDecoding.thumbnail(from: solidRedPNG(), maxSide: 40))
        let renderer = ImageRenderer(
            content: ArtworkView(side: 40, cornerRadius: 0).environment(\.artworkImage, cover)
        )
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let pixel = centre(of: image)
        #expect(pixel.red > 200 && pixel.green < 60 && pixel.blue < 60)
    }
}
