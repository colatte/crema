import SwiftUI

/// Now playing on the lock screen: a glass card over the user's own wallpaper
/// that, on a click, becomes the cover itself.
///
/// Both states live inside the one rectangle the lock screen leaves free — the
/// card rests on the floor of that band, the expanded tile is centred in it
/// (`LockWidgetMetrics.clearBandFloor`, measured rather than chosen). The
/// blurred backdrop is the layer that does take the whole display.
///
/// It reads `coordinator.nowPlaying` rather than `coordinator.state`, and that
/// is the whole reason it can exist. `state` is the ephemeral presentation
/// machine — it returns to `.hidden` whenever the linger timer expires, which
/// is correct for a surface that visits and wrong for one that stays. The live
/// snapshot survives that and only goes nil when the media genuinely stops.
/// The 1 Hz position tick rebuilds this body, which is what the scrubber wants
/// anyway; nothing here derives layout from it, so no frame moves per second.
///
/// It deliberately does NOT conform to `SurfaceStyleBody`. That protocol would
/// oblige it to declare a `SurfaceProvenance` it never advances and a
/// `SurfaceDisplayPolicy` it never reads — both exist to serve a surface that
/// can hide, which this one cannot. Four one-line calls into the Coordinator
/// cost less than two dead requirements.
@MainActor
struct LockWidgetView: View {
    let coordinator: Coordinator
    /// Which cover to draw. Nil where nobody wired one (previews); the surface
    /// then simply uses whatever the player handed over, which is the fallback
    /// the resolver would have returned anyway.
    var artwork: LockArtworkResolver?

    /// The rect that may take a click, in the hosting window's coordinate space,
    /// reported whenever it moves — empty when there is nothing drawn.
    ///
    /// The view has to report it because the window cannot compute it: this
    /// window is the size of the display and the card is a few hundred points of
    /// it, so without this the panel would have to capture everywhere, over a
    /// surface where "everywhere" is the password field
    /// (`LockWidgetClickThrough`).
    var onInteractiveRect: ((CGRect) -> Void)?

    /// Purely visual, purely ephemeral — the same category as a hover: which of
    /// the two states is showing is never domain and never persisted.
    ///
    /// It resets when the media STOPS, not when the track changes, and the
    /// asymmetry is deliberate. A new song is continuous listening, and yanking
    /// a cover the user deliberately enlarged back into the card would be the
    /// surface undoing their choice. A gap is the surface leaving; whatever
    /// comes back after it has to come back the way it is born, or the large
    /// cover appears over the lock screen with nobody having clicked anything.
    @State private var expanded = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var track: NowPlaying? { coordinator.nowPlaying }

    /// One place decides which bytes every layer draws, so the thumbnail, the
    /// expanded tile and the backdrop can never disagree about which cover is
    /// showing.
    private func cover(_ track: NowPlaying) -> [UInt8]? {
        artwork?.artwork(for: track) ?? track.artworkData
    }

