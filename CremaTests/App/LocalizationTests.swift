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
        #expect(try localizedInBuiltBundle("menu.quit", in: "en") == "Quit Crema")
        // No article, which is Apple's own shape for this menu item: Music.app
        // ships "Encerrar Música" and TV.app "Encerrar TV". Pinned so it is not
        // put back.
        #expect(try localizedInBuiltBundle("menu.quit", in: "pt-BR") == "Encerrar Crema")

        // The sample has to be a key whose two values DIFFER, or it stops testing
        // the thing it is named for: the style names are product names, equal in
        // both languages (docs/INTERNATIONALIZATION.md: one name per concept), and
        // "Card" == "Card" stays green against a bundle that ignores the language
        // argument entirely.
        #expect(try localizedInBuiltBundle("style.notch.description", in: "en") == "Blends into the notch")
        #expect(try localizedInBuiltBundle("style.notch.description", in: "pt-BR") == "Se funde com o notch")

        // And the styles themselves, pinned as deliberately UNtranslated: the
        // rule is easy to undo by helpfully translating one of them back.
        for style in ["style.notch", "style.card", "style.classic"] {
            #expect(try localizedInBuiltBundle(style, in: "en") == localizedInBuiltBundle(style, in: "pt-BR"))
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

    /// The Card footer counts the displays it names, so its noun agrees with the
    /// count in each language. A String Catalog plural compiles to the bundle's
    /// stringsdict, never to the flat table, so its presence there is the check
    /// that the variation shipped at all.
    @Test func theCardFooterAgreesWithTheNumberOfDisplays() throws {
        let key = "settings.hud.indicator.footer"
        var forms: [String: (one: String, two: String)] = [:]
        for language in ["en", "pt-BR"] {
            let lproj = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
            let plurals = NSDictionary(contentsOfFile: lproj + "/Localizable.stringsdict")
            try #require(plurals?[key] != nil, "\(language) ships no plural for \(key)")

            let bundle = try #require(Bundle(path: lproj))
            let format = bundle.localizedString(forKey: key, value: nil, table: nil)
            let locale = Locale(identifier: language)
            forms[language] = (
                String(format: format, locale: locale, 1, "A"),
                String(format: format, locale: locale, 2, "A, B")
            )
        }
        #expect(forms["en"]?.one == "Applies to 1 display: A.")
        #expect(forms["en"]?.two == "Applies to 2 displays: A, B.")
        #expect(forms["pt-BR"]?.one == "Vale para 1 tela: A.")
        #expect(forms["pt-BR"]?.two == "Vale para 2 telas: A, B.")
    }
}
