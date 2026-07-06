import AppKit
import SwiftUI

/// Album art with a one-time decode. The hosting views re-run body on every
/// position tick (they read the live scrubber position), so decoding inline
/// would rerun `NSImage(data:)` on the identical bytes each second — the live
/// snapshot re-carries the same artwork every emit. Caching in @State keyed by
/// the bytes decodes only when they change (a new cover); @State holds a
/// purely-visual artifact, not domain. The placeholder (♪) stands in when a
/// track has no artwork or bytes haven't arrived yet.
struct ArtworkView: View {
    let data: [UInt8]?
    let side: CGFloat
    let cornerRadius: CGFloat
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                // Decorative: the cover carries no information the title
                // doesn't; the thumbnail is pre-scaled, so scale is moot.
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.secondary.opacity(0.15))
                    // Scaled to the box: a fixed-size glyph overpowers small
                    // artwork slots.
                    Image(systemName: "music.note")
                        .font(.system(size: side * 0.42))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: data) { [data] in
            // Detached: the eager bounded decode stays off the render path.
            let decoded = await Task.detached {
                ArtworkDecoding.thumbnail(from: data, maxSide: ArtworkDecoding.displayMaxSide)
            }.value
            // A cancelled task means the bytes changed mid-decode: the stale
            // cover must not land over the successor's.
            guard !Task.isCancelled else { return }
            image = decoded
        }
    }
}
