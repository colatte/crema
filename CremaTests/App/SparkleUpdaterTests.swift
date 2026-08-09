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
    /// This pins plist-vs-expectation COHERENCE, not reachability — whether the
    /// host actually serves the feed is proved by curl in the release ritual.
    @Test func infoPlistCarriesFeedURL() {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        #expect(feed == "https://colatte.github.io/crema/appcast.xml")
    }

    @Test func infoPlistCarriesPublicEDKey() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        #expect(key == "AWufPX9SoMRSSmTVmoLNaoXyHJuRHOKx+BxrSfazfmQ=")
    }

    /// Crema ships a DMG, and Sparkle's disk-image unarchiver does not force
    /// prevalidation on its own: dropped, this key sends the downloaded image to
    /// hdiutil BEFORE its EdDSA signature is checked. Nothing in the build fails when
    /// it goes missing — the update still installs — so the plist is where it gets
    /// caught.
    @Test func infoPlistVerifiesUpdatesBeforeExtraction() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool == true)
    }

    /// The feed itself is signed, not only the enclosure, so a served appcast cannot
    /// lie about which version is newest. Two halves, and the second is not decoration:
    /// Sparkle refuses to START the updater when this key is on without
    /// SUVerifyUpdateBeforeExtraction, which would take the whole update cycle down.
    @Test func infoPlistRequiresASignedFeed() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "SURequireSignedFeed") as? Bool == true)
        #expect(Bundle.main.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool == true)
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
        // Shape, not literal: release.sh stamps the shipping version by CLI, so a
        // literal here would pin the pbxproj's stale number and go red on a bump.
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        #expect(version?.wholeMatch(of: /\d+\.\d+\.\d+/) != nil)
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String == "com.colatte.crema")
    }

    // MARK: - Updater build-config contract

    /// The pure seam: dev builds ship no updater. `isSupported` is the compile-time
    /// source of truth the menu mirrors, and a Debug-built model holds no
    /// controller, so it can never check — and, with no Sparkle session behind it,
    /// never claims an update is waiting either.
    @MainActor
    @Test func updaterIsAbsentInDebugBuilds() {
        #expect(UpdaterModel.isSupported == false)
        let model = UpdaterModel()
        #expect(model.canCheckForUpdates == false)
        #expect(model.hasPendingUpdate == false)
    }

    // MARK: - Menu strings

    @Test func checkForUpdatesStringResolvesPerLanguage() throws {
        #expect(try value("menu.checkForUpdates", in: "en") == "Check for Updates…")
        // "Buscar", not "Verificar", and the pin exists so it is not helpfully
        // corrected back: across 10,130 pt-BR strings extracted from macOS,
        // "buscar atualizações" appears 6 times and "verificar atualizações"
        // zero (2026-08-07).
        #expect(try value("menu.checkForUpdates", in: "pt-BR") == "Buscar Atualizações…")
    }

    /// The pending-update line and its button. Release-only on screen, but the
    /// strings ship in every build — and this reads the BUILT bundle, where the
    /// catalog gate cannot: that script checks the source catalog, so a unit that
    /// never made it into the .lproj still reads clean there and serves English to
    /// the pt-BR user.
    @Test func pendingUpdateStringsResolvePerLanguage() throws {
        #expect(try value("menu.update.available", in: "en") == "An update to Crema is available.")
        #expect(try value("menu.update.available", in: "pt-BR") == "Há uma atualização do Crema disponível.")
        #expect(try value("menu.update.show", in: "en") == "Show Update…")
        #expect(try value("menu.update.show", in: "pt-BR") == "Mostrar Atualização…")
    }

    private func value(_ key: String, in language: String) throws -> String {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        return bundle.localizedString(forKey: key, value: "«missing»", table: nil)
    }
}
