import CoreGraphics
import SwiftUI
import Testing
@testable import Crema

/// The filled bar's remainder, read off a render: on the Card's glass it is the
/// glass itself, and on any other surface it is drawn, whatever the system
/// offers. Settings' indicator tiles draw it on a flat stand-in, never on glass
/// (docs/DECISIONS.md: the-card-is-glass).
@MainActor
struct HUDFilledRemainderRenderTests {

    /// The alpha a half-full bar draws three quarters along, in its remainder.
    /// Half full, not empty: rendered one after another in one process, an empty
    /// bar comes back drawn as the render before it was.
    private func remainderAlpha(onGlass: Bool) throws -> UInt8 {
        let width = 120, height = 20
        let renderer = ImageRenderer(
            content: HUDLevelSlider(kind: .volume, value: 0.5, onChange: { _ in }, onRelease: {}, appearance: .filled)
                .frame(width: CGFloat(width), height: CGFloat(height))
                .environment(\.surfaceIsGlass, onGlass)
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
        return pixels[((image.height / 2) * image.width + image.width * 3 / 4) * 4 + 3]
    }

    @Test func theRemainderIsDrawnOffTheGlassAndIsTheGlassOnIt() throws {
        #expect(try remainderAlpha(onGlass: false) > 0)
        #expect(try remainderAlpha(onGlass: true) == 0)
    }
}
