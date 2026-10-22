import CoreGraphics
import SwiftUI
import Testing
@testable import Crema

/// Where the knob is DRAWN, read off a render: at an empty level it sits at the
/// bar's start, which is the right end of a right-to-left bar. Drawing
/// coordinates mirror under right-to-left where pointer coordinates do not
/// (`CapsuleTrack.drawnReversed`), so a knob placed by the pointer's rule lands at
/// the far end there.
@MainActor
struct CapsuleTrackKnobRenderTests {

    private let width = 200

    /// The knob's horizontal extent in a row above the 4 pt track, where only the
    /// 14 pt knob draws.
    private func knobSpan(_ direction: LayoutDirection) throws -> ClosedRange<Int> {
        let renderer = ImageRenderer(
            content: CapsuleTrack(value: 0, showsKnob: true)
                .frame(width: CGFloat(width), height: CapsuleTrack.trackHitHeight)
                .environment(\.layoutDirection, direction)
        )
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let row = 3
        let drawn = (0..<image.width).filter { pixels[(row * image.width + $0) * 4 + 3] > 128 }
        let first = try #require(drawn.first), last = try #require(drawn.last)
        return first...last
    }

    @Test func anEmptyBarDrawsItsKnobAtItsStartInEitherLanguage() throws {
        let leftToRight = try knobSpan(.leftToRight)
        let rightToLeft = try knobSpan(.rightToLeft)
        #expect(leftToRight.upperBound < width / 4, "\(leftToRight)")
        #expect(rightToLeft.lowerBound > width * 3 / 4, "\(rightToLeft)")
    }
}
