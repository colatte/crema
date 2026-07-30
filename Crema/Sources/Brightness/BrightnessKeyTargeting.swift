import CoreGraphics

/// Which display a screen-brightness key acts on.
///
/// `.anotherDisplay` and `.unknown` mean the same thing to most callers and are
/// still kept apart: one is a refusal, the other is a blank, and only the second
/// would be a defect if it became common.
enum BrightnessKeyTarget: Equatable, Sendable {
    /// The built-in panel: the one display this app reads and writes itself, and
    /// the display every actuator here spells `nil`.
    case builtIn
    /// A display whose brightness does not live behind DisplayServices. Carries no
    /// identity because nothing dials one — a field nobody reads goes stale, and
    /// adding it back is one stored property.
    case anotherDisplay
    /// The pointer names no display: none attached, or a reading outside every
    /// display's bounds. Answering a display here would be a guess, and a guess
    /// moves a screen.
    case unknown
}

/// A display as this rule sees it. `bounds` is in CoreGraphics' global display
/// space — origin at the top-left of the main display, y growing DOWN — which is
/// the space `CGEvent.location` reports the pointer in, so the rule never
/// converts between spaces and has no sign to get wrong.
struct BrightnessKeyDisplay: Equatable, Sendable {
    let bounds: CGRect
    let isBuiltIn: Bool
}

/// The rule: a brightness key acts on the display under the POINTER — what the
/// display utilities that own these keys already do, and what a person reading a
/// screen expects the key over it to change
/// (docs/DECISIONS.md: brightness-key-follows-the-pointer).
///
/// Pure over values, so every arrangement is a test instead of a hardware trip.
/// Four properties carry the weight:
///
/// - There is NO fallback to the built-in panel. That fallback is the reported
///   bug. Clamshell therefore needs no branch of its own — with no built-in among
///   the bounds the rule never answers `.builtIn` — and a pointer nobody can
///   place answers `.unknown` rather than picking a screen.
/// - A single display answers itself, pointer or no pointer: with one screen
///   attached the pointer disambiguates nothing, so a failed reading must not
///   disable the keys on the Mac that has exactly one panel. Not a disguised
///   fallback — in clamshell the single display is the external one and is
///   answered as such.
/// - Bounds are half-open on both axes, the way CoreGraphics tiles them, so a
///   point on a seam belongs to exactly one display and the answer never depends
///   on list order. The load-bearing seam is a monitor placed ABOVE the laptop:
///   the laptop's menu bar and the monitor's bottom row sit on the same line, and
///   in this space that line is the laptop's `minY`, so the laptop owns it.
/// - A mirror set reports one rectangle per display, so its point is inside both
///   and the tie-break is explicit rather than positional.
enum BrightnessKeyTargeting {
    static func target(pointer: CGPoint?, among displays: [BrightnessKeyDisplay]) -> BrightnessKeyTarget {
        guard let display = display(under: pointer, among: displays) else { return .unknown }
        return display.isBuiltIn ? .builtIn : .anotherDisplay
    }

    private static func display(under pointer: CGPoint?, among displays: [BrightnessKeyDisplay]) -> BrightnessKeyDisplay? {
        guard displays.count > 1 else { return displays.first }
        guard let pointer else { return nil }
        let containing = displays.filter { contains($0.bounds, pointer) }
        // Mirroring: the built-in wins the tie. It is the panel this app lights,
        // and handing the key back for a screen we are literally driving would be
        // the original bug with its sign flipped.
        return containing.first(where: \.isBuiltIn) ?? containing.first
    }

    private static func contains(_ bounds: CGRect, _ point: CGPoint) -> Bool {
        point.x >= bounds.minX && point.x < bounds.maxX
            && point.y >= bounds.minY && point.y < bounds.maxY
    }
}
