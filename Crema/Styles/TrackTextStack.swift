import SwiftUI

/// Shared stacked text of the reference layout: strong title over weak artist,
/// two lines — never side by side. One type ramp for the whole family, so the
/// skins read as siblings.
struct TrackTextStack: View {
    let title: String
    let artist: String?
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 2

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let artist {
                Text(artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
