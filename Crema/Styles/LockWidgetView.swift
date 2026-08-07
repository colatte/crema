import SwiftUI

/// Now playing on the lock screen: a glass card over the user's own wallpaper
/// that, on a click, hands its cover to the whole display.
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
    /// comes back after it has to come back the way it is born, or a full-display
    /// cover appears over the lock screen with nobody having clicked anything.
    @State private var expanded = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var track: NowPlaying? { coordinator.nowPlaying }

    /// One place decides which bytes every layer draws, so the thumbnail, the
    /// hero and the backdrop can never disagree about which cover is showing.
    private func cover(_ track: NowPlaying) -> [UInt8]? {
        artwork?.artwork(for: track) ?? track.artworkData
    }

    var body: some View {
        ZStack {
            if let track {
                backdrop(track)
                hero(track)
                card(track)
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

    /// The cover once it has left the card. Grows out of the thumbnail's
    /// position rather than fading in on the spot, so the click reads as the
    /// picture moving rather than two pictures swapping.
    @ViewBuilder
    private func hero(_ track: NowPlaying) -> some View {
        if expanded {
            ArtworkView(
                data: cover(track),
                side: LockWidgetMetrics.heroSide,
                cornerRadius: LockWidgetMetrics.heroRadius,
                maxSide: ArtworkDecoding.lockScreenMaxSide
            )
            .shadow(color: .black.opacity(0.5), radius: 40, y: 18)
            .transition(.scale(scale: 0.2).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    private func card(_ track: NowPlaying) -> some View {
        VStack(spacing: LockWidgetMetrics.gap) {
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
            width: expanded
                ? LockWidgetMetrics.expandedCardWidth
                : LockWidgetMetrics.cardWidth
        )
        .background { cardSurface }
        .artworkAccent(from: cover(track))
        // One appearance for the whole surface, in every state — scoping it per
        // branch would flip the palette mid-transition.
        .environment(\.colorScheme, .dark)
        // Hit region, accessibility element and reported rect all attach HERE,
        // above the stretching frame below and never under it. Under it they
        // would describe the card's LAYOUT frame, which is the card's width by
        // the whole height of the display — a tap target, and a VoiceOver
        // button, sitting over the password field.
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(expanded
                ? String(localized: "lock.collapse", defaultValue: "Hide the full-screen cover")
                : String(localized: "lock.expand", defaultValue: "Show the cover full screen")))
        .background { interactiveRectReporter }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, LockWidgetMetrics.bottomInset)
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
