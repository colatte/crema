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

        // The sample has to be a key whose two values DIFFER, or it stops
        // testing the thing it is named for. `style.card` used to sit here and
        // stopped qualifying the day the style names became product names in
        // both languages (CLAUDE.md: one name per concept) — "Card" == "Card"
        // would have kept this green against a bundle that ignored the language
        // argument entirely.
        #expect(try value("style.notch.description", in: "en") == "Blends into the notch")
        #expect(try value("style.notch.description", in: "pt-BR") == "Funde-se com o notch")

        // And the styles themselves, pinned as deliberately UNtranslated: the
        // rule is easy to undo by helpfully translating one of them back.
        for style in ["style.notch", "style.card", "style.classic"] {
            #expect(try value(style, in: "en") == value(style, in: "pt-BR"))
        }
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
