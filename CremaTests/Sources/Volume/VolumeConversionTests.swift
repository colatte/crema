import Testing
@testable import Crema

/// Pure conversions between raw Core Audio values and the domain's
/// 0...1. The border itself is manual-smoke; everything testable lives here.
struct VolumeConversionTests {

    // MARK: - System value → domain (normalize + defensive clamp)

    @Test func normalizePassesThroughInRangeValues() {
        #expect(VolumeConversion.normalize(0) == 0)
        // The raw value is Float32; the domain Double carries Float precision.
        #expect(VolumeConversion.normalize(0.42) == Double(Float(0.42)))
        #expect(VolumeConversion.normalize(1) == 1)
    }

    @Test func normalizeClampsOutOfRangeValues() {
        // If the system ever reports outside 0...1, the domain never sees it.
        #expect(VolumeConversion.normalize(-0.5) == 0)
        #expect(VolumeConversion.normalize(1.7) == 1)
    }

    @Test func normalizeSanitizesNonFiniteValues() {
        #expect(VolumeConversion.normalize(.nan) == 0)
        #expect(VolumeConversion.normalize(.infinity) == 1)
        #expect(VolumeConversion.normalize(-.infinity) == 0)
    }

    // MARK: - Domain/slider → system value (same clamp on the way back)

    @Test func denormalizeClampsSliderValues() {
        #expect(VolumeConversion.denormalize(0.7) == 0.7)
        #expect(VolumeConversion.denormalize(-0.3) == 0)
        #expect(VolumeConversion.denormalize(1.2) == 1)
    }

    @Test func denormalizeSanitizesNonFiniteValues() {
        #expect(VolumeConversion.denormalize(.nan) == 0)
        #expect(VolumeConversion.denormalize(.infinity) == 1)
        #expect(VolumeConversion.denormalize(-.infinity) == 0)
    }

    @Test func roundTripPreservesInRangeValues() {
        for value: Float in [0, 0.25, 0.5, 1] {
            #expect(VolumeConversion.denormalize(VolumeConversion.normalize(value)) == value)
        }
    }

    // MARK: - Raw readings → SystemHUD

    @Test func hudMapsRawReadingsToTheVolumeKind() {
        let hud = VolumeConversion.hud(rawVolume: 0.8, isMuted: false)
        #expect(hud.kind == .volume)
        #expect(hud.value == Double(Float(0.8)))
        #expect(!hud.isMuted)
        #expect(hud.display == nil)
    }

    @Test func hudPassesMuteThroughAndStillClampsValue() {
        let muted = VolumeConversion.hud(rawVolume: 1.7, isMuted: true)
        #expect(muted.isMuted)
        #expect(muted.value == 1)
    }
}
