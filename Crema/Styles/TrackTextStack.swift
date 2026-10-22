import SwiftUI

/// Shared stacked text of the reference layout: strong title over weak artist,
/// two lines — never side by side. One type ramp for the whole family, so the
/// skins read as siblings.
///
/// ONE ramp, and the sizes are not parameterised: a surface that set its own
/// would be the first to break the siblinghood.
struct TrackTextStack: View {

    let title: String
    let artist: String?
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 2
    /// Whether a line too long for its width scrolls through (`MarqueeLine`)
    /// rather than truncating: the expanded player's, where the text is read.
    var scrolls = false

    /// Read here rather than at each call site, because the promotion below is
    /// correct on every surface: a secondary label going primary is precisely
    /// what the preference asks for, and scattering the check would leave three
    /// skins honouring it and one forgetting.
    @Environment(\.colorSchemeContrast) private var contrast

    /// The two lines' scrolling, kept here so they share one rhythm: one start,
    /// reset when the track or what moves changes, and the longer line's travel
    /// as the length of every run (`MarqueeMotion.offset`). Purely visual.
    @State private var runStart = Date.now
    @State private var titleTravel: CGFloat = 0
    @State private var artistTravel: CGFloat = 0

    private var cycleTravel: CGFloat { max(titleTravel, artistTravel) }

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            MarqueeLine(
                scrolls: scrolls, start: runStart, cycleTravel: cycleTravel,
                reportTravel: { titleTravel = $0 },
                content: {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
            )
            if let artist {
                MarqueeLine(
                    scrolls: scrolls, start: runStart, cycleTravel: cycleTravel,
                    reportTravel: { artistTravel = $0 },
                    content: {
                        Text(artist)
                            .font(.caption)
                            // `.secondary` is a hierarchical style on purpose: a literal
                            // `Color.white.opacity(0.55)` would switch OFF AppKit's
                            // vibrancy blend behind it, which is the thing making the
                            // ink sit in the material rather than on top of it. Under
                            // Increase Contrast it promotes instead of being tinted,
                            // for the same reason.
                            .foregroundStyle(contrast == .increased ? .primary : .secondary)
                    }
                )
            }
        }
        .onChange(of: title) { runStart = .now }
        .onChange(of: artist) { _, artist in
            // A line that leaves takes its travel with it; one that stays reports
            // a new one as it measures.
            if artist == nil { artistTravel = 0 }
            runStart = .now
        }
        .onChange(of: cycleTravel) { runStart = .now }
    }
}
