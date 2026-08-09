import SwiftUI

/// Shared stacked text of the reference layout: strong title over weak artist,
/// two lines — never side by side. One type ramp for the whole family, so the
/// skins read as siblings.
///
/// The sizes come from a CLOSED SET declared below, never from a call site.
/// That is the whole of what "one ramp for the family" now means: for a long
/// while it meant one ramp full stop, and a comment in `LockWidgetMetrics`
/// refused a second on the grounds that it would be broken "for a feeling
/// nobody measured". The feeling got measured — see `Scale` — so the rule moved
/// from "there is one" to "there are exactly two and they live together".
///
/// A caller may also vary the artist's WEIGHT, which is the free variable on a
/// card that cannot grow: Apple's Live Activities guidance, written for a
/// glanceable surface, asks for "a medium weight or higher".
struct TrackTextStack: View {

    /// The two scales this family has, both defined HERE and never at a call
    /// site, which is the whole mitigation. A lock card that spelled its own
    /// sizes inline would put the two ramps in different files, and the next
    /// person to move one would not see the other; as an enum, both land in the
    /// reviewer's diff and the relationship between them is a thing you can
    /// read rather than reconstruct.
    ///
    /// Why a second scale exists at all, after a comment in `LockWidgetMetrics`
    /// spent a paragraph refusing one: the refusal was "a feeling nobody
    /// measured", and it has now been measured. Apple's Accessibility HIG
    /// publishes macOS default 13 pt against minimum 10 pt, and says to follow
    /// the defaults for custom type. `.family` ships 11 over 10 — the title two
    /// points UNDER the platform default and the artist exactly AT the platform
    /// minimum. That is correct for a surface read at desk distance while the
    /// user is working, and wrong for the one surface in this app read from
    /// across a room.
    enum Scale {
        /// The desktop skins: discreet, over the user's work.
        case family
        /// The lock card: read at two or three metres, in the dark, by someone
        /// walking past. One step up on both lines, which lands the title on
        /// the platform default and the artist one above the minimum.
        case glance

        var title: Font {
            switch self {
            case .family: .subheadline.weight(.semibold)   // 11/14
            case .glance: .body.weight(.semibold)          // 13/16
            }
        }

        var artist: Font {
            switch self {
            case .family: .caption                          // 10/13
            case .glance: .subheadline                      // 11/14
            }
        }

        /// What a caller must reserve for the two lines plus their spacing, so
        /// a card's height stays a sum of its parts rather than a measurement
        /// off a screenshot.
        var blockHeight: CGFloat {
            switch self {
            case .family: 34
            case .glance: 38
            }
        }
    }

    let title: String
    let artist: String?
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 2
    var scale: Scale = .family
    /// Regular for the desktop skins, which are read at desk distance. The lock
    /// card asks for `.medium`.
    var artistWeight: Font.Weight = .regular

    /// Read here rather than at each call site, because the promotion below is
    /// correct on every surface: a secondary label going primary is precisely
    /// what the preference asks for, and scattering the check would leave three
    /// skins honouring it and one forgetting.
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            Text(title)
                .font(scale.title)
                .lineLimit(1)
            if let artist {
                Text(artist)
                    .font(scale.artist.weight(artistWeight))
                    // `.secondary` is a hierarchical style on purpose: a literal
                    // `Color.white.opacity(0.55)` would switch OFF AppKit's
                    // vibrancy blend behind it, which is the thing making the ink
                    // sit in the material rather than on top of it. Under
                    // Increase Contrast it promotes instead of being tinted, for
                    // the same reason.
                    .foregroundStyle(contrast == .increased ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
    }
}
