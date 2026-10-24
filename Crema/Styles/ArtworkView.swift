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
                // Decorative like the cover it stands in for; exposed, VoiceOver
                // reads the symbol's name beside the title it decorates.
                .accessibilityHidden(true)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A cover slot. It draws the cover its skin already decoded
/// (`artworkImage(from:)`) and decodes nothing itself: a slot lives inside a
/// crossfading branch, and every insertion of that branch — HUD to now playing,
/// compact to expanded — would start a slot of its own empty, flashing the ♪
/// until its decode landed.
struct ArtworkView: View {
    let side: CGFloat
    let cornerRadius: CGFloat
    @Environment(\.artworkImage) private var image

    var body: some View {
        ArtworkFrame(image: image, side: side, cornerRadius: cornerRadius)
    }
}

private struct ArtworkImageKey: EnvironmentKey {
    static let defaultValue: CGImage? = nil
}

extension EnvironmentValues {
    /// The cover decoded for display; nil while it decodes and when the track has
    /// none, which every slot draws as the placeholder.
    var artworkImage: CGImage? {
        get { self[ArtworkImageKey.self] }
        set { self[ArtworkImageKey.self] = newValue }
    }
}

extension View {
    /// Decodes the cover for every `ArtworkView` below. Applied above the
    /// crossfading branches (one instance per skin view, beside
    /// `artworkAccent(from:)`), so the decoded image survives every branch swap,
    /// and keyed on the bytes, which position ticks never change: one decode per
    /// cover. @State holds a purely visual artifact, never domain.
    func artworkImage(from data: [UInt8]?) -> some View {
        modifier(ArtworkImageModifier(data: data))
    }
}

private struct ArtworkImageModifier: ViewModifier {
    let data: [UInt8]?
    @State private var image: CGImage?

    func body(content: Content) -> some View {
        content
            .environment(\.artworkImage, image)
            // Every slot decodes to the same bound, so the bytes alone are the
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
