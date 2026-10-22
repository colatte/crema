import AppKit
import SwiftUI
import Testing
@testable import Crema

/// The recess the Card's glass takes, against the system OSD's own track read
/// off the captures `CapsuleTrack.glassTrack` cites: #45 over a body near #1d
/// on a dark page, #d1 under a #d8 body on a pale one. Pinned as the composite
/// the grey makes over each body, so a retune that drifts off either backdrop
/// fails here rather than on someone's desktop.
struct GlassTrackTests {

    private func composite(over body: Double) throws -> Double {
        let color = try #require(NSColor(CapsuleTrack.glassTrack).usingColorSpace(.deviceGray))
        let alpha = Double(color.alphaComponent)
        return (1 - alpha) * body + alpha * Double(color.whiteComponent) * 255
    }

    @Test func overADarkBodyTheTrackReadsAsTheSystemsDoes() throws {
        #expect(try abs(composite(over: 0x1D) - 0x45) <= 3)
    }

    @Test func overAPaleBodyTheTrackIsAShadeUnderItNotAGroove() throws {
        let track = try composite(over: 0xD8)
        #expect(abs(track - 0xD1) <= 3)
        #expect(track < 0xD8)
    }
}