    var body: some View {
        ZStack {
            if let track {
                backdrop(track)
                surface(track)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Geometry never crosses the empty boundary — the same contract the
        // desktop skins keep: appearing and vanishing are opacity, at the
        // final rect.
        .opacity(track == nil ? 0 : 1)
        .animation(SurfaceAnimation.morph(reduceMotion: reduceMotion), value: track == nil)
        // The media stopping is the one edge the surface cannot observe from
        // inside itself: the card leaves the hierarchy and takes its reporter
        // with it, so the LAST rect it published would stay armed over bare
        // wallpaper, and `expanded` would survive to greet the next song
        // full-screen. Both are settled here, while the fade is running.
        .onChange(of: track == nil) { _, empty in
            guard empty else { return }
            onInteractiveRect?(.zero)
            expanded = false
        }
        // Keyed on the identity rather than the snapshot: the snapshot is
        // rewritten every second by the position tick, and re-asking the
        // endpoint once a second for the same song would be a very rude client.
        .task(id: track.map(LockArtworkResolver.identity)) {
            if let track { await artwork?.resolve(track) }
        }
    }

    // MARK: - Layers

    /// Only while expanded: the cover, blurred past reading, over everything.
    /// Collapsed, the user's own wallpaper is the background and this draws
    /// nothing at all.
    @ViewBuilder
    private func backdrop(_ track: NowPlaying) -> some View {
        DriftingArtworkBackground(image: nil, fallbackTone: nil)
            .opacity(0)
            .overlay {
                if expanded {
                    ArtworkBackdrop(data: cover(track))
                        .transition(.opacity)
                }
            }
    }

    /// One surface in both states, moved and reshaped rather than swapped.
    ///
    /// Collapsed it rests on the floor of the clear band; expanded it becomes a
    /// 300 pt square centred on the display, which is the rect the ruler proved
    /// free. Being ONE view across the two is what lets the cover travel — the
    /// earlier hero was a separate view that appeared at screen centre, so the
    /// comment claiming it "grows out of the thumbnail's position" described a
    /// motion that never happened.
    private func surface(_ track: NowPlaying) -> some View {
        card(track)
            .frame(
                maxHeight: .infinity,
                alignment: expanded ? .center : .bottom
            )
            .padding(.bottom, expanded ? 0 : LockWidgetMetrics.bottomInset)
    }

    /// Expanding is only offered when there is a cover to expand INTO. With no
    /// artwork — the JXA fallback carries none — the big state would be a glass
    /// square with the same words already on screen, and a control whose hint
    /// says "show the cover" would be promising something that does not exist.
    private func canExpand(_ track: NowPlaying) -> Bool {
        cover(track) != nil
    }

    private func card(_ track: NowPlaying) -> some View {
        VStack(spacing: LockWidgetMetrics.gap) {
            // Expanded, the rows sink to the bottom of the square and the cover
            // fills what they leave.
            if expanded { Spacer(minLength: 0) }
            head(track)
            ScrubberRow(
                position: coordinator.nowPlaying?.position ?? 0,
                duration: coordinator.nowPlaying?.duration,
                enabled: coordinator.commandsAvailable,
                showsDuration: true,
                onScrub: { coordinator.scrub(to: $0) }
            )
            .frame(height: LockWidgetMetrics.scrubberHeight)
            TransportControls(
                isPlaying: track.isPlaying,
                enabled: coordinator.commandsAvailable,
                skipEnabled: coordinator.skipControlsEnabled,
                buttonSide: LockWidgetMetrics.transportSide,
                spacing: LockWidgetMetrics.transportSpacing,
                onPrevious: { coordinator.previousTrack() },
                onPlayPause: { coordinator.togglePlayPause() },
                onNext: { coordinator.nextTrack() }
            )
        }
        .padding(LockWidgetMetrics.padding)
        .frame(
            width: expanded ? LockWidgetMetrics.expandedSide : LockWidgetMetrics.cardWidth,
            height: expanded ? LockWidgetMetrics.expandedSide : nil
        )
        .background { background(track) }
        .artworkAccent(from: cover(track))
        // One appearance for the whole surface, in every state — scoping it per
        // branch would flip the palette mid-transition.
        .environment(\.colorScheme, .dark)
        // Hit region, accessibility element and reported rect all attach HERE,
        // above the placement frame in `surface(_:)` and never under it. Under
        // it they would describe the LAYOUT frame, which is this width by the
        // whole height of the display — a tap target, and a VoiceOver button,
        // sitting over the password field.
        .contentShape(Rectangle())
        .onTapGesture { if canExpand(track) || expanded { toggle() } }
        .accessibilityAddTraits(canExpand(track) || expanded ? .isButton : [])
        .accessibilityHint(Text(expanded
                ? String(localized: "lock.collapse", defaultValue: "Hide the large cover")
                : String(localized: "lock.expand", defaultValue: "Show the cover large")))
        .background { interactiveRectReporter }
    }

    /// Glass when collapsed; the cover itself when expanded, with a scrim under
    /// the rows so the words hold against any album art.
    ///
    /// The fallback matters more than it looks: a track with no artwork keeps
    /// the glass even in the big state, so the square is never a placeholder
    /// glyph blown up to 300 pt.
    @ViewBuilder
    private func background(_ track: NowPlaying) -> some View {
        if expanded, let data = cover(track) {
            let shape = RoundedRectangle(
                cornerRadius: LockWidgetMetrics.expandedRadius, style: .continuous
            )
            ArtworkView(
                data: data,
                side: LockWidgetMetrics.expandedSide,
                cornerRadius: LockWidgetMetrics.expandedRadius,
                maxSide: ArtworkDecoding.lockScreenMaxSide
            )
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55), .black.opacity(0.88)],
                    startPoint: .init(x: 0.5, y: 0.42),
                    endPoint: .bottom
                )
                .clipShape(shape)
            }
            .overlay {
                shape.strokeBorder(
                    Color(white: SurfaceChrome.outerHairlineWhite)
                        .opacity(SurfaceChrome.outerHairlineOpacity),
                    lineWidth: SurfaceChrome.outerHairlineWidth
                )
            }
            .shadow(color: .black.opacity(0.5), radius: 40, y: 18)
        } else {
            cardSurface
        }
    }

    /// Publishes the drawn card's rect to the window. A background rather than
    /// an overlay so it can never sit between the card and a click, and keyed on
    /// the rect so a body pass that moved nothing — the 1 Hz position tick,
    /// every second, all night — reports nothing.
    private var interactiveRectReporter: some View {
        GeometryReader { proxy in
            let rect = proxy.frame(in: .global)
            Color.clear
                .onAppear { onInteractiveRect?(rect) }
                .onChange(of: rect) { _, new in onInteractiveRect?(new) }
        }
    }

    /// The card's own material. Deliberately NOT `vibrantSurface`: that samples
    /// what is behind the WINDOW, and this window is the size of the screen, so
    /// it would sample its own backdrop and go flat. A translucent fill over a
    /// blur of our own is what reads as glass here.
    private var cardSurface: some View {
        let shape = RoundedRectangle(cornerRadius: LockWidgetMetrics.cornerRadius, style: .continuous)
        return shape
            .fill(.black.opacity(expanded ? 0.40 : 0.52))
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                // The family's edge, from the one place that owns those numbers,
                // so this surface cannot drift from its siblings.
                shape.strokeBorder(
                    Color(white: SurfaceChrome.outerHairlineWhite)
                        .opacity(SurfaceChrome.outerHairlineOpacity),
                    lineWidth: SurfaceChrome.outerHairlineWidth
                )
            }
    }

    /// Collapsed the cover sits beside the words; expanded it has left, so the
    /// words take the middle. The waveform goes with it — it belongs to the
    /// compact row, and beside a 300 pt cover it is noise.
    @ViewBuilder
    private func head(_ track: NowPlaying) -> some View {
        HStack(spacing: LockWidgetMetrics.gap) {
            if !expanded {
                ArtworkView(
                    data: cover(track),
                    side: LockWidgetMetrics.thumbnailSide,
                    cornerRadius: LockWidgetMetrics.thumbnailRadius
                )
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            TrackTextStack(
                title: track.title,
                artist: track.artist,
                alignment: expanded ? .center : .leading
            )
            .frame(maxWidth: .infinity, alignment: expanded ? .center : .leading)
            if !expanded {
                WaveformGlyph(animating: track.isPlaying)
                    .transition(.opacity)
            }
        }
        .frame(height: expanded ? LockWidgetMetrics.textBlockHeight : LockWidgetMetrics.headHeight)
    }

    private func toggle() {
        withAnimation(SurfaceAnimation.morph(reduceMotion: reduceMotion)) {
            expanded.toggle()
        }
    }
}

/// The blurred cover behind an expanded widget. A thin wrapper whose only job
/// is to own the decode, so `DriftingArtworkBackground` stays a pure function
/// of an image and can be exercised without ImageIO.
private struct ArtworkBackdrop: View {
    let data: [UInt8]?
    @State private var image: CGImage?

    var body: some View {
        DriftingArtworkBackground(
            image: image,
            fallbackTone: ArtworkAccent.extract(from: data)
        )
        .ignoresSafeArea()
        .task(id: data) { [data] in
            let decoded = await blockingCall {
                ArtworkDecoding.thumbnail(from: data, maxSide: ArtworkDecoding.lockScreenMaxSide)
            }
            guard !Task.isCancelled else { return }
            image = decoded
        }
    }
}
