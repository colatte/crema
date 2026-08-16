/// Pure policy: is this media source a web browser? Browser media is ignored
/// by default — autoplay videos (feed scrolls, ads) grab the system's
/// now-playing for a few seconds each, and surfacing every one is the
/// opposite of discreet. Dedicated player apps are never filtered, so no
/// allowlist is needed: the rule is "non-browser surfaces, browser doesn't".
/// Settings exposes the override ("Include browser media", persisted and applied
/// live through Coordinator.ignoresBrowserMedia), so this rule is the DEFAULT and
/// not the whole behaviour — a reader deciding how strict to make it should know
/// the user can already turn it off.
enum MediaSourceFilter {
    /// Known browser families, by bundle-ID prefix — prefix matching covers
    /// the Beta/Dev/Canary/Nightly variants that share a family prefix, and
    /// WebKit helper processes for the odd payload with no parent app.
    /// Firefox is listed per-product (never "org.mozilla." wholesale):
    /// Thunderbird is org.mozilla.thunderbird — a mail app whose media must
    /// pass, per this module's own non-browser rule.
    private static let browserBundleIDPrefixes: [String] = [
        "com.apple.Safari",             // Safari + Technology Preview
        "com.apple.WebKit",             // WebKit helpers reported without a parent
        "com.google.Chrome",            // Chrome + Beta/Dev/Canary
        "org.mozilla.firefox",          // Firefox + Developer Edition
        "org.mozilla.nightly",          // Firefox Nightly
        "com.microsoft.edgemac",        // Edge + Beta/Dev/Canary
        "com.brave.Browser",            // Brave + Beta/Nightly
        "company.thebrowser.",          // Arc and Dia (The Browser Company)
        "com.operasoftware.",           // Opera + GX + Air
        "com.vivaldi.",                 // Vivaldi + snapshots
        "org.chromium.",                // Chromium builds
        "com.duckduckgo.macos.browser", // DuckDuckGo
        "ru.yandex.desktop.yandex-browser", // Yandex
        "org.torproject.torbrowser",    // Tor Browser
        "com.kagi.kagimacOS",           // Orion
        "app.zen-browser.zen",          // Zen
        "net.imput.helium",             // Helium (per-product, like Firefox: imput ships non-browser apps)
    ]

    /// Carve-outs checked before the browser prefixes: sources that live
    /// under a browser's namespace but are deliberate app-like experiences,
    /// not feed noise. Safari Web Apps ("Add to Dock") are the user pinning
    /// a site as an app — media from one is as intentional as Spotify's.
    private static let nonBrowserExceptionPrefixes: [String] = [
        "com.apple.Safari.WebApp",
    ]

    static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        if nonBrowserExceptionPrefixes.contains(where: { bundleID.hasPrefix($0) }) {
            return false
        }
        return browserBundleIDPrefixes.contains { bundleID.hasPrefix($0) }
    }
}
