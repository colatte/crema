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

        #expect(try value("menu.quit", in: "en") == "Quit")
        #expect(try value("menu.quit", in: "pt-BR") == "Sair")
        #expect(try value("style.card", in: "en") == "Card")
        #expect(try value("style.card", in: "pt-BR") == "Cartão")
    }
}
