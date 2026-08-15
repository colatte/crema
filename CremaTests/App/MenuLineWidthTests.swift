import Foundation
import Testing
@testable import Crema

/// The menu's width ceiling, read off the strings that actually ship.
///
/// An NSMenu is exactly as wide as its widest item, so one 116-character row opened
/// this menu at roughly 1500 pt in the field. The ceiling is about 72 characters a
/// LINE, the breaks live in the catalog, and both languages carry the same number of
/// them (docs/DECISIONS.md: menu-status-before-warnings, third amendment).
///
/// Measured against the compiled `.lproj` tables rather than the source catalog for
/// the reason `SparkleUpdaterTests` gives: the catalog gate checks the file, and a
/// unit that never made it into the bundle still reads clean there.
struct MenuLineWidthTests {
    /// Not a round number chosen here: it is the ceiling the field measurement
    /// bought, stated once so a regression names it.
    private let ceiling = 72

    private func table(_ language: String) throws -> [String: String] {
        let lproj = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(NSDictionary(contentsOfFile: lproj + "/Localizable.strings") as? [String: String])
    }

    /// Every menu line whose width the app itself decides. A value carrying a hole is
    /// skipped HERE and measured below only where the hole's content is closed: a
    /// track title or a neighbour app's name has no worst case to measure, which is
    /// why those stay data rather than chrome.
    @Test func everyStaticMenuLineStaysUnderTheCeiling() throws {
        for language in ["en", "pt-BR"] {
            for (key, value) in try table(language) where key.hasPrefix("menu.") && !value.contains("%") {
                for line in value.split(separator: "\n", omittingEmptySubsequences: false) {
                    #expect(line.count <= ceiling, "\(language) \(key): \(line.count) characters — \(line)")
                }
            }
        }
    }

    /// The one menu line with a hole the app fills from a CLOSED set, measured at its
    /// widest: every domain suspended at once. Written as a single line it reached 85
    /// characters in English and 86 in Portuguese — a wide menu reachable by turning
    /// the feature on and having three channels fail
    /// (docs/DECISIONS.md: menu-status-before-warnings, fifth amendment).
    ///
    /// The domain names come from `OSDSuppressionDomain.allCases` through an
    /// exhaustive switch, so a fourth domain cannot be added without this test being
    /// told what it is called.
    @Test func theSuspensionWarningIsMeasuredWithEveryDomainNamed() throws {
        for language in ["en", "pt-BR"] {
            let strings = try table(language)
            var domains: [String] = []
            for domain in OSDSuppressionDomain.allCases {
                try domains.append(#require(strings[domainKey(domain)]))
            }
            // Joined the way the menu joins them, in the locale the line is read in:
            // the separator is the language's own (", " vs " and " vs " e ").
            let names = domains.formatted(.list(type: .and).locale(Locale(identifier: language)))
            let format = try #require(strings["menu.osdSuspended.warning"])
            for line in String(format: format, names).split(separator: "\n", omittingEmptySubsequences: false) {
                #expect(line.count <= ceiling, "\(language) suspension warning: \(line.count) characters — \(line)")
            }
        }
    }

    /// The two languages break the same number of times, so one sentence does not
    /// stack three items in English and one in Portuguese.
    @Test func bothLanguagesBreakEveryMenuSentenceTheSameNumberOfTimes() throws {
        let english = try table("en")
        let portuguese = try table("pt-BR")
        for (key, value) in english where key.hasPrefix("menu.") {
            let translated = try #require(portuguese[key], "no pt-BR unit for \(key)")
            let englishBreaks = value.filter { $0 == "\n" }.count
            let portugueseBreaks = translated.filter { $0 == "\n" }.count
            #expect(englishBreaks == portugueseBreaks, "\(key): \(englishBreaks) breaks in en, \(portugueseBreaks) in pt-BR")
        }
    }

    private func domainKey(_ domain: OSDSuppressionDomain) -> String {
        switch domain {
        case .volume: "osd.domain.volume"
        case .screenBrightness: "osd.domain.screenBrightness"
        case .keyboardBrightness: "osd.domain.keyboardBrightness"
        }
    }
}
