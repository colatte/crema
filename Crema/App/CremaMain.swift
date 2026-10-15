import Foundation
import SwiftUI

/// The entry point. The unit tests run hosted inside Crema.app (TEST_HOST), so
/// without this fork every suite run would boot the live graph behind them: the
/// event tap, the screen and wake observers, the adapter process, the launch
/// writes to the user's defaults and the first-launch tour, all under the tests
/// that exist so nothing touches a real system API.
///
/// The host is told by `XCTestConfigurationFilePath`, which xcodebuild puts in
/// the hosted process's environment (present, and empty, in a command-line run;
/// read from a probe in this suite's host). Debug only: tests run the Debug
/// configuration, and Release launches the app with no branch to take.
@main
enum CremaMain {
    @MainActor
    static func main() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            UnitTestHostApp.main()
            return
        }
        #endif
        CremaApp.main()
    }
}

#if DEBUG
/// What the unit-test host runs instead of the app: a scene SwiftUI accepts and
/// nothing behind it — no AppCore, so no tap, no observers, no panels and no
/// defaults writes.
private struct UnitTestHostApp: App {
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
#endif
