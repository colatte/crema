import SwiftUI
import Testing
@testable import Crema

/// The one launch-at-login switch both windows carry shows what the attempt
/// returned, never what was asked: the General tab and the tour cannot disagree
/// about it because they hold the same binding.
@MainActor
struct LaunchAtLoginToggleTests {

    private final class Mirrors {
        var isOn = false
        var needsApproval = false
        var asked: [Bool] = []
    }

    private func binding(_ mirrors: Mirrors, returning result: (enabled: Bool, needsApproval: Bool)) -> Binding<Bool> {
        LaunchAtLoginToggle.binding(
            isOn: Binding(get: { mirrors.isOn }, set: { mirrors.isOn = $0 }),
            needsApproval: Binding(get: { mirrors.needsApproval }, set: { mirrors.needsApproval = $0 }),
            apply: { wanted in
                mirrors.asked.append(wanted)
                return result
            }
        )
    }

    @Test func aFailedAttemptSnapsTheSwitchBack() {
        let mirrors = Mirrors()
        binding(mirrors, returning: (enabled: false, needsApproval: false)).wrappedValue = true
        #expect(mirrors.asked == [true])
        #expect(!mirrors.isOn)
        #expect(!mirrors.needsApproval)
    }

    @Test func aPendingApprovalStaysOnWithItsNote() {
        let mirrors = Mirrors()
        binding(mirrors, returning: (enabled: true, needsApproval: true)).wrappedValue = true
        #expect(mirrors.isOn)
        #expect(mirrors.needsApproval)
    }
}
