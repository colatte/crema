import Foundation
@testable import Crema

/// Test double for the desktop-picture border: the test says which file the
/// system is currently reporting, including "no answer at all" — there may be no
/// screen to ask, and some desktops name no file.
///
/// `@MainActor` like the protocol it stands in for, because the real one reads
/// NSScreen; the tests drive it directly.
@MainActor
final class MockDesktopPictureSource: DesktopPictureSource {
    /// What the border reports on the next ask. Assignable mid-test: a user
    /// changing the wallpaper IS this value changing.
    var url: URL?

    /// How many times the store asked. The cache may remember the ANSWER; a
    /// store that stopped asking the QUESTION could never notice a new picture,
    /// and no assertion about the drawn image can tell those two apart.
    private(set) var callCount = 0

    init(url: URL? = nil) {
        self.url = url
    }

    func desktopPictureURL() -> URL? {
        callCount += 1
        return url
    }
}
