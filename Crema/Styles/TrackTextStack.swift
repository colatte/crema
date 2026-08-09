import SwiftUI

/// Shared stacked text of the reference layout: strong title over weak artist,
/// two lines — never side by side. One type ramp for the whole family, so the
/// skins read as siblings.
///
/// ONE ramp, and the sizes are not parameterised: a surface that set its own
/// would be the first to break the siblinghood. A second scale existed briefly,
/// for a lock-screen card read at two or three metres; the surface was removed
/// and the scale went with it rather than waiting in the file for a caller.
///
/// A caller may still vary the artist's WEIGHT, which stays because it costs no
/// layout and Apple's own guidance asks for a medium weight or higher wherever
/// text has to carry at a distance.
struct TrackTextStack: View {

    let title: String
    let artist: String?
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 2
    /// Regular for the desktop skins, which are read at desk distance. The lock
    /// card asked for `.medium`; the surface went, the knob stays for the
    /// reason the header gives.
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
