import SwiftUI

/// Whether the cover behind the lock-screen surface is allowed to move.
///
/// Pure and static so the rule is a test rather than a thing you have to lock
/// your Mac to check, and so the three vetoes live in one place instead of
/// being re-derived at each `if`.
enum ArtworkDrift {
    /// How long the surface may drift before it settles.
    ///
    /// Every other animation in this app answers to a moment: a HUD lives 1.5 s,
    /// a morph is over in half of one. This surface can be lit on an idle desk
    /// all night, and a `repeatForever` transform there stops being liveliness
    /// and becomes spent battery — and, on the displays that have it, a
    /// rectangle burned into the panel. Three minutes is long enough that
    /// anyone who glances at the Mac sees it breathing, and short enough that
    /// nobody sleeps beside it.
    static let settlesAfter: Duration = .seconds(180)

    /// Three vetoes, none reducible to another: the user asking that nothing
    /// move (Reduce Motion), the system asking that nothing be spent on
    /// movement (Low Power Mode), and the surface having been lit long enough
    /// that motion turned into wear.
    ///
    /// Callers key their `onChange` on THIS value, never on one of the inputs —
    /// keying on an input is how one veto ends up observed and the others
    /// forgotten (the lesson `WaveformGlyph.dances` already carries).
    ///
    /// What this predicate must NOT be extended to cover: the clock drawn over
    /// the same surface (`LockClockView`). Two of the three vetoes simply do not
    /// reach it — a digit replacing another is not motion, and a wake once a
    /// minute is not the `repeatForever` transform Low Power was written for.
    /// The third actively points the other way. `settlesAfter` exists because a
    /// picture still moving on an idle desk at 4 a.m. is wear; a clock still
    /// running at 4 a.m. is the entire point of one, and folding it in here
    /// would ship a clock frozen at the minute of the lock.
    static func drifts(reduceMotion: Bool, lowPower: Bool, settled: Bool) -> Bool {
        !reduceMotion && !lowPower && !settled
    }

    /// The drift's extremes, as a scale and a fractional offset. Deliberately
    /// small: the point is that the picture is never quite still, not that it
    /// travels. Overscan (`LockWidgetMetrics.backdropOverscan`) is what keeps
    /// the larger end from exposing an edge.
    static let restingScale: CGFloat = 1.0
    static let travelledScale: CGFloat = 1.10
    static let travel: CGFloat = 0.025
    static let cycle: Double = 26

    /// How long the drift takes to come to rest when a veto engages or the
    /// settle timer fires. Short enough to read as "it stopped", long enough not
    /// to be the jump it replaced.
    static let settleDuration: Double = 0.6
}

/// The cover, blurred past recognition and drifting, filling whatever it is
/// given. It is scenery: the picture the eye rests on while reading the words
/// in front of it, which is why it is blurred rather than merely dimmed — a
/// legible photograph behind text is two things asking to be read.
///
/// Nothing else in `Styles/` blurs or animates an image, so this is new work
/// rather than a variation. It is also the only continuous animation in the app
/// besides `WaveformGlyph`, and it answers to one more veto than that one does.
struct DriftingArtworkBackground: View {
    let image: CGImage?
    /// The tone pulled from the cover, used when there is no cover to show.
    var fallbackTone: ArtworkAccent.Tone?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lowPowerMode) private var lowPower

    @State private var settled = false
    @State private var travelled = false

    /// An absent mirror is an absent veto — previews and the Settings tiles
    /// have no power state to consult and must not be frozen by its absence.
    private var lowPowerIsOn: Bool { lowPower?.isLowPower ?? false }

    private var drifts: Bool {
        ArtworkDrift.drifts(
            reduceMotion: reduceMotion,
            lowPower: lowPowerIsOn,
            settled: settled
        )
    }

    var body: some View {
        // The container is load-bearing, and it took a measurement to learn it.
        // `Image.resizable().scaledToFill()` reports a LAYOUT size larger than
        // the proposal — a square cover on a 1512x982 panel makes this view
        // 1512x1512 — and everything downstream inherits that lie. Measured on a
        // real screen-sized panel: the login-clearance mask, which lays out at
        // its RECEIVER's size and centres, landed 265 pt below the display, so
        // the band that keeps the password field readable never appeared; and
        // the ZStack that carries the clock grew with it, putting the clock at
        // y = -177, off screen entirely. Both failed ONLY when there was a
        // cover, which is the normal case — album art is square.
        //
        // `Color.clear.overlay { }` pins the size, the same way `ArtworkView`
        // already does it. A flexible `.frame(maxWidth:.infinity,
        // maxHeight:.infinity)` does NOT: measured, the receiver still reported
        // 1512x1512, because a flexible frame lets an oversized child overflow.
        // `.clipped()` below does not help either — it clips pixels and leaves
        // the reported size alone.
        Color.clear.overlay {
            picture
        }
        .scaleEffect(
            LockWidgetMetrics.backdropOverscan
                * (travelled ? ArtworkDrift.travelledScale : ArtworkDrift.restingScale)
        )
        .offset(
            x: travelled ? ArtworkDrift.travel * 100 : -ArtworkDrift.travel * 100,
            y: travelled ? ArtworkDrift.travel * 100 : -ArtworkDrift.travel * 100
        )
        // Two animations, because stopping is not the reverse of starting. While
        // drifting it is the endless cycle; when a veto engages — or the settle
        // timer fires — `travelled` flips with the cycle already gone, and a nil
        // animation there made the full-screen image JUMP to its resting scale
        // and offset in one frame. Reduce Motion is the one preference that must
        // never be answered with a teleport, and it was the likeliest way to
        // reach this. So the stop is a plain ease to rest, itself suppressed
        // under Reduce Motion (a settle with no travel is already dry).
        .animation(
            drifts
                ? .easeInOut(duration: ArtworkDrift.cycle).repeatForever(autoreverses: true)
                : (reduceMotion ? nil : .easeOut(duration: ArtworkDrift.settleDuration)),
            value: travelled
        )
        .clipped()
        .allowsHitTesting(false)
        // Keyed on the predicate, not on any single veto: a per-input key is how
        // one of the three ends up observed and the others forgotten.
        .onChange(of: drifts) { _, moving in travelled = moving }
        .task {
            travelled = drifts
            try? await Task.sleep(for: ArtworkDrift.settlesAfter)
            settled = true
        }
    }

    @ViewBuilder
    private var picture: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .blur(radius: LockWidgetMetrics.backdropBlur, opaque: true)
        } else {
            // No cover: the accent's own hue over black, or a neutral ground
            // when the cover was monochrome and the accent abstained.
            //
            // OPAQUE, and that is a correctness property rather than a look.
            // This branch used to be translucent (0.35 → 0.75), which left
            // the lock shield showing through at about 65% at the top of the
            // display — where macOS draws its own clock, directly under the
            // one this surface now draws. Two states reach here: a track
            // whose player published no cover (the JXA fallback never does)
            // while `expanded` survives from the previous track, and the
            // first frames of EVERY expansion, before the async decode in
            // `ArtworkBackdrop` lands. Gating the clock on "has cover bytes"
            // would close the first and miss the second, because bytes in
            // hand are not an image on screen.
            LinearGradient(
                colors: [
                    (fallbackTone?.color ?? .gray).opacity(0.35),
                    .black.opacity(0.75),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .background(Color.black)
        }
    }
}
