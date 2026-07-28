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
        guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            logger.notice(
                "display \(displayID, privacy: .public) (\(screen.localizedName, privacy: .public)) has no resolvable UUID — dropped from the panel roster"
            )
            return nil
        }
        let uuid = CFUUIDCreateString(nil, uuidRef) as String

        return ScreenDescription(
            id: DisplayUUID(rawValue: uuid),
            geometry: geometry(of: screen),
            isInternal: CGDisplayIsBuiltin(displayID) != 0
        )
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
