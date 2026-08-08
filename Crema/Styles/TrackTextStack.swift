import SwiftUI

/// Shared stacked text of the reference layout: strong title over weak artist,
/// two lines — never side by side. One type ramp for the whole family, so the
/// skins read as siblings.
///
/// The SIZES are the family's and are not parameterised: a surface that set its
/// own would be the first to break the siblinghood for a feeling nobody
/// measured. What a caller may vary is the artist's WEIGHT, because weight is
/// the free variable on a card that cannot grow — Apple's Live Activities
/// guidance, written for a glanceable surface, asks for "a medium weight or
/// higher", and the lock card is the one surface in this app read from across a
/// room rather than from a desk.
struct TrackTextStack: View {
    let title: String
    let artist: String?
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 2
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
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let artist {
                Text(artist)
                    .font(.caption.weight(artistWeight))
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
