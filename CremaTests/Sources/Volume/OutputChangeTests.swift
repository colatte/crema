import Testing
@testable import Crema

/// The volume source sends every Core Audio notification through
/// `OutputChange.popsHUD`; the notifications themselves are Core Audio's and
/// untestable here, so the rule is pinned where it is decided.
struct OutputChangeTests {

    @Test func onlyALevelChangePopsTheHUD() {
        // A device switch and a data-source change are the sound moving, not the
        // user turning it up: neither may pop the HUD by itself.
        #expect(OutputChange.allCases.filter(\.popsHUD) == [.level])
    }
}
