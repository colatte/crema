/// What the menu should say about which display Crema's screen brightness lands
/// on.
///
/// Crema drives the BUILT-IN panel and only it, by decision: a consumed key owes
/// an apply-verify cycle, and a neighbouring app's brightness can be written but
/// never read — measured, every spelling of the level is refused — so an external
/// display offers no level to step from and nothing to verify against
/// (docs/DECISIONS.md: external-brightness-is-write-only). Correct, documented,
/// and also invisible: with a monitor as the main display the brightness key dims
/// the laptop panel nobody is looking at, and no surface said so
/// (docs/DECISIONS.md: brightness-key-target-in-the-menu).
enum BrightnessKeyTargetNotice: Equatable {
    /// Nothing worth saying: the built-in panel is the only display in use, so
    /// there is no other screen to confuse it with — or the claim is not ours to
    /// make, because something else is positioned to take the keys or is drawing
    /// the bar.
    case quiet
    /// A built-in panel alongside at least one other display — the one arrangement
    /// where the target surprises the user.
    case builtInAmongOthers
    /// No built-in panel in use: clamshell, or a Mac that has none. The brightness
    /// write degrades to false there rather than reaching for whatever display
    /// happens to be main, so the honest line is what Crema cannot do.
    case noBuiltInDisplay
}
