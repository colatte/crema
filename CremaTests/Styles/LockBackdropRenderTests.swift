import CoreGraphics
import SwiftUI
import Testing
@testable import Crema

/// The one class of defect the metric tests could not see: a rule that is right
/// in arithmetic and never reaches the screen.
///
/// `LockBackdropFadeTests` asserts the numbers and passed unchanged while the
/// clear band was landing 265 pt below the display. Nothing in that file renders
/// anything, so nothing could notice. These do — `ImageRenderer` at the panel's
/// real size, sampling the alpha the compositor would produce.
///
/// The defect they exist for: `Image.resizable().scaledToFill()` reports a layout
/// size LARGER than the proposal, so a square cover on a 1512x982 panel made the
/// backdrop report 1512x1512. A `.mask` lays out at its RECEIVER's size and
/// centres, so the mask went off the bottom of the screen and the clear band with
/// it. Album art is square; the failing case was the normal one.
@MainActor
struct LockBackdropRenderTests {

    /// The panel this surface was designed against, and the one every other
    /// geometry test in the suite uses.
    private static let panel = CGSize(width: 1512, height: 982)

    /// A square cover, because that is what album art is and what broke. Drawn
    /// rather than fetched: the assertion is about geometry, and a real JPEG
    /// would make the test depend on a file.
    private static func squareCover(side: Int) -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()
    }

    /// Renders the masked backdrop over an opaque green ground and returns the
    /// green channel at `pointsFromBottom`. Green showing through IS the clear
    /// band: the backdrop is pure red, so a high green means the mask let the
    /// ground through, and a low one means the backdrop is covering it.
    private static func groundVisible(at pointsFromBottom: CGFloat, cover: CGImage?) -> Int? {
        // An explicit full-channel green, not `Color.green`: the system green is
        // (52, 199, 89) in sRGB, so an assertion of "the ground is fully visible"
        // written against it would have to compare with 199 and would read as a
        // magic number.
        let content = ZStack {
            Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1)
            DriftingArtworkBackground(image: cover, fallbackTone: nil)
                .mask { LoginClearanceProbe() }
        }
        .frame(width: panel.width, height: panel.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        guard let rendered = renderer.cgImage else { return nil }

        let width = rendered.width, height = rendered.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(rendered, in: CGRect(x: 0, y: 0, width: width, height: height))

        // ImageRenderer hands back a top-down bitmap; the metric speaks in points
        // off the BOTTOM, which is the space every frame rule in this app uses.
        let row = height - 1 - Int(pointsFromBottom)
        guard row >= 0, row < height else { return nil }
        let column = width / 2
        return Int(pixels[(row * width + column) * 4 + 1])
    }

    @Test func theClearBandReachesTheScreenWithASquareCover() throws {
        // Fails on the shipped code before the fix (the mask lands 265 pt below
        // the display, so the backdrop covers the ground everywhere), passes
        // after, and dies again if the size-pinning container is removed.
        let cover = try #require(Self.squareCover(side: 1024))
        let atFloor = try #require(
            Self.groundVisible(at: LockWidgetMetrics.clearBandFloor - 1, cover: cover)
        )
        #expect(atFloor > 200, "the login's strip must be clear, green read \(atFloor)")
    }

    @Test func theBackdropStillCoversAboveTheRamp() throws {
        // The other half of the contract, and what stops the fix from becoming
        // "clear everywhere": above the ramp the backdrop is opaque.
        let cover = try #require(Self.squareCover(side: 1024))
        let rampTop = LockWidgetMetrics.clearBandFloor + LockWidgetMetrics.backdropFadeBand
        let above = try #require(Self.groundVisible(at: rampTop + 120, cover: cover))
        #expect(above < 60, "above the ramp the backdrop must cover, green read \(above)")
    }

    @Test func theCoverlessBranchClearsTheSameStrip() throws {
        // It already worked, which is exactly why it is pinned: it is the branch
        // that made the bug invisible in every hand check.
        let atFloor = try #require(
            Self.groundVisible(at: LockWidgetMetrics.clearBandFloor - 1, cover: nil)
        )
        #expect(atFloor > 200, "green read \(atFloor)")
    }

    @Test func aTallCoverDoesNotSwallowTheWholeDisplay() throws {
        // The worst measured case: a 683x1024 cover made the backdrop report
        // 1512x3024 and the mask never intersected the screen at all, so every
        // row was opaque.
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = try #require(CGContext(
            data: nil, width: 683, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 683, height: 1024))
        let tall = try #require(ctx.makeImage())
        let atFloor = try #require(
            Self.groundVisible(at: LockWidgetMetrics.clearBandFloor - 1, cover: tall)
        )
        #expect(atFloor > 200, "green read \(atFloor)")
    }
}

/// A copy of the shipped mask's shape, because `LoginClearance` is private to
/// `LockWidgetView.swift` and making it internal purely for a test would widen
/// production surface for the test's convenience.
///
/// A copy is a divergence risk and it is bounded on purpose: it restates the
/// SHAPE, and both numbers come from `LockWidgetMetrics`, so the values a test
/// could get wrong are the ones the production view reads too.
private struct LoginClearanceProbe: View {
    var body: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.80), location: 0.60),
                    .init(color: .black.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: LockWidgetMetrics.backdropFadeBand)
            Color.clear.frame(height: LockWidgetMetrics.clearBandFloor)
        }
    }
}

// A suite for `ArtworkAccent.extract(from: CGImage)` was written here and then
// deleted, because two mutations proved it could not fail.
//
// The first asserted that the image path AGREES with the bytes path. It cannot
// disagree: the bytes path now delegates to the image path after thumbnailing,
// so they are one implementation and the assertion is a tautology by
// construction — shifting the hue inside the overload left it green, because
// both sides shifted together.
//
// The second asserted that the overload DOWNSAMPLES, comparing a 1024 px source
// against a 128 px one. Mutating `sampleSide` to `image.width` also left it
// green, and the rule explains why: the tone is a weighted mean over hue
// buckets, so it is robust to sample density. Reading a million pixels is a
// COST, not a wrong answer.
//
// What remains is a two-line delegation of a picker `ArtworkAccentTests` already
// covers in eleven cases, including one over a real encoded image. There is no
// failure mode left for a test here to catch, and a test that cannot die is the
// tautology this house refuses (the lesson `FixedWindowFrameTests` carries).
