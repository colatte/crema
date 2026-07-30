import Foundation
import Testing
@testable import Crema

/// The production wiring of the hand-back seam, which the isolated halves never
/// exercise: the suppressor's suite proves the callback fires, and each sampler's
/// suite proves `standDown()` spends its window, but nothing until here proved that
/// AppCore routes a given key to the RIGHT sampler. Deleting one arm of that switch
/// left the whole suite green — measured — and brought back the double bar for the
/// press that recovers a late-enumerating backlight
/// (docs/DECISIONS.md: absent-capability-hands-the-key-back).
@MainActor
struct AppCoreHandbackWiringTests {

    private final class RecordingSampler: ManuallySampledSource, @unchecked Sendable {
        private let lock = NSLock()
        private var _stoodDown = 0
        var stoodDown: Int { lock.withLock { _stoodDown } }
        func sample() {}
        func standDown() { lock.withLock { _stoodDown += 1 } }
    }

    @Test func eachHandedBackKeyStandsDownItsOwnSamplerAndNoOther() {
        let suppressor = RecordingOSDSuppressor()
        let screen = RecordingSampler()
        let keyboard = RecordingSampler()
        AppCore.wireHandbackStandDown(from: suppressor, screen: screen, keyboard: keyboard)

        suppressor.onHandedBackToTheSystem?(.screenBrightnessUp)
        #expect(screen.stoodDown == 1)
        #expect(keyboard.stoodDown == 0)

        // The arm that a mutation deletes in silence: a backlight key handed back
        // while the keyboard has not enumerated yet must spend the KEYBOARD window,
        // or the poll it armed draws our bar over the indicator macOS just put up.
        suppressor.onHandedBackToTheSystem?(.keyboardBrightnessUp)
        #expect(keyboard.stoodDown == 1)
        #expect(screen.stoodDown == 1)

        // Volume needs nothing: Core Audio is event-driven and the router arms no
        // poll for it, so spending a window here would be spending one that is not
        // open.
        suppressor.onHandedBackToTheSystem?(.volumeUp)
        suppressor.onHandedBackToTheSystem?(.mute)
        #expect(screen.stoodDown == 1)
        #expect(keyboard.stoodDown == 1)
    }
}
