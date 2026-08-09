import SwiftUI

/// Now playing on the lock screen: one glass card over the user's own wallpaper,
/// and nothing else.
///
/// **It paints no ground and it has no second state.** Both of those were here
/// and both were removed in the same week, for reasons that turned out to be the
/// same reason (docs/DECISIONS.md: the-lock-surface-is-a-card). A full-screen
/// blurred backdrop cost a clock of its own, a clearance band and a fade whose
/// boundary the eye hunts; a 300 pt expanded tile cost a centred geometry that
/// lands on the login on any panel shorter than 660 pt, a second contrast
/// problem where text sits ON the artwork rather than beside it, and the whole
/// high-resolution cover lookup that existed only to fill it. The level this
/// window occupies is named
/// `kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`; Apple's own tenant
/// there draws one bounded card, and so does every shipping competitor at it.
///
/// What is left rests on the floor the ruler measured
/// (`LockWidgetMetrics.clearBandFloor`) and never moves from it. The system's
/// clock, avatar and password field are all visible and untouched, and this
/// surface draws no clock — with no ground covering theirs, a second one beside
/// it is a defect rather than a feature.
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

    /// The rect that may take a click, in the hosting window's coordinate space,
    /// reported whenever it moves — empty when there is nothing drawn.
    ///
    /// Still needed with the tap gesture gone: the transport controls and the
    /// scrubber are live, and the window cannot compute where they are. It is
    /// the size of the display and the card is a few hundred points of it, so
    /// without this the panel would have to capture everywhere, over a surface
    /// where "everywhere" is the password field (`LockWidgetClickThrough`).
    var onInteractiveRect: ((CGRect) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Two accessibility settings this surface owes an answer to, because it is
    /// the one surface in the app whose ground is a picture the app did not
    /// choose. Apple's instruction is not optional: "if your app doesn't provide
    /// this minimum contrast by default, ensure it at least provides a higher
    /// contrast color scheme when the system setting Increase Contrast is turned
    /// on" — and measured, Increase Contrast changes an `NSVisualEffectView` by
    /// nothing, so every hardening here is the app's own code.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    /// ONE decode for the whole surface.
    ///
    /// It used to be five, and the expensive ones started ON THE CLICK: the
    /// expanded tile owned an `ArtworkView`-style decode whose cache key only
    /// came into existence when the surface grew, so a cold expand animated a
    /// grey rectangle for the whole spring. That state is gone and the decode
    /// stayed here, because the reason generalises — the pixels exist before
    /// anything needs them, at the moment the TRACK resolves, where nobody is
    /// watching.
    @State private var decoded = DecodedCover()

    struct DecodedCover {
        var image: CGImage?
        var tone: ArtworkAccent.Tone?
    }

    private var track: NowPlaying? { coordinator.nowPlaying }

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
        .animation(SurfaceAnimation.appearFade(vanishing: track == nil), value: track == nil)
        // The media stopping is the one edge the surface cannot observe from
        // inside itself: the card leaves the hierarchy and takes its reporter
        // with it, so the LAST rect it published would stay armed over bare
        // wallpaper. Settled here, while the fade is running.
        .onChange(of: track == nil) { _, empty in
            if empty { onInteractiveRect?(.zero) }
        }
        // Keyed on the bytes rather than the snapshot: the snapshot is rewritten
        // every second by the position tick, and re-decoding once a second for
        // the same song would put ImageIO on a treadmill.
        .task(id: track?.artworkData) { [bytes = track?.artworkData] in
            // ImageIO is blocking and uncancellable, so it goes off the
            // concurrency pools entirely — the same exit `ArtworkView` takes, and
            // for the same reason.
            let fresh = await blockingCall { () -> DecodedCover in
                let image = ArtworkDecoding.thumbnail(from: bytes, maxSide: ArtworkDecoding.displayMaxSide)
                return DecodedCover(image: image, tone: image.flatMap(ArtworkAccent.extract))
            }
            guard !Task.isCancelled else { return }
            decoded = fresh
        }
    }

    // MARK: - Layers

    /// The card rests on the floor of the band the ruler measured, and that is
    /// its only placement rule. It was once one view at two sizes, with the
    /// expanded state centred on the display — which is exactly the geometry
    /// that put a 300 pt tile onto the login on any panel shorter than 660 pt,
    /// because a centred object's position is a function of a height this file
    /// never sees.
    private func surface(_ track: NowPlaying) -> some View {
        card(track)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, LockWidgetMetrics.bottomInset)
    }

    private func card(_ track: NowPlaying) -> some View {
        VStack(spacing: LockWidgetMetrics.gap) {
            head(track)
            ScrubberRow(
                position: coordinator.nowPlaying?.position ?? 0,
                duration: coordinator.nowPlaying?.duration,
                enabled: coordinator.commandsAvailable,
                // No digits. At two metres a 10 pt cap subtends about 2.5
                // arcminutes, under the 5 a 20/20 eye needs to resolve a letter
                // it already expects — they were not being read, they were
                // occupying the row. The bar keeps the position.
                showsDuration: false,
                onScrub: { coordinator.scrub(to: $0) }
            )
            .frame(height: LockWidgetMetrics.scrubberHeight)
            TransportControls(
                isPlaying: track.isPlaying,
                enabled: coordinator.commandsAvailable,
                skipEnabled: coordinator.skipControlsEnabled,
                buttonSide: LockWidgetMetrics.transportSide,
                primarySide: LockWidgetMetrics.transportPrimarySide,
                spacing: LockWidgetMetrics.transportSpacing,
                onPrevious: { coordinator.previousTrack() },
                onPlayPause: { coordinator.togglePlayPause() },
                onNext: { coordinator.nextTrack() }
            )
        }
        .padding(LockWidgetMetrics.padding)
        .frame(width: LockWidgetMetrics.cardWidth)
        .background { cardSurface }
        // Injected from the surface's own decode rather than derived again by
        // `.artworkAccent(from:)`, which would open a second ImageIO path over
        // the same bytes.
        .environment(\.artworkAccent, decoded.tone)
        .environment(\.colorScheme, .dark)
        // The reported rect attaches HERE, above the placement frame in
        // `surface(_:)` and never under it. Under it it would describe the
        // LAYOUT frame, which is this width by the whole height of the display —
        // a capture region sitting over the password field.
        //
        // No `contentShape`, no tap gesture and no `.isButton` trait any more:
        // the card is not itself a control. Its transport buttons and its
        // scrubber are, and they carry their own.
        .background { interactiveRectReporter }
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

    /// The card's own material — real vibrancy, and the family's own border with
    /// it, after two rounds of neither.
    ///
    /// It refused `vibrantSurface` on a reason that expired: "it would sample its
    /// own backdrop and go flat" was true while this surface painted one, and the
    /// backdrop is gone. Measured on hardware 2026-08-08
    /// (`scripts/probes/lockscreen-card-material.swift`): a real
    /// `NSVisualEffectView` with `.behindWindow` blending DOES sample the shield
    /// from a raised space at level 400, and the `.withinWindow` control swatch
    /// behaved, so the reading means something.
    ///
    /// Adopting the shared modifier also restores the SPECULAR the card was
    /// missing. It took only the black rim, under a `SurfaceChrome` comment
    /// saying the pair splits the work — the rim carries the boundary over a
    /// light backdrop, the specular carries it over a dark one — which is the
    /// half a lock screen is made of.
    ///
    /// `.underWindowBackground` rather than the skins' `.hudWindow`: the ground
    /// has to be certain over a wallpaper the app does not choose, and 0.80 of
    /// tint against 0.40 is where that certainty comes from. The fill above it is
    /// 0.42 rather than the 0.52 that shipped — the material is doing more of the
    /// work now, and the point of a heavier material is to spend less alpha
    /// hiding the wallpaper behind flat black.
    private var cardSurface: some View {
        let shape = RoundedRectangle(cornerRadius: LockWidgetMetrics.cornerRadius, style: .continuous)
        return shape
            .fill(.black.opacity(reduceTransparency ? 1 : 0.42))
            .vibrantSurface(in: shape, material: .underWindowBackground)
            // The preference means "do not put a translucent layer over content",
            // and a card whose ground is the user's wallpaper is exactly that.
            // The substitute is a measured system value rather than a guess:
            // `windowBackgroundColor` under darkAqua is white 0.1176, which is
            // where AppKit itself puts an opaque dark surface.
            .background(reduceTransparency ? Color(white: 0.1176) : .clear, in: shape)
            // Three members, tight to broad, rather than one. A single shadow
            // is a halo; a stack is height, because the near member draws the
            // contact and the far one draws the distance. Amberol's own
            // stylesheet is the reference and this is its shape scaled up —
            // 0 1px 6px at 0.30, 0 2px 12px at 0.15, 0 6px 32px at 0.10.
            //
            // The broad member is deliberately kept off the floor: at radius 30
            // with y 10 its penumbra reaches roughly 260, which is above the
            // login's measured top of 180 but below `clearBandFloor`. The
            // constant means "no drawn SURFACE below this line" and a shadow is
            // not a surface — stated here because the alternative reading would
            // have every design in the round quietly violating it.
            .shadow(color: .black.opacity(0.30), radius: 3, y: 1)
            .shadow(color: .black.opacity(0.15), radius: 12, y: 3)
            .shadow(color: .black.opacity(0.10), radius: 30, y: 10)
    }

    private func head(_ track: NowPlaying) -> some View {
        HStack(spacing: LockWidgetMetrics.gap) {
            ArtworkFrame(
                image: decoded.image,
                side: LockWidgetMetrics.thumbnailSide,
                cornerRadius: LockWidgetMetrics.thumbnailRadius
            )
            // The cover gets a shadow of its own, which is what makes it an
            // object resting ON the card rather than a picture printed into it.
            // Tuneful's mini player does exactly this at a comparable size
            // (black 0.30, radius 5, y 2); the numbers here are that shape,
            // scaled to 72 pt.
            .shadow(color: .black.opacity(0.30), radius: 6, y: 2)
            TrackTextStack(
                title: track.title,
                artist: track.artist,
                alignment: .leading,
                // The app's only glanceable surface takes the only other scale
                // there is, declared beside the family's in `TrackTextStack`.
                // Apple publishes macOS default 13 pt against minimum 10, and
                // the family ramp sits under the first and on the second.
                scale: .glance,
                artistWeight: .medium
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            WaveformGlyph(animating: track.isPlaying)
        }
        .frame(height: LockWidgetMetrics.headHeight)
    }
}
