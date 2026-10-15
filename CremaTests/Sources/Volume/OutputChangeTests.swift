import Testing
@testable import Crema

/// The volume source sends every Core Audio notification through
/// `OutputChange.popsHUD`; the notifications themselves are Core Audio's and
/// untestable here, so the rule is pinned where it is decided.
struct OutputChangeTests {

    @Test func onlyALevelChangePopsTheHUD() {
        #expect(OutputChange.allCases.filter(\.popsHUD) == [.level])
    }

    @Test func aDeviceSwitchNeverPopsTheHUD() {
        #expect(!OutputChange.defaultDevice.popsHUD)
    }

    @Test func aDataSourceChangeNeverPopsTheHUD() {
        #expect(!OutputChange.dataSource.popsHUD)
    }
}
