import CoreGraphics
import SwiftUI

/// The closed set of skins, switchable at runtime per display.
/// An enum — not type erasure: the set is fixed, dispatch is a switch, and the
/// raw value doubles as the Preferences persistence format.
enum Style: String, CaseIterable, Equatable, Sendable {
    case notch
    case card
    case classic

    /// The style a display actually RENDERS: the notch skin needs a physical
    /// slit, so a notch DECLARATION on a slitless panel — an external monitor, or
    /// a Mac with no notch at all (mini, Studio, iMac, older Air) — renders as
    /// the card, the floating skin. The one place that maps a declared style to
    /// the drawn one: the WindowManager builds every panel through it and Settings
    /// gates its Card-scoped controls on the same answer, so the two cannot
    /// disagree by accident (docs/DECISIONS.md: rendered-style-gates-settings).
    func resolved(on geometry: ScreenGeometry) -> Self {
        self == .notch && geometry.safeTop <= 0 ? .card : self
    }

    /// Pure frame-rule dispatch — same purity and testability as each style's
    /// own rule; receives ScreenGeometry, never NSScreen.
    func frame(for state: PresentationState, on geometry: ScreenGeometry) -> CGRect {
        switch self {
        case .notch:
            NotchStyle().frame(for: state, on: geometry)
        case .card:
            CardStyle().frame(for: state, on: geometry)
        case .classic:
            ClassicStyle().frame(for: state, on: geometry)
        }
    }

    /// Stable hover regions for the active skin. Dispatch mirrors `frame`.
    func hoverRegions(on geometry: ScreenGeometry) -> SurfaceHoverRegions? {
        switch self {
        case .notch:
            NotchStyle().hoverRegions(on: geometry)
        case .card:
            CardStyle().hoverRegions(on: geometry)
        case .classic:
            ClassicStyle().hoverRegions(on: geometry)
        }
    }

    /// Click-invoke zone for the active skin. Dispatch mirrors `frame`.
    func invokeZone(on geometry: ScreenGeometry) -> CGRect? {
        switch self {
        case .notch:
            NotchStyle().invokeZone(on: geometry)
        case .card:
            CardStyle().invokeZone(on: geometry)
        case .classic:
            ClassicStyle().invokeZone(on: geometry)
        }
    }

    /// Per-state surface sizes for the active skin. Dispatch mirrors `frame`.
    func stateSizes(on geometry: ScreenGeometry) -> SurfaceStateSizes? {
        switch self {
        case .notch:
            NotchStyle().stateSizes(on: geometry)
        case .card:
            CardStyle().stateSizes(on: geometry)
        case .classic:
            ClassicStyle().stateSizes(on: geometry)
        }
    }

    /// Fixed window frame for the active skin (the view animates the surface
    /// inside it). Same partition as `stateSizes`; dispatch mirrors `frame`.
    func windowFrame(on geometry: ScreenGeometry) -> CGRect? {
        switch self {
        case .notch:
            NotchStyle().windowFrame(on: geometry)
        case .card:
            CardStyle().windowFrame(on: geometry)
        case .classic:
            ClassicStyle().windowFrame(on: geometry)
        }
    }

    /// Which window edge the surface hangs from — the panel pins the reported
    /// interactive region to it. The top-edge skins hang from the top; the
    /// classic block sits on its bottom line and grows up.
    var surfaceVerticalAnchor: SurfaceVerticalAnchor {
        self == .classic ? .bottom : .top
    }

    /// How a hover commits to the Coordinator. The notch rides the accident-prone
    /// top edge, so it goes through the debounced hover-intent; the floating
    /// styles commit immediately — stable detection already removed the spurious
    /// toggles that made hover loop, so the extra delay would only cost
    /// responsiveness.
    enum HoverCommit { case immediate, debounced }

    var hoverCommit: HoverCommit {
        self == .notch ? .debounced : .immediate
    }

    /// Per-edge exit band, dispatched to the concrete style (the notch is
    /// directional; the floating styles keep the uniform default). All three
    /// styles retarget hover to the rendered surface — the same truth clicks
    /// use (docs/DECISIONS.md: hover-follows-the-eye).
    var hoverExitMargins: SurfaceHoverRegions.Margins {
        switch self {
        case .notch: NotchStyle().hoverExitMargins
        case .card: CardStyle().hoverExitMargins
        case .classic: ClassicStyle().hoverExitMargins
        }
    }

    /// User-facing name (String Catalog; English as source language).
    var displayName: String {
        switch self {
        case .notch:
            String(localized: "style.notch", defaultValue: "Notch")
        case .card:
            String(localized: "style.card", defaultValue: "Card")
        case .classic:
            String(localized: "style.classic", defaultValue: "Classic")
        }
    }

    @MainActor @ViewBuilder
    func makeView(coordinator: Coordinator, displayPolicy: SurfaceDisplayPolicy) -> some View {
        switch self {
        case .notch:
            NotchStyle().makeView(coordinator: coordinator, displayPolicy: displayPolicy)
        case .card:
            CardStyle().makeView(coordinator: coordinator, displayPolicy: displayPolicy)
        case .classic:
            ClassicStyle().makeView(coordinator: coordinator, displayPolicy: displayPolicy)
        }
    }
}
