/// Bridges the media-key tap to the brightness sources: a brightness key
/// samples the matching source, which both marks the change as key-originated
/// (both brightness sources show the HUD only for key changes, not the ambient
/// sensor) and surfaces it with no poll latency when the value is already
/// applied; otherwise the source's armed poll a beat later surfaces it.
///
/// Volume is deliberately not routed here — Core Audio is event-driven, so the
/// volume source already emits the instant the key lands; poking it would just
/// double-fire. Without Accessibility the tap stays silent, so no sample ever
/// marks a change as key-originated and the brightness HUDs simply never
/// surface (the key-origin gate keeps them quiet — deliberately, or the
/// ambient-light sensor would flash a HUD). Volume still flows; the router's
/// absence degrades brightness to silence, not to latency.
///
/// @unchecked because `task` is mutable without a lock: the invariant making it
/// safe is that start() is called only from the MainActor (AppCore owns the
/// router and drives it from the main thread). Calling it off-main requires
/// adding a lock.
///
/// One-shot, and there is no `stop()` — there was one, referenced by neither the
/// app nor the suite, and it could not have been honoured: the tap's `updates` is
/// built once at init and finishes only with the source, so a cancelled iteration
/// is not resubscribable. Whoever called it would get brightness keys that stop
/// reaching the HUD for the rest of the process, with no error anywhere. The
/// router lives for the process, the same conclusion the Coordinator's start()
/// records for its own consumption tasks
/// (docs/DECISIONS.md: teardown-seam-that-cannot-be-honoured).
final class MediaKeyHUDRouter: @unchecked Sendable {
    private let mediaKeys: any MediaKeySource
    private let screenBrightness: any ManuallySampledSource
    private let keyboardBrightness: any ManuallySampledSource
    private var task: Task<Void, Never>?

    init(
        mediaKeys: any MediaKeySource,
        screenBrightness: any ManuallySampledSource,
        keyboardBrightness: any ManuallySampledSource
    ) {
        self.mediaKeys = mediaKeys
        self.screenBrightness = screenBrightness
        self.keyboardBrightness = keyboardBrightness
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self, mediaKeys] in
            for await key in mediaKeys.updates {
                self?.route(key)
            }
        }
    }

    private func route(_ key: MediaKey) {
        switch key {
        case .screenBrightnessUp, .screenBrightnessDown:
            screenBrightness.sample()
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            keyboardBrightness.sample()
        case .volumeUp, .volumeDown, .mute:
            break
        }
    }
}
