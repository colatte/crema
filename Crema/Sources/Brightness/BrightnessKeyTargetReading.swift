import CoreGraphics

/// The border half of the pointer rule: the live cursor and the display bounds
/// the rule reasons over.
///
/// Nonisolated by necessity. The swallow decision is synchronous and runs on the
/// event tap's own thread, where there is no hop to take and AppKit is not ours
/// to call — so both readings come from CoreGraphics, which answers on any
/// thread: the cursor from a null event, the bounds from the SAME active-display
/// list the brightness write resolves its target from and the menu reads its
/// census from. Sharing that list is what keeps the key, the write and the
/// menu's sentence from disagreeing about how many displays exist; the panel
/// roster deliberately would not, since it drops displays with no NSScreenNumber
/// or no resolvable UUID and collapses a mirror set to one NSScreen.
///
/// Read fresh at every press rather than snapshotted at the display-topology
/// edge. A snapshot buys nothing here and costs a lock, an invalidation edge and
/// a window in which a key aims at a display that already left. These are local,
/// side-effect-free CoreGraphics reads — nothing like `CGGetEventTapList`, whose
/// every call resets the latency counters of every tap on the machine — and they
/// happen on no poll: only a screen-brightness key-DOWN pays, never a key-up,
/// never the menu.
enum BrightnessKeyTargetReading {
    static func target() -> BrightnessKeyTarget {
        BrightnessKeyTargeting.target(pointer: pointer(), among: ScreenTranslation.brightnessKeyDisplays())
    }

    /// A null CGEvent carries the current cursor location, in the same global
    /// display space the bounds are in. Nil only if the event cannot be minted,
    /// which is not the same fact as "no display" — both answer `.unknown`, and
    /// neither guesses.
    static func pointer() -> CGPoint? {
        CGEvent(source: nil)?.location
    }
}
