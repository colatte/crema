import Testing
@testable import Crema

/// Pure clamp, mirroring the volume conversion tests.
struct BrightnessConversionTests {

    @Test func normalizePassesThroughInRangeValues() {
        #expect(BrightnessConversion.normalize(0) == 0)
        #expect(BrightnessConversion.normalize(0.42) == Double(Float(0.42)))
        #expect(BrightnessConversion.normalize(1) == 1)
    }

    @Test func normalizeClampsOutOfRangeValues() {
        #expect(BrightnessConversion.normalize(-0.5) == 0)
        #expect(BrightnessConversion.normalize(1.7) == 1)
    }

    @Test func normalizeSanitizesNonFiniteValues() {
        #expect(BrightnessConversion.normalize(.nan) == 0)
        #expect(BrightnessConversion.normalize(.infinity) == 1)
        #expect(BrightnessConversion.normalize(-.infinity) == 0)
    }

    @Test func denormalizeClampsSliderValues() {
        #expect(BrightnessConversion.denormalize(0.7) == 0.7)
        #expect(BrightnessConversion.denormalize(-0.3) == 0)
        #expect(BrightnessConversion.denormalize(1.2) == 1)
    }

    @Test func denormalizeSanitizesNonFiniteValues() {
        #expect(BrightnessConversion.denormalize(.nan) == 0)
        #expect(BrightnessConversion.denormalize(.infinity) == 1)
        #expect(BrightnessConversion.denormalize(-.infinity) == 0)
    }
}
