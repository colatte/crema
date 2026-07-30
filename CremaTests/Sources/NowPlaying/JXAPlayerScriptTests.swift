import Testing
@testable import Crema

/// The player list and the script that talks to them are one source or they are a
/// lie: Settings NAMES these apps and the Automation check asks macOS about them,
/// so a name here the preamble never attempts would promise an app the backup
/// reader does not script — and an app the script attempts without an entry here
/// would never have its consent checked.
struct JXAPlayerScriptTests {

    @Test func everyPlayerTheAppNamesIsOneTheScriptActuallyAttempts() {
        for player in JXAPlayerScript.players {
            #expect(JXAPlayerScript.preamble.contains("attempt('\(player.name)'"))
        }
    }

    @Test func theScriptAttemptsNoPlayerTheAppDoesNotName() {
        let attempts = JXAPlayerScript.preamble.components(separatedBy: "attempt('").count - 1
        #expect(attempts == JXAPlayerScript.players.count)
    }

    @Test func everyNamedPlayerCarriesTheBundleIDConsentIsAskedFor() {
        #expect(JXAPlayerScript.players.map(\.bundleID) == ["com.spotify.client", "com.apple.Music"])
    }
}
