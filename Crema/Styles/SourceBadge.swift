import AppKit
import SwiftUI

/// The icon of the app the music is coming from, pinned to a corner of the
/// cover.
///
/// It answers a question the card could not: "playing" is visible, "playing
/// FROM WHERE" was not, and on a lock screen the difference matters because
/// nobody is going to go and look. It costs nothing to know — the adapter
/// already publishes the parent application's bundle identifier and
/// `NowPlaying.sourceBundleID` already carries it up; nothing new is read from
/// the system except an icon the Finder draws anyway.
///
/// **Absence is the resting state, not an error.** The JXA fallback leaves
/// `sourceBundleID` nil by design, an app can be uninstalled between the
/// payload and the draw, and a bundle identifier can name something with no
/// icon. Every one of those renders nothing at all rather than a placeholder:
/// a generic grey square in the corner of a cover is worse than a clean corner,
/// because it says "something is missing" about a fact nobody asked for.
struct SourceBadge: View {
    let bundleID: String?
    var side: CGFloat

    var body: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: side, height: side)
                .clipShape(Circle())
                // The badge sits ON the artwork, so it needs its own separation
                // or a dark album corner swallows a dark app icon. A ring plus a
                // tight shadow is what the system's own badged icons use.
                .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
    }

    /// Resolved at draw time rather than cached, and the reason is that the
    /// alternative is worse than the cost. `NSWorkspace` answers from an
    /// in-process cache — this is a dictionary lookup, not disk I/O — while a
    /// cache of our own would need an invalidation story for an app being
    /// installed, moved or removed while the card is up, which is a whole
    /// mechanism to avoid a lookup that is already free.
    private var icon: NSImage? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
