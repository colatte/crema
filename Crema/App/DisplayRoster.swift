import Observation

/// The connected displays, as the per-display Settings list reads them: the
/// border's own descriptions (name, geometry, built-in), replaced whole at every
/// display edge the app already handles.
///
/// Reactive, and deliberately unlike its Settings neighbours: the seeded-once
/// seeds its mirrors ONCE and re-reads only when its own picker writes — a
/// pinned-latent tradeoff (docs/CONTRACTS.md: S4), which
/// costs a stale value there. A list whose rows ARE the displays cannot take that
/// deal: a row surviving its monitor is a control over a screen the user cannot
/// see, and a display plugged in with the window open would have no row at all
/// until Settings is closed and reopened.
///
/// Fed by the SAME reading that builds the panels (`AppCore.applyScreenRoster`),
/// never by a second `describeAll()`. Two readings can disagree — a display that
/// left between them — and then the tab lists a display no panel carries while a
/// panel draws for one no row can reach; two lists disagreeing about which screen
/// is which is exactly the class docs/DECISIONS.md: hud-target-is-a-role rules on,
/// where a true sentence ends up over the opposite behaviour.
///
/// The menu bar does NOT read this. Its status block pull-reads the event-tap
/// chain, and each of those readings resets the min/max latency counters of every
/// tap on the machine, so a roster the menu observed would turn every display
/// change into a system-wide probe — the reason the automation monitor stays out
/// of that body too (docs/DECISIONS.md: one-screen-reading-per-edge).
@MainActor
@Observable
final class DisplayRoster {
    private(set) var displays: [ScreenDescription] = []

    /// Guarded like the other read mirrors: an unchanged topology invalidates no
    /// view. That is the common case rather than the rare one —
    /// `didChangeScreenParameters` fires for a resolution change, a rearrangement
    /// or a display waking, and only some of those move this list.
    func update(_ new: [ScreenDescription]) {
        if new != displays { displays = new }
    }
}
