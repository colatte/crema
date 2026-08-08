import SwiftUI

/// Now playing on the lock screen: a glass card over the user's own wallpaper
/// that, on a click, becomes the cover itself.
///
/// Both states live inside the one rectangle the lock screen leaves free — the
/// card rests on the floor of that band, the expanded tile is centred in it
/// (`LockWidgetMetrics.clearBandFloor`, measured rather than chosen). The
/// blurred backdrop takes the whole display MINUS that same band: it fades out
/// below `clearBandFloor` so the clock, the avatar and the password field stay
/// readable (`LoginClearance`). Covering the system's clock is what obliges this
/// surface to draw one of its own, and only in the state that covers it.
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
struct LockWidgetView<Clock: SleepClock>: View {
    let coordinator: Coordinator
    /// Which cover to draw. Nil where nobody wired one (previews); the surface
    /// then simply uses whatever the player handed over, which is the fallback
    /// the resolver would have returned anyway.
    var artwork: LockArtworkResolver?

    /// What paces the clock's minute hand. No default, deliberately: a clock
    /// parameter carrying a production default is a wall clock injected at every
    /// test site without anyone writing `Date()`, which is the trap CLAUDE.md's
    /// TDD section names. There is exactly one production caller.
    ///
    /// Generic rather than `any SleepClock` for two reasons, one of them a
    /// compiler fact: the protocol does not self-conform, so an existential
    /// could not be handed to `LockClockView`. And the production clock is an
    /// empty struct, so a concrete type keeps both views diffable where an
    /// existential stored property would make every 1 Hz media tick re-evaluate
    /// the clock's body.
    var clock: Clock

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
    /// nothing at all — and NOTHING is what it costs, which it did not before.
    ///
    /// This used to host the transition on a real `DriftingArtworkBackground` at
    /// `.opacity(0)`, used purely as a container. Zero opacity keeps a view in
    /// the hierarchy: the invisible one armed its 26 s `repeatForever` transform
    /// and its settle task on every lock, drawing nothing, all night. A plain
    /// shape is the container now.
    @ViewBuilder
    private func backdrop(_ track: NowPlaying) -> some View {
        Color.clear
            .overlay {
                if expanded {
                    // The clock rides the same condition as the backdrop, and
                    // that is the whole design rather than a convenience: the
                    // only reason to draw a clock is that this layer covered the
                    // system's. One fact, one `if` — a second gate could drift
                    // into showing ours beside theirs.
                    ZStack(alignment: .top) {
                        ArtworkBackdrop(data: cover(track))
                        LockClockView(clock: clock)
                            .padding(.top, LockWidgetMetrics.clockTopInset)
                    }
                    // Belt-and-braces, not the load-bearing part: measured, a
                    // borderless screen-sized `NSHostingView` reports a safe area
                    // of 0 even on a notched panel, so `clockTopInset` already
                    // means the physical top. Kept so a future window that DOES
                    // get an inset cannot move the clock without anyone noticing.
                    .ignoresSafeArea()
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

/// Where the backdrop stops, so the lock screen's own login keeps its strip.
///
/// The surface's whole cost is that a full-screen backdrop also covers the
/// clock, the avatar and the password field. It clears the bottom band and ramps
/// back to opaque above it — a hard edge there reads as a rendering bug, which
/// is why the band exists at all.
///
/// Bands in POINTS, bottom-anchored, opaque taking the remainder: no display
/// height enters this file, so the fraction this was nearly written as cannot be
/// spelled here without plumbing a reviewer would see. macOS has no bottom safe
/// area, so bottom-anchoring also costs nothing at the edge.
///
/// `.mask` reads ALPHA, not luminance — the black band shows, the clear one
/// hides, and the ramp between them is one description of the fade and the only
/// one. A `backdropAlpha(distanceFromBottom:)` helper beside it would be the
/// same curve written twice.
private struct LoginClearance: View {
    var body: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(
                // Weighted rather than straight, for a reason that is
                // arithmetic: the expanded tile's bottom edge lands at 341 pt on
                // the panel this was designed against, which is INSIDE the ramp.
                // A linear fall leaves the tile's bottom corners flanked by
                // near-bare wallpaper (23%); this holds them at ~46%.
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.80), location: 0.60),
                    // `.black.opacity(0)` rather than `.clear` is style, not
                    // correctness: measured on macOS 26.6, SwiftUI interpolates
                    // gradients PREMULTIPLIED, so the two render byte-identically
                    // — even across hues, where the hazard is usually stated.
                    // Written out because the version of this comment that
                    // claimed `.clear` drags the midpoint would send someone
                    // "fixing" gradients elsewhere on a belief that does not hold.
                    .init(color: .black.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: LockWidgetMetrics.backdropFadeBand)
            Color.clear.frame(height: LockWidgetMetrics.clearBandFloor)
        }
    }
}

/// The blurred cover behind an expanded widget. A thin wrapper whose only job
/// is to own the decode, so `DriftingArtworkBackground` stays a pure function
/// of an image and can be exercised without ImageIO.
private struct ArtworkBackdrop: View {
    let data: [UInt8]?
    @State private var image: CGImage?
    @State private var tone: ArtworkAccent.Tone?

    var body: some View {
        DriftingArtworkBackground(image: image, fallbackTone: tone)
            // Here rather than inside `DriftingArtworkBackground`, which promises
            // to fill whatever it is given: a login-clearance band is a
            // lock-screen concept with no business in a generic backdrop.
            //
            // The one thing that decides whether this WORKS is not the ordering.
            // A mask lays out at its RECEIVER's reported size and centres on it —
            // not at the proposal, not at the screen — which is why
            // `DriftingArtworkBackground` has to pin its own size, and why this
            // silently drew nothing until it did (a square cover made the
            // receiver 1512x1512 and put the band 265 pt below the display).
            //
            // Three things this comment used to claim, all measured false and
            // corrected rather than deleted: the order relative to
            // `ignoresSafeArea` is INERT (identical layout either way); there is
            // no safe area to inset against, because a borderless screen-sized
            // NSHostingView reports `safeAreaInsets` of 0 even on a notched
            // panel, so both calls are belt-and-braces; and there is no overhang
            // to cut, because the backdrop already ends in `.clipped()`.
                .mask { LoginClearance() }
                .ignoresSafeArea()
                // BOTH the decode and the accent are computed off the main actor,
                // in one task. The accent used to be called inline in this body —
                // `ArtworkAccent.extract(from:)` is a full ImageIO decode, and with
                // the cover upgrade on those are 1200 px, ~77 KB bytes. A body
                // re-runs whenever SwiftUI decides to, so that put a blocking decode
                // on the main thread during the expand animation, and it was dead
                // work on every pass after the first: the image below it had already
                // landed, so the tone was only ever the fallback for the frames
                // before it. Every other decode in the app already goes through
                // `blockingCall` for exactly this reason (ArtworkView, ArtworkAccent,
                // the line below it).
                .task(id: data) { [data] in
                    let decoded = await blockingCall {
                        (
                            ArtworkDecoding.thumbnail(from: data, maxSide: ArtworkDecoding.lockScreenMaxSide),
                            ArtworkAccent.extract(from: data)
                        )
                    }
                    guard !Task.isCancelled else { return }
                    image = decoded.0
                    tone = decoded.1
                }
    }
}
