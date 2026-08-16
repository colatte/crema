import AppKit
import SwiftUI

/// What a cover slot LOOKS like, with no opinion about who decoded it: the
/// placeholder (♪) when a track has no artwork or the bytes haven't arrived,
/// the clip and the fill rule. Split from the decode so the drawing cannot
/// acquire an opinion about it; ArtworkView below is its only client.
private struct ArtworkFrame: View {
    let image: CGImage?
    let side: CGFloat
    let cornerRadius: CGFloat

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
    }
}

/// Album art with a one-time decode. The hosting views re-run body on every
/// position tick (they read the live scrubber position), so decoding inline
/// would re-run the ImageIO thumbnail (ArtworkDecoding) on the identical
/// bytes each second — the live snapshot re-carries the same artwork every
/// emit. Caching in @State keyed by the bytes decodes only when they change
/// (a new cover); @State holds a purely-visual artifact, not domain.
struct ArtworkView: View {
    let data: [UInt8]?
    let side: CGFloat
    let cornerRadius: CGFloat
    @State private var image: CGImage?

    var body: some View {
        ArtworkFrame(image: image, side: side, cornerRadius: cornerRadius)
            // Every slot decodes to the same bound (a per-caller bound existed
            // once, for a removed 300 pt surface), so the bytes alone are the
            // decode's whole identity and the task keys on them directly.
                .task(id: data) { [data] in
                    // ImageIO decoding is a blocking synchronous call, so it goes off the
                    // concurrency pools entirely rather than into a detached task — the
                    // pool has one thread per core and does not overcommit, and a big
                    // cover on a slow path would hold one (see `blockingCall`). It is not
                    // cancellable either way: ImageIO does not check for it, so the guard
                    // below is what keeps a stale cover off the successor's slot.
                    let decoded = await blockingCall {
                        ArtworkDecoding.thumbnail(from: data, maxSide: ArtworkDecoding.displayMaxSide)
                    }
                    // A cancelled task means the bytes changed mid-decode: the stale
                    // cover must not land over the successor's.
                    guard !Task.isCancelled else { return }
                    image = decoded
                }
    }
}
