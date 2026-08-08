import SwiftUI

/// Now playing on the lock screen: a glass card over the user's own wallpaper
/// that, on a click, becomes the cover itself.
///
/// **Nothing here paints a ground.** Both states are bounded objects on the
/// user's own wallpaper, and that is the decision rather than a limitation
/// (docs/DECISIONS.md: the-lock-surface-is-a-card). A full-screen blurred
/// backdrop shipped here for a while and was removed: it covered the system's
/// clock, the avatar and the password field, which cost a clock of our own, a
/// clearance band, a fade whose boundary the eye hunts, and — the part that
/// ended it — a safety case for what a wedged app leaves over a login. The
/// level this window occupies is named
/// `kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`; Apple's own tenant
/// there draws bounded cards, and so does every shipping competitor at it.
///
/// Both states live inside the one rectangle the lock screen leaves free — the
/// card rests on the floor of that band, the expanded tile is centred in it
/// (`LockWidgetMetrics.clearBandFloor`, measured rather than chosen).
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

    /// ONE decode for the whole surface, at the largest bound any layer needs.
    ///
    /// It used to be five, and the expensive ones started ON THE CLICK: the
    /// 300 pt tile owned an `ArtworkView`-style decode at 1024 px whose cache key
    /// only came into existence when `expanded` flipped. So a cold expand
    /// animated a grey rectangle with a 126 pt music note for the whole spring,
    /// and no choreography above it could mean anything. Decoding here, keyed on
    /// the bytes, moves the work to the moment the TRACK resolves — where nobody
    /// is watching — and the destination pixels exist before the gesture starts.
    @State private var decoded = DecodedCover()

    struct DecodedCover {
        var image: CGImage?
        var tone: ArtworkAccent.Tone?
    }

    private var track: NowPlaying? { coordinator.nowPlaying }

    /// One place decides which bytes every layer draws, so the thumbnail and the
    /// expanded tile can never disagree about which cover is showing.
    private func cover(_ track: NowPlaying) -> [UInt8]? {
        artwork?.artwork(for: track) ?? track.artworkData
    }

    var body: some View {
        ZStack {
            if let track {
                surface(track)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Geometry never crosses the empty boundary — the same contract the
        // desktop skins keep: appearing and vanishing are opacity, at the
        // final rect.
        .opacity(track == nil ? 0 : 1)
        // NOT gated on Reduce Motion, and that is the contract rather than an
        // oversight — a cross-fade is what the preference asks for in place of
        // motion, so suppressing it makes the card pop in and out in one frame.
        // This used to call `morph(reduceMotion:)` and inherited a gate that
        // belongs to geometry; the desktop skins never had it.
        .animation(SurfaceAnimation.appearFade(vanishing: track == nil), value: track == nil)
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
        // Keyed on the BYTES, not the track: the archive upgrade lands after the
        // track resolves, and when it does every layer has to move to the larger
        // cover together.
        .task(id: track.flatMap { cover($0) }) { [bytes = track.flatMap { cover($0) }] in
            // ImageIO is blocking and uncancellable, so it goes off the
            // concurrency pools entirely — the same exit `ArtworkView` takes, and
            // for the same reason.
            let fresh = await blockingCall { () -> DecodedCover in
                let image = ArtworkDecoding.thumbnail(from: bytes, maxSide: ArtworkDecoding.lockScreenMaxSide)
                return DecodedCover(image: image, tone: image.flatMap(ArtworkAccent.extract))
            }
            guard !Task.isCancelled else { return }
            decoded = fresh
        }
    }

    // MARK: - Layers

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
    private var canExpand: Bool {
        // The DECODED image, not the bytes. Bytes in hand are not a picture on
        // screen, and offering a growth into a placeholder is what the single
        // decode exists to stop.
        decoded.image != nil
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
        // Injected from the surface's own decode rather than derived again by
        // `.artworkAccent(from:)`, which would open a second ImageIO path over
        // the same bytes.
        .environment(\.artworkAccent, decoded.tone)
        // One appearance for the whole surface, in every state — scoping it per
        // branch would flip the palette mid-transition.
        .environment(\.colorScheme, .dark)
        // Hit region, accessibility element and reported rect all attach HERE,
        // above the placement frame in `surface(_:)` and never under it. Under
        // it they would describe the LAYOUT frame, which is this width by the
        // whole height of the display — a tap target, and a VoiceOver button,
        // sitting over the password field.
        .contentShape(Rectangle())
        .onTapGesture { if canExpand || expanded { toggle() } }
        .accessibilityAddTraits(canExpand || expanded ? .isButton : [])
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
        if expanded, let image = decoded.image {
            let shape = RoundedRectangle(
                cornerRadius: LockWidgetMetrics.expandedRadius, style: .continuous
            )
            ArtworkFrame(
                image: image,
                side: LockWidgetMetrics.expandedSide,
                cornerRadius: LockWidgetMetrics.expandedRadius
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
                ArtworkFrame(
                    image: decoded.image,
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

    /// `expanded` still holds the CURRENT state here, so the destination is its
    /// negation — and the destination is what picks the spring, the same rule the
    /// desktop skins get from provenance. Both directions shared the open spring
    /// until this round, which meant collapsing overshot: the card sprang past
    /// its resting size and grew back into it, a bounce on a surface whose whole
    /// gesture is putting itself away.
    private func toggle() {
        withAnimation(SurfaceAnimation.morph(expanding: !expanded, reduceMotion: reduceMotion)) {
            expanded.toggle()
        }
    }
}
