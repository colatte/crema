import Foundation
import Testing

/// i18n foundation: the String Catalog ships both languages and semantic keys
/// resolve per language (the host app bundle is the real Crema.app).
struct LocalizationTests {

    @Test func bundleShipsEnglishAndPortuguese() {
        let localizations = Set(Bundle.main.localizations)
        #expect(localizations.contains("en"))
        #expect(localizations.contains("pt-BR"))
    }

    @Test func semanticKeysResolvePerLanguage() throws {
        func value(_ key: String, in language: String) throws -> String {
            let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            return bundle.localizedString(forKey: key, value: "«missing»", table: nil)
        }

        #expect(try value("menu.quit", in: "en") == "Quit Crema")
        #expect(try value("menu.quit", in: "pt-BR") == "Encerrar o Crema")
        #expect(try value("style.card", in: "en") == "Card")
        #expect(try value("style.card", in: "pt-BR") == "Cartão")
    }

    /// The whole catalog, not a sample: both compiled tables carry the same
    /// key set and every value is non-empty. A key added without its pt-BR
    /// unit ships showing the raw identifier in that language's UI — the
    /// compiler never complains, so this is the only mechanical net under the
    /// catalog's verbatim discipline.
    @Test func everyCatalogKeyShipsInBothLanguages() throws {
        func table(_ language: String) throws -> [String: String] {
            let lproj = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
            return try #require(NSDictionary(contentsOfFile: lproj + "/Localizable.strings") as? [String: String])
        }
        let english = try table("en")
        let portuguese = try table("pt-BR")

        #expect(!english.isEmpty)
        #expect(Set(english.keys) == Set(portuguese.keys))
        for (key, value) in english {
            #expect(!value.isEmpty, "empty en value for \(key)")
        }
        for (key, value) in portuguese {
            #expect(!value.isEmpty, "empty pt-BR value for \(key)")
        }
    }

    /// The composed track line must survive translation with BOTH names intact: a
    /// pt-BR unit that lost a placeholder ships a menu row missing the artist, and
    /// the compiler cannot see it — `everyCatalogKeyShipsInBothLanguages` cannot
    /// either, since the key exists and the value is non-empty. Formatting it is
    /// the only mechanical check, because the catalog value may legitimately be
    /// `%@ … %@` or the positional `%1$@ … %2$@`.
    @Test func theTrackLineKeepsBothNamesInEveryLanguage() throws {
        for language in ["en", "pt-BR"] {
            let lproj = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try #require(Bundle(path: lproj))
            let format = bundle.localizedString(
                forKey: "menu.nowPlaying.titleAndArtist",
                value: nil,
                table: nil
            )
            let line = String(format: format, "TRACK", "BAND")
            #expect(line.contains("TRACK"), "\(language) drops the title")
            #expect(line.contains("BAND"), "\(language) drops the artist")
        }
    }
}
