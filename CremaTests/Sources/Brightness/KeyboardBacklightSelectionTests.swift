import Testing
@testable import Crema

/// The built-in keyboard is selected by enumeration + filter, never
/// hardcoded. Tested with fake opaque ID lists.
struct KeyboardBacklightSelectionTests {

    @Test func picksTheBuiltInAmongExternals() {
        let selected = KeyboardBacklightSelection.builtInID(from: [10, 95158272, 30]) { $0 == 95158272 }
        #expect(selected == 95158272)
    }

    @Test func returnsNilWhenNoneIsBuiltIn() {
        #expect(KeyboardBacklightSelection.builtInID(from: [10, 20]) { _ in false } == nil)
    }

    @Test func returnsNilForAnEmptyList() {
        #expect(KeyboardBacklightSelection.builtInID(from: []) { _ in true } == nil)
    }
}
