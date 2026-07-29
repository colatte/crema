import Foundation
import Testing
@testable import Crema

/// Slider-driven brightness writes must close their own HUD loop. Volume echoes
/// its programmatic writes through Core Audio, so its indicator follows and the
/// revert timer refreshes for free; the brightness sources emit only through a
/// key-gated poll, so a drag with no key would leave the indicator stuck and let
/// the HUD tuck mid-drag. The fix: on a successful brightness write the
/// Coordinator fires `onBrightnessApplied`, which AppCore wires to poke the
/// matching sampler (re-read + emit). These tests pin that at the Coordinator
/// level with the hook wired to echo the applied value, mirroring the real sampler.
@MainActor
struct CoordinatorBrightnessLoopTests {

    /// Captures the kinds the Coordinator reports as applied.
    private final class AppliedKindRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [SystemHUD.Kind] = []
        var kinds: [SystemHUD.Kind] { lock.withLock { stored } }
        func record(_ kind: SystemHUD.Kind) { lock.withLock { stored.append(kind) } }
    }

    /// Wires the hook to echo the just-written value back into the HUD stream,
    /// exactly as the real samplers do (re-read the applied value and emit it).
    private func wireEcho(_ h: CoordinatorHarness) {
        h.coordinator.onBrightnessApplied = { applied in
            switch applied.kind {
            case .screenBrightness:
                if case let .setBrightness(value, display) = h.screen.commands.last {
                    h.hudSource.emit(SystemHUD(kind: .screenBrightness, value: value, display: display))
                }
            case .keyboardBrightness:
                if case let .setBrightness(value) = h.keyboard.commands.last {
                    h.hudSource.emit(SystemHUD(kind: .keyboardBrightness, value: value))
                }
            case .volume:
                break
            }
        }
    }

    @Test func screenBrightnessSliderReportsTheAppliedKind() async {
        let h = CoordinatorHarness()
        let recorder = AppliedKindRecorder()
        h.coordinator.onBrightnessApplied = { recorder.record($0.kind) }
        h.hudSource.emit(SystemHUD(kind: .screenBrightness, value: 0.5))
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.8)

        #expect(await eventually { recorder.kinds == [.screenBrightness] })
    }

    @Test func keyboardBrightnessSliderReportsTheAppliedKind() async {
        let h = CoordinatorHarness()
        let recorder = AppliedKindRecorder()
        h.coordinator.onBrightnessApplied = { recorder.record($0.kind) }
        h.hudSource.emit(SystemHUD(kind: .keyboardBrightness, value: 0.5))
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.1)

        #expect(await eventually { recorder.kinds == [.keyboardBrightness] })
    }

    @Test func volumeSliderNeverReportsAnAppliedBrightness() async {
        // Parity guard: volume echoes itself through Core Audio, so the volume
        // path must not poke a sampler — it stays exactly as it was.
        let h = CoordinatorHarness()
        let recorder = AppliedKindRecorder()
        h.coordinator.onBrightnessApplied = { recorder.record($0.kind) }
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.5)) })

        h.coordinator.hudSliderChanged(to: 0.7)

        #expect(await eventually { h.volume.commands == [.setVolume(0.7, display: nil)] })
        await settle()
        #expect(recorder.kinds.isEmpty)
    }

    @Test func draggingScreenBrightnessUpdatesTheIndicatorValue() async {
        let h = CoordinatorHarness()
        wireEcho(h)
        h.hudSource.emit(SystemHUD(kind: .screenBrightness, value: 0.5))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .screenBrightness, value: 0.5)) })

        h.coordinator.hudSliderChanged(to: 0.8)

        // The echo carries the applied value back into state — the indicator the
        // views read now shows 0.8 instead of snapping back to 0.5.
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .screenBrightness, value: 0.8)) })
    }

    @Test func draggingKeyboardBrightnessUpdatesTheIndicatorValue() async {
        let h = CoordinatorHarness()
        wireEcho(h)
        h.hudSource.emit(SystemHUD(kind: .keyboardBrightness, value: 0.5))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .keyboardBrightness, value: 0.5)) })

        h.coordinator.hudSliderChanged(to: 0.2)

        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .keyboardBrightness, value: 0.2)) })
    }

    @Test func draggingBrightnessRefreshesTheRevertTimer() async {
        let h = CoordinatorHarness()
        wireEcho(h)
        h.hudSource.emit(SystemHUD(kind: .screenBrightness, value: 0.5))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .screenBrightness, value: 0.5)) })
        await h.clock.waitForSleep()   // the first revert timer is parked

        h.coordinator.hudSliderChanged(to: 0.8)

        // The echoed event restarts the revert timer (old sleep cancelled, fresh
        // one parked) and keeps the HUD up at the new value — a drag holds the
        // HUD alive, like the native HUD on repeated keys, instead of tucking.
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .screenBrightness, value: 0.8)) })
        #expect(await eventually { h.clock.cancelledCount == 1 })
    }
}
