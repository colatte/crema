import Foundation
import Testing
@testable import Crema

/// Pins Crema's Sparkle wiring — the seams we own, not the framework. The tests
/// run in Debug (the only config the suite builds), where the updater is never
/// constructed and cannot contact the feed; the plist assertions read the merged
/// Info.plist of the host app (Bundle.main is the real Crema.app).
struct SparkleUpdaterTests {

    // MARK: - Info.plist merge (build-config independent)

    /// The partial Info.plist merges into the generated one, so both Sparkle keys
    /// reach the shipped bundle with the exact feed URL and public EdDSA key. A
    /// regressed merge (dropped INFOPLIST_FILE, wrong values) fails here loudly.
    @Test func infoPlistCarriesFeedURL() {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        #expect(feed == "https://vctorgriggi.github.io/crema/appcast.xml")
    }

    @Test func infoPlistCarriesPublicEDKey() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        #expect(key == "AWufPX9SoMRSSmTVmoLNaoXyHJuRHOKx+BxrSfazfmQ=")
    }

    /// The consent defaults stay untouched: Sparkle owns the automatic-check
    /// prompt (asked on the second launch) and install requires a user click, so
    /// we ship neither key in the partial plist.
    @Test func consentDefaultsAreNotBaked() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") == nil)
        #expect(Bundle.main.object(forInfoDictionaryKey: "SUAutomaticallyUpdate") == nil)
    }

    /// The generated keys the merge must preserve — a botched merge that replaced
    /// rather than merged the plist would drop these.
    @Test func infoPlistPreservesGeneratedKeys() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true)
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Crema")
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == "1.1.0")
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String == "com.colatte.crema")
    }

    // MARK: - Updater build-config contract

    /// The pure seam: dev builds ship no updater. `isSupported` is the compile-time
    /// source of truth the menu mirrors, and a Debug-built model holds no
    /// controller, so it can never check.
    @MainActor
    @Test func updaterIsAbsentInDebugBuilds() {
        #expect(UpdaterModel.isSupported == false)
        let model = UpdaterModel()
        #expect(model.canCheckForUpdates == false)
    }

    // MARK: - Menu string

    @Test func checkForUpdatesStringResolvesPerLanguage() throws {
        func value(_ key: String, in language: String) throws -> String {
            let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            return bundle.localizedString(forKey: key, value: "«missing»", table: nil)
        }
        #expect(try value("menu.checkForUpdates", in: "en") == "Check for Updates…")
        #expect(try value("menu.checkForUpdates", in: "pt-BR") == "Buscar Atualizações…")
    }
}
