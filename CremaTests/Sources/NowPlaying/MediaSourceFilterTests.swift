import Testing
@testable import Crema

/// The browser filter: pure bundle-ID policy. Browsers (and their Beta/Dev
/// variants, via prefix) are recognized; dedicated players and unknown
/// sources are not — the rule is "non-browser surfaces", never an allowlist.
struct MediaSourceFilterTests {

    @Test func recognizesTheKnownBrowserFamilies() {
        for id in [
            "com.apple.Safari",
            "com.apple.SafariTechnologyPreview",
            "com.apple.WebKit.GPU",
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "org.mozilla.firefox",
            "org.mozilla.nightly",
            "com.microsoft.edgemac",
            "com.microsoft.edgemac.Beta",
            "com.brave.Browser",
            "company.thebrowser.Browser",
            "com.operasoftware.OperaGX",
            "com.vivaldi.Vivaldi",
            "org.chromium.Chromium",
            "com.duckduckgo.macos.browser",
            "ru.yandex.desktop.yandex-browser",
            "org.torproject.torbrowser",
            "com.kagi.kagimacOS",
            "app.zen-browser.zen",
        ] {
            #expect(MediaSourceFilter.isBrowser(id), "\(id) must be filtered")
        }
    }

    @Test func dedicatedPlayersAndUnknownSourcesPass() {
        for id in [
            "com.spotify.client",
            "com.apple.Music",
            "com.apple.podcasts",
            "com.apple.QuickTimePlayerX",
            "tv.plex.desktop",
            "com.colatte.some-future-player",
            // Gecko-based but a mail app: the org.mozilla family must be
            // matched per-product, never wholesale.
            "org.mozilla.thunderbird",
        ] {
            #expect(!MediaSourceFilter.isBrowser(id), "\(id) must pass")
        }
    }

    @Test func safariWebAppsAreAppsNotBrowserNoise() {
        // "Add to Dock" pins a site as an app — media from it is as
        // intentional as a dedicated player's.
        #expect(!MediaSourceFilter.isBrowser("com.apple.Safari.WebApp.ABC123"))
        // The carve-out must not blunt the Safari match itself.
        #expect(MediaSourceFilter.isBrowser("com.apple.Safari"))
    }

    @Test func nilIsNotABrowser() {
        // The JXA fallback cannot report a source — and it only ever talks to
        // Spotify/Apple Music, so nil defaulting to "pass" is safe.
        #expect(!MediaSourceFilter.isBrowser(nil))
    }
}
