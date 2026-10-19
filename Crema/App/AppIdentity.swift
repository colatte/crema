import AppKit

/// The app's own name, version, build and icon, as its bundle states them. Read
/// here and nowhere else, so the views that show them call no system API
/// (AGENTS.md, golden rule) and the build the About pane prints is the one the
/// login-item intent is stamped with. Each caller picks its own fallback: a
/// missing key is impossible in a built bundle, and what to show in its place
/// is the caller's contract, not this reading's.
enum AppIdentity {
    /// Display name, then name, so a rename never leaves a stale plaque.
    static var name: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
    }

    static var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    static var build: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    /// null_resettable in AppKit (imported as an IUO, so reads never return nil);
    /// the fallback keeps the no-force-unwrap discipline explicit.
    @MainActor static var icon: NSImage {
        NSApp.applicationIconImage ?? NSImage()
    }
}
