import AppKit
import Observation
import os

/// Whether the lock surface should be on screen at this moment.
///
/// Pure and separate from the presenter because it is the whole policy, and
/// because the presenter's other half is AppKit — a test can own this and never
/// has to own a window.
enum LockWidgetPresence {
    /// Three conditions, and each rules out a different way of getting it wrong.
    ///
    /// - `enabled`: the feature is opt-in and born off. Nothing here may put a
    ///   window over a lock screen the user never asked us to draw on.
    /// - `locked`: the raw lock bit, never `!isSuppressionSafe`. Off-console
    ///   means someone else is using the Mac, and their lock screen is not the
    ///   place for this user's listening.
    /// - `spaceAvailable`: without the raised space the window renders at the
    ///   default level, behind the shield — invisible while locked and, worse,
    ///   sitting on the desktop when unlocked.
    static func shouldPresent(enabled: Bool, locked: Bool, spaceAvailable: Bool) -> Bool {
        enabled && locked && spaceAvailable
    }
}

/// Owns the lock surface's whole lifetime: builds the window when the screen
/// locks, tears it down when it unlocks, and re-asserts its space on every edge
/// that can have reconfigured the WindowServer underneath it.
///
/// It is a parallel owner rather than a branch of `WindowManager`, and that is
/// the point. The manager keys one panel per display and reconciles them against
/// a screen roster; this is one window on the main screen whose existence is
/// governed by a lock bit. Folding it in would mean an eighth parameter on a
/// protocol with four implementers and a lock dimension inside `PresentationState`
/// — machinery for a distinction neither type has today.
///
/// It also does not touch `coordinator.onPresentationChange`: that is a single
/// closure slot already claimed by `WindowManager.start()`, and a second claim
/// would silently unhook the frame pass.
///
/// Not `@Observable`, deliberately: nothing reads state OFF this type. It pushes
/// — into the window it owns and into the resolver it holds, both of which are
/// observable in their own right. Marking it would advertise a subscription no
/// view takes and invite the next reader to add one.
@MainActor
final class LockScreenPresenter {
    private let coordinator: Coordinator
    private let lock: LockScreenMirror
    private let space: any RaisedSpace
    private let lowPower: LowPowerModeMirror
    private let artwork: LockArtworkResolver
    private let makePanel: @MainActor (NSScreen, Coordinator, any RaisedSpace, LowPowerModeMirror, LockArtworkResolver) -> LockScreenPanel?
    private let logger = Logger.crema("LockScreen")

    private var panel: LockScreenPanel?
    private var observation: NSObjectProtocol?
    private var workspaceObservations: [NSObjectProtocol] = []

    /// Written only by `setEnabled`, which is the Settings path. No failure here
    /// ever writes it back — the preference is the user's intent and only the
    /// user changes it (docs/DECISIONS.md: pref-sacred).
    private var enabled: Bool

    init(
        coordinator: Coordinator,
        lock: LockScreenMirror,
        space: any RaisedSpace,
        lowPower: LowPowerModeMirror,
        artwork: LockArtworkResolver,
        enabled: Bool,
        makePanel: @escaping @MainActor (
            NSScreen, Coordinator, any RaisedSpace, LowPowerModeMirror, LockArtworkResolver
        ) -> LockScreenPanel? = {
            LockScreenPanel(screen: $0, coordinator: $1, space: $2, lowPower: $3, artwork: $4)
        }
    ) {
        self.coordinator = coordinator
        self.lock = lock
        self.space = space
        self.lowPower = lowPower
        self.artwork = artwork
        self.enabled = enabled
        self.makePanel = makePanel
    }

    /// Starts observing the lock mirror and the WindowServer edges.
    ///
    /// Observation rather than a stream: `LockScreenMirror` is `@Observable` and
    /// `withObservationTracking` re-arms itself per change, which is the shape
    /// that lets a second reader exist at all here — the source's `updates` is a
    /// single-consumer stream the suppression controller already owns.
    func start() {
        observeLock()
        installEdgeObservers()
        reconcile()
    }

    /// Asked by Settings so the row can say "not on this macOS" instead of
    /// offering a switch that does nothing. Exposed here rather than by holding
    /// the border in the composition root: AppCore never calls SkyLight, and a
    /// system border it stores but does not use is one more thing to keep true.
    var spaceIsAvailable: Bool { space.isAvailable }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        reconcile()
    }

    /// The cover lookup's own switch, forwarded rather than reached around.
    ///
    /// The resolver belongs to this surface's lifetime — it exists to decide what
    /// one window draws — so the composition root holds no second handle to it.
    /// The live window keeps working: the resolver is `@Observable` and the view
    /// already reads it, so flipping this repaints without rebuilding anything.
    func setArtworkLookupEnabled(_ on: Bool) {
        artwork.setEnabled(on)
    }

    /// The read half of the pair above. It exists because the two opt-in
    /// preferences this surface carries are both plain `Bool`s seeded in the same
    /// call, and swapping them compiles: without a way to ask, the crossing is
    /// invisible until someone reports a network request they never enabled.
    var artworkLookupIsEnabled: Bool { artwork.isEnabled }

    // MARK: - The decision

    private func reconcile() {
        let wanted = LockWidgetPresence.shouldPresent(
            enabled: enabled,
            locked: lock.isLocked,
            spaceAvailable: space.isAvailable
        )
        switch (wanted, panel) {
        case (true, nil):
            guard let screen = NSScreen.main else {
                logger.notice("no main screen to draw the lock surface on")
                return
            }
            panel = makePanel(screen, coordinator, space, lowPower, artwork)
            if panel == nil {
                logger.notice("the raised space refused the surface; the lock widget stays off")
            }
        case (false, .some(let live)):
            live.close()
            panel = nil
        default:
            break
        }
    }

    // MARK: - Inputs

    private func observeLock() {
        withObservationTracking {
            _ = lock.isLocked
        } onChange: { [weak self] in
            // onChange fires BEFORE the value is written, so the read has to
            // happen on the next turn or `reconcile` sees the old bit.
            Task { @MainActor [weak self] in
                self?.observeLock()
                self?.reconcile()
            }
        }
    }

    /// The same four edges the media-key tap reinstalls on, for the same reason:
    /// whether a raised space survived a display sleep is state living in the
    /// WindowServer, and this process cannot audit it (docs/DECISIONS.md:
    /// preventive-reinstall, J7-estado-do-outro-lado). Re-adopting is idempotent
    /// and convergent, so acting unconditionally costs one cheap call and a local
    /// health read would cost a surface that silently stopped appearing.
    private func installEdgeObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification,
        ] {
            workspaceObservations.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.panel?.reassertSpace() }
                }
            )
        }
        observation = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleScreenChange() }
        }
    }

    /// A topology change can move or resize the main screen under a window that
    /// was sized to the old one, so the frame is re-applied before the space is
    /// re-asserted — a correctly-spaced window at the wrong size is still wrong.
    private func handleScreenChange() {
        guard let panel, let screen = NSScreen.main else { return }
        panel.setFrame(screen.frame)
    }

    deinit {
        // nonisolated deinit: the observer arrays are only mutated during
        // `installEdgeObservers` and read here, after every other access has
        // ended — the same lifecycle bracket the lock source documents.
        MainActor.assumeIsolated {
            for observer in workspaceObservations {
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
            }
            if let observation { NotificationCenter.default.removeObserver(observation) }
            panel?.close()
        }
    }
}
