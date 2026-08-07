import AppKit
import os

/// Capability: put a window somewhere the lock shield cannot cover it.
///
/// A capability rather than a function because the honest answer on some future
/// macOS is "no" — `isAvailable` is what every caller checks first, and a false
/// there degrades the feature instead of crashing it.
@MainActor
protocol RaisedSpace: AnyObject {
    var isAvailable: Bool { get }
    /// Idempotent and convergent by construction: WindowServer takes the window
    /// out of whatever space it was in and puts it in ours, so calling it again
    /// after a wake costs nothing and repairs everything.
    func adopt(_ window: NSWindow)
}

/// The lock screen border: SkyLight private framework via dlopen/dlsym.
///
/// ## Why this exists at all, when the panel layer refuses the same framework
///
/// `docs/LOCKSCREEN-INVESTIGATION.md` spent five window LEVELS proving nothing
/// composites over the lock shield, and drew the wrong conclusion from a sound
/// result. Level orders windows WITHIN a space; the shield IS a space, at
/// absolute level 300. No level lifts a window out of the space it lives in, so
/// varying only the level could never tell "impossible" from "wrong knob".
///
/// The knob is here. The ladder of absolute space levels, read off
/// `Lakr233/SkyLightWindow` (MIT) and confirmed on hardware:
///
///     0   default             300  the lock shield      500  boot progress
///     100 setup assistant     400  notification centre  600  VoiceOver
///     200 security agent          at the screen lock
///
/// Create a space, set its absolute level to 400, show it, move the window in.
/// Proven twice on macOS 26 / Apple Silicon by `scripts/probes/`: the space
/// probe showed a raised window survives the shield while a control at
/// `kCGMaximumWindowLevel` does not, and the events probe showed clicks reach it
/// there — 10 of them, each stamped LOCKED by the probe's own session read.
///
/// `NSPanelPresentationPanel` still refuses this framework and should: its
/// panels have no business over a lock screen, and the WindowServer-instability
/// caution recorded there is about using private window APIs for ordinary
/// surfaces. This is the one surface whose entire premise is the other side of
/// that shield.
///
/// ## The half that is not private
///
/// `NSWindow.canBecomeVisibleWithoutLogin` is public and has been since macOS
/// 10.5 (`NSWindow.h`). Without it AppKit will not show a window while no
/// session is logged in, and the space alone does not save you — the level
/// sweep missed this too.
@MainActor
final class SkyLightSpaceBridge: RaisedSpace {
    typealias SymbolResolver = (_ name: String) -> UnsafeMutableRawPointer?

    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias SpaceCreateFn = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevelFn = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpacesFn = @convention(c) (Int32, CFArray) -> Int32
    private typealias SpaceAddWindowsFn = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"

    /// `kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`. One above the
    /// shield's 300 and below boot progress and VoiceOver, which is the correct
    /// neighbourhood: this surface should lose to a machine that is booting and
    /// to an accessibility technology, and win against a lock screen.
    private static let aboveScreenLock: Int32 = 400

    /// The fourth argument to `SLSSpaceAddWindowsAndRemoveFromSpaces`, which is
    /// a bitmask of which space sets to touch. Every published use of this call
    /// passes 7; nobody outside Apple has documented the individual bits, so it
    /// is carried as the constant it is rather than dressed up as a computation.
    private static let allSpaceSets: Int32 = 7

    private let mainConnectionID: MainConnectionIDFn?
    private let spaceCreate: SpaceCreateFn?
    private let spaceSetAbsoluteLevel: SpaceSetAbsoluteLevelFn?
    private let showSpaces: ShowSpacesFn?
    private let spaceAddWindows: SpaceAddWindowsFn?

    private let logger = Logger.crema("LockScreen")

    /// Created once and reused. Making one space per window would leave a
    /// WindowServer space behind on every panel rebuild, and there is no
    /// published call to destroy one.
    private var space: Int32?
    private var connection: Int32?
    /// Set once if the absolute level is ever refused, so the created-then-
    /// abandoned space happens at most one time (see `raisedSpace`).
    private var levelRefused = false

    init(resolver: SymbolResolver = SkyLightSpaceBridge.defaultResolver) {
        mainConnectionID = resolver("SLSMainConnectionID").map { unsafeBitCast($0, to: MainConnectionIDFn.self) }
        spaceCreate = resolver("SLSSpaceCreate").map { unsafeBitCast($0, to: SpaceCreateFn.self) }
        spaceSetAbsoluteLevel = resolver("SLSSpaceSetAbsoluteLevel")
            .map { unsafeBitCast($0, to: SpaceSetAbsoluteLevelFn.self) }
        showSpaces = resolver("SLSShowSpaces").map { unsafeBitCast($0, to: ShowSpacesFn.self) }
        spaceAddWindows = resolver("SLSSpaceAddWindowsAndRemoveFromSpaces")
            .map { unsafeBitCast($0, to: SpaceAddWindowsFn.self) }
    }

    static let defaultResolver: SymbolResolver = { name in
        guard let handle = dlopen(frameworkPath, RTLD_NOW) else { return nil }
        return dlsym(handle, name)
    }

    /// Every one of the five, or none: a partial resolve is a macOS that renamed
    /// something, and half of this sequence puts a window in a space nobody ever
    /// raised — visible on the desktop and nowhere else, which is worse than
    /// absent because it looks like it worked.
    var isAvailable: Bool {
        mainConnectionID != nil && spaceCreate != nil && spaceSetAbsoluteLevel != nil
            && showSpaces != nil && spaceAddWindows != nil
    }

    func adopt(_ window: NSWindow) {
        guard let spaceAddWindows, let raised = raisedSpace() else { return }
        guard let connection else { return }
        let error = spaceAddWindows(
            connection, raised, [window.windowNumber] as CFArray, Self.allSpaceSets
        )
        if error != 0 {
            logger.error("SkyLight refused the window (\(error)); the lock surface will not appear")
        }
    }

    /// Lazily, because a user who never enables the feature should never make a
    /// space — and because the space has to outlive any one window.
    private func raisedSpace() -> Int32? {
        if let space { return space }
        // A refusal is latched, and that is what bounds the damage. The level
        // failing is a property of this macOS, not a transient, so retrying can
        // only fail again — and each retry calls `spaceCreate` first, which
        // SUCCEEDS. Unlatched, every lock cycle (and every WindowServer edge
        // behind it) would leave one more space nobody can reach. One leak on a
        // machine where the feature is off anyway is the price; a growing count
        // is not. Reopening gate: if a sixth symbol is ever resolved to destroy
        // a space, this can retry instead of latch.
        guard !levelRefused else { return nil }
        guard let mainConnectionID, let spaceCreate, let spaceSetAbsoluteLevel, let showSpaces else {
            return nil
        }
        let cid = mainConnectionID()
        let created = spaceCreate(cid, 1, 0)
        // A level that did not take is the whole failure: the space exists, the
        // window goes into it, and it sits at absolute 0 behind the shield —
        // pixels nobody will ever see. Refuse the space rather than hand back
        // one that silently does nothing.
        let levelError = spaceSetAbsoluteLevel(cid, created, Self.aboveScreenLock)
        guard levelError == 0 else {
            levelRefused = true
            logger.error("SkyLight refused the space level (\(levelError)); the lock surface is off")
            return nil
        }
        _ = showSpaces(cid, [created] as CFArray)
        connection = cid
        space = created
        logger.notice("raised space \(created) created at absolute level \(Self.aboveScreenLock)")
        return created
    }
}
