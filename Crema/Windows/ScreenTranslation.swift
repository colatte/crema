import AppKit
import os

/// AppKit border: translates NSScreen into pure ScreenDescription values.
///
/// Coordinate-space contract — every layer below assumes it, and the check is
/// visual, so keep it exact:
/// - Everything is in AppKit global screen coordinates: origin at the
///   bottom-left of the primary screen, y growing upward.
/// - `NSScreen.frame` is already in that global space — secondary displays
///   arrive with offset (possibly negative) origins.
/// - `ScreenGeometry.frame` carries that global rect verbatim. Frame rules
///   compute relative to it (midX, maxY…), so their output is also a global
///   rect for that screen.
/// - That rect goes straight to `NSPanel.setFrame` with no conversion: no
///   flipping, no per-screen local space anywhere in the pipeline.
enum ScreenTranslation {
    /// Describes all connected screens, carrying the real notch geometry.
    @MainActor
    static func describeAll() -> [ScreenDescription] {
        NSScreen.screens.compactMap(describe)
    }

    private static let logger = Logger.crema("Windows")

    @MainActor
    static func describe(_ screen: NSScreen) -> ScreenDescription? {
        // A screen this translation drops never gets a panel — no HUD, no now
        // playing on that display. compactMap erases the evidence, so each
        // drop logs the reason (virtual displays and screen-sharing sessions
        // are the known offenders).
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            logger.notice("screen \(screen.localizedName, privacy: .public) has no NSScreenNumber — dropped from the panel roster")
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        // displayID → UUID happens here, at the border: Preferences and the
        // domain only ever see the stable UUID, never the numeric ID.
        guard let uuid = displayUUID(for: displayID) else {
            logger.notice(
                "display \(displayID, privacy: .public) (\(screen.localizedName, privacy: .public)) has no resolvable UUID — dropped from the panel roster"
            )
            return nil
        }

        return ScreenDescription(
            id: uuid,
            geometry: geometry(of: screen),
            isInternal: CGDisplayIsBuiltin(displayID) != 0
        )
    }

    /// displayID → the domain's stable key, in one place. The panel roster starts
    /// from an NSScreen and a neighbouring app reports raw display IDs; both must
    /// land on the same UUID or the two would disagree about which screen is which.
    nonisolated static func displayUUID(for displayID: CGDirectDisplayID) -> DisplayUUID? {
        guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return DisplayUUID(rawValue: CFUUIDCreateString(nil, uuidRef) as String)
    }

    /// The reverse trip: the domain's key back to the numeric ID a neighbouring
    /// app speaks. Nil for a display that is no longer attached — the honest
    /// answer for a command with nowhere to land.
    nonisolated static func displayID(for uuid: DisplayUUID) -> CGDirectDisplayID? {
        activeDisplayIDs().first { displayUUID(for: $0) == uuid }
    }

    /// The built-in screen's numeric ID — what `display == nil` means when a
    /// command has to name a display explicitly.
    nonisolated static func builtInDisplayID() -> CGDirectDisplayID? {
        activeDisplayIDs().first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// What the menu's brightness row is decided from: whether a built-in panel is
    /// among the ACTIVE displays, and how many displays there are at all.
    ///
    /// Deliberately the same list `builtInDisplayID()` resolves the brightness write
    /// target from, and deliberately NOT the panel roster, which disagrees: the
    /// roster drops any display with no NSScreenNumber or no resolvable UUID, and
    /// AppKit collapses a mirror set to a single NSScreen. Sharing the list is what
    /// keeps the menu from contradicting the hardware — wherever this reports no
    /// built-in entry, the write returns false for the same reason, so the sentence
    /// and the behavior fail together instead of disagreeing.
    nonisolated static func activeDisplayCensus() -> (hasBuiltIn: Bool, count: Int) {
        let ids = activeDisplayIDs()
        return (ids.contains { CGDisplayIsBuiltin($0) != 0 }, ids.count)
    }

    /// The displays a brightness key can aim at, in CoreGraphics' global display
    /// space — the space `CGEvent.location` reports the pointer in, so the rule
    /// that pairs the two never converts between spaces.
    ///
    /// The SAME active list `builtInDisplayID()` writes through and
    /// `activeDisplayCensus()` is read from, for the reason spelled out above: a
    /// key aiming by one list while the menu speaks from another is how a true
    /// sentence ends up over the opposite behavior. Nonisolated because the
    /// swallow decision is made on the event tap's thread, which cannot ask
    /// NSScreen.
    nonisolated static func brightnessKeyDisplays() -> [BrightnessKeyDisplay] {
        activeDisplayIDs().map {
            BrightnessKeyDisplay(bounds: CGDisplayBounds($0), isBuiltIn: CGDisplayIsBuiltin($0) != 0)
        }
    }

    /// The same screen in the domain's own currency. Needed because nil and this
    /// UUID name one display: the neighbour integration reports displays by ID and
    /// names the built-in like any other, so an actuator handed that UUID must
    /// recognise it as its own rather than as somebody else's screen.
    nonisolated static func builtInDisplayUUID() -> DisplayUUID? {
        builtInDisplayID().flatMap(displayUUID(for:))
    }

    /// Read fresh on every call: numeric IDs are reassigned across sessions and
    /// reconnections, so a cached list would eventually address another screen.
    private nonisolated static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// Reads the notch geometry from NSScreen.
    ///
    /// `safeTop` is the slit height (`safeAreaInsets.top`), not the menu-bar
    /// height — the two differ (menu bar ~37 pt vs slit ~32 pt), and the notch
    /// surface must anchor to the physical slit. The menu-bar height, if ever
    /// needed, would be `frame.maxY − visibleFrame.maxY`; we deliberately do not
    /// use it here.
    ///
    /// The auxiliary areas flank the slit; their widths let the frame rule
    /// derive the slit width (`frame.width − auxLeft − auxRight`). On a display
    /// without a notch these are nil and safeAreaInsets.top is 0, so all three
    /// stay zero and the geometry reads as "no notch" (WindowManager then
    /// resolves any orphan notch preference to the card).
    @MainActor
    private static func geometry(of screen: NSScreen) -> ScreenGeometry {
        ScreenGeometry(
            frame: screen.frame,
            safeTop: screen.safeAreaInsets.top,
            auxLeft: screen.auxiliaryTopLeftArea?.width ?? 0,
            auxRight: screen.auxiliaryTopRightArea?.width ?? 0,
            scale: screen.backingScaleFactor
        )
    }
}
