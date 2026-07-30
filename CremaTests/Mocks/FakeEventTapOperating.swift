import AppKit
import CoreGraphics
import Foundation
@testable import Crema

/// Test fake for the CGEventTap border: records install/uninstall and lets a
/// test flip either the enabled flag (system disable) or the port's validity
/// (system invalidate) behind the source's back — the two distinct failure
/// modes the health-check must tell apart. It also CAPTURES the C callback and
/// userInfo of every install, so a test can fire a synthetic media-key event
/// through the real source's callback — including at an OLD install, modeling
/// an event delivered to a stale port during an uninstall→install swap.
/// Lock-protected — the source's poll task and the test thread both touch it.
final class FakeEventTapOperating: EventTapOperating, @unchecked Sendable {
    /// The opaque token the source stores; identity distinguishes reinstalls.
    final class Token {}

    /// One captured install: the token plus the callback/userInfo pair, kept
    /// even after the port is uninstalled — that persistence is the whole
    /// point of the old-port delivery probe.
    private struct Install {
        let token: Token
        let callback: CGEventTapCallBack
        let userInfo: UnsafeMutableRawPointer
    }

    private let lock = NSLock()
    private var _installs: [Install] = []
    private var _token: Token?
    private var _enabled = false
    /// A freshly installed port is valid; an invalidated one is dead until the
    /// health-check reinstalls (unlike disable, no re-enable recovers it).
    private var _valid = false
    private var _setEnabledCalls: [Bool] = []
    private var _operations: [String] = []
    private var _offMainMutations: [String] = []

    /// How many times a tap was installed (a revive must not increment this —
    /// re-enabling keeps the same port and its consumer wiring; a reinstall
    /// after an invalidation does increment). The index of the current install
    /// is installCount − 1; a prior index targets an already-uninstalled port.
    var installCount: Int { lock.withLock { _installs.count } }
    /// Whether the currently installed tap is enabled.
    var isCurrentlyEnabled: Bool { lock.withLock { _enabled } }
    /// Whether a tap is installed at all.
    var isInstalled: Bool { lock.withLock { _token != nil } }
    /// The current opaque token, for asserting a reinstall minted a fresh one.
    var currentToken: Token? { lock.withLock { _token } }
    /// Every `setEnabled` argument in order (install's implicit enable excluded).
    var setEnabledCalls: [Bool] { lock.withLock { _setEnabledCalls } }
    /// The `userInfo` pointer of every install, in order. It is
    /// `Unmanaged.passUnretained(source)`, so identical pointers across a
    /// reinstall prove the fresh port routes back to the same source — and thus
    /// the same, unchanged `consumer`, which the callback reads dynamically.
    /// This is the by-construction pin that a reinstall never drops suppression.
    var installedUserInfos: [UnsafeMutableRawPointer] { lock.withLock { _installs.map(\.userInfo) } }
    /// Every install/uninstall in call order — pins a forced reinstall as a
    /// paired uninstall→install (old port torn down first, no orphan) rather
    /// than a bare re-create over a still-live port.
    var operations: [String] { lock.withLock { _operations } }
    /// Every port reconfiguration that ran OFF the main thread. The live border puts
    /// the run-loop source on the MAIN run loop, which is also the thread the
    /// callback is delivered on, so a mutation from anywhere else can land between a
    /// delivered event and the callback handling it — and contends the source's lock
    /// with that callback across a WindowServer round-trip. Empty is the invariant
    /// (docs/DECISIONS.md: tap-mutation-on-its-own-thread). Read it only in tests
    /// that drive the POLL: the synchronous seams (setConsumer, reinstallTap) are
    /// main-thread by their callers' isolation in production, and tests call them
    /// straight off-actor.
    var offMainMutations: [String] { lock.withLock { _offMainMutations } }

    /// Called BEFORE taking the lock — NSLock is not recursive and every mutating
    /// operation below already holds it.
    private func noteMutationThread(_ operation: String) {
        guard !Thread.isMainThread else { return }
        lock.withLock { _offMainMutations.append(operation) }
    }

    /// Simulate the system disabling the tap without delivering a callback. The
    /// port stays valid, so the health-check revives it in place.
    func simulateSystemDisable() {
        lock.withLock { _enabled = false }
    }

    /// Simulate the system invalidating the mach port outright — dead
    /// permanently, no re-enable recovers it. The source's state still says
    /// "installed" until the health-check notices and reinstalls from scratch.
    func simulateSystemInvalidate() {
        lock.withLock { _valid = false }
    }

    func install(
        mask: CGEventMask,
        callback: @escaping CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer
    ) -> AnyObject? {
        noteMutationThread("install")
        return lock.withLock {
            let token = Token()
            _installs.append(Install(token: token, callback: callback, userInfo: userInfo))
            _token = token
            _enabled = true
            _valid = true
            _operations.append("install")
            return token
        }
    }

    func isEnabled(_ token: AnyObject) -> Bool {
        lock.withLock { (token as AnyObject) === _token && _enabled }
    }

    func isValid(_ token: AnyObject) -> Bool {
        lock.withLock { (token as AnyObject) === _token && _valid }
    }

    func setEnabled(_ token: AnyObject, _ enabled: Bool) {
        noteMutationThread("setEnabled")
        lock.withLock {
            _setEnabledCalls.append(enabled)
            if (token as AnyObject) === _token { _enabled = enabled }
        }
    }

    func uninstall(_ token: AnyObject) {
        noteMutationThread("uninstall")
        lock.withLock {
            _operations.append("uninstall")
            if (token as AnyObject) === _token {
                _token = nil
                _enabled = false
                _valid = false
            }
        }
    }

    // MARK: - Synthetic delivery through the captured callback

    /// Fire a synthetic media-key event through a captured install's callback.
    /// `index` nil = the current (last) install. Returns whether the callback
    /// swallowed it (true) or passed it through (false); nil if no such install.
    /// The install is looked up regardless of whether the port was later
    /// uninstalled — that is the whole point of the old-port delivery probe: the
    /// captured callback routes through the same source pointer either way.
    func deliver(data1: Int, index: Int? = nil) -> Bool? {
        let install: Install? = lock.withLock {
            guard !_installs.isEmpty else { return nil }
            let i = index ?? (_installs.count - 1)
            return _installs.indices.contains(i) ? _installs[i] : nil
        }
        guard let install, let event = Self.makeSystemDefinedEvent(data1: data1) else { return nil }
        // The proxy is never dereferenced by the callback (it reads userInfo); a
        // bogus non-null pointer is fine, and bitPattern: 0x1 is never nil.
        guard let proxy = OpaquePointer(bitPattern: 0x1) else { return nil }
        let result = install.callback(proxy, event.type, event, install.userInfo)
        return result == nil   // nil ⇒ swallowed
    }

    /// An NX_SYSDEFINED aux-control CGEvent (subtype 8) built via NSEvent — the
    /// only reliable way to synthesize one; its .type carries rawValue 14, which
    /// the callback reads directly (CGEventType has no named case for 14).
    static func makeSystemDefinedEvent(data1: Int) -> CGEvent? {
        NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: MediaKeyTranslation.auxiliaryControlSubtype,
            data1: data1,
            data2: -1
        )?.cgEvent
    }
}
