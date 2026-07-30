/// What the menu should say about which display Crema's screen brightness lands
/// on.
///
/// A brightness key acts on the display under the POINTER: Crema applies it on the
/// built-in panel, the one display it reads and writes itself, and hands the key to
/// the system for every other display rather than moving a screen the user is not
/// looking at (docs/DECISIONS.md: brightness-key-follows-the-pointer). The rule is
/// invisible while it works — the key simply does what was expected — so the menu
/// states it in the one arrangement where it explains something, which is also the
/// arrangement where the old behavior read as a bug
/// (docs/DECISIONS.md: brightness-key-target-in-the-menu).
enum BrightnessKeyTargetNotice: Equatable {
    /// Nothing worth saying: the built-in panel is the only display in use, so the
    /// pointer can only ever be on it — or the claim is not ours to make, because
    /// something else is positioned to take the keys or is drawing the bar.
    case quiet
    /// A built-in panel alongside at least one other display — the one arrangement
    /// where the rule is worth explaining, because the same key does two different
    /// things depending on where the pointer rests.
    case builtInAmongOthers
    /// No built-in panel in use: clamshell, or a Mac that has none. Crema applies no
    /// brightness key at all there — every display in use belongs to someone else,
    /// and the write would degrade to false anyway — so the honest line is what
    /// Crema cannot do.
    case noBuiltInDisplay
}
