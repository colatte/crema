import CoreAudio
import Foundation

/// Real system-volume source: observes the default output device's volume and
/// mute via Core Audio property listeners and emits domain events. Raw↔domain
/// translation lives in VolumeConversion; when the default output device
/// changes, observation moves to the new device (silently — switching devices
/// must not pop the HUD; the next real change will).
final class CoreAudioVolumeSource: SystemHUDSource, ManuallySampledSource, @unchecked Sendable {
    let updates: AsyncStream<SystemHUD>

    private let continuation: AsyncStream<SystemHUD>.Continuation
    private let queue = DispatchQueue(label: "com.colatte.crema.CoreAudioVolumeSource")
    private let lock = NSLock()
    private var observedDevice: AudioDeviceID?

    // Listener blocks are retained so they can be removed; one block serves
    // both the volume and the mute address on the observed device.
    private var deviceBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceBlock: AudioObjectPropertyListenerBlock?

    init() {
        var continuation: AsyncStream<SystemHUD>.Continuation!
        updates = AsyncStream { continuation = $0 }
        self.continuation = continuation

        let defaultBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.observeCurrentDefaultDevice()
        }
        defaultDeviceBlock = defaultBlock
        var address = CoreAudioSystemOutput.defaultOutputDeviceAddress
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, queue, defaultBlock
        )

        observeCurrentDefaultDevice()
    }

    deinit {
        lock.lock()
        removeDeviceListenersLocked()
        lock.unlock()
        if let block = defaultDeviceBlock {
            var address = CoreAudioSystemOutput.defaultOutputDeviceAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, queue, block
            )
        }
        continuation.finish()
    }

    func isAvailable() async -> Bool {
        guard let device = CoreAudioSystemOutput.defaultOutputDeviceID() else { return false }
        return CoreAudioSystemOutput.supportsVolume(device)
    }

    /// A consumed volume key drove this (the suppressor's post-apply poke). At a
    /// scale boundary the write is a no-op and Core Audio fires no property
    /// change, so re-read and emit here; off the boundary the echo already
    /// covered the change, so `boundaryRefreshHUD` returns nil and we stay quiet
    /// (no double-fire). Never called in observe mode — there the native OSD
    /// covers the boundary and the app owns nothing to feed back.
    func sample() {
        guard let device = CoreAudioSystemOutput.defaultOutputDeviceID() else { return }
        let raw = CoreAudioSystemOutput.readVolume(device) ?? 0
        let muted = CoreAudioSystemOutput.readMute(device) ?? false
        guard let hud = VolumeConversion.boundaryRefreshHUD(rawVolume: raw, isMuted: muted) else { return }
        continuation.yield(hud)
    }

    // MARK: - Observation

    private func observeCurrentDefaultDevice() {
        lock.lock()
        defer { lock.unlock() }

        removeDeviceListenersLocked()

        guard let device = CoreAudioSystemOutput.defaultOutputDeviceID() else {
            observedDevice = nil
            return
        }

        // The block captures its device: a stale notification from the old
        // device can still be queued when the default output switches, and it
        // must not emit (device switches never pop the HUD).
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.emitCurrentState(from: device)
        }
        deviceBlock = block
        var volume = CoreAudioSystemOutput.volumeAddress
        var mute = CoreAudioSystemOutput.muteAddress
        AudioObjectAddPropertyListenerBlock(device, &volume, queue, block)
        AudioObjectAddPropertyListenerBlock(device, &mute, queue, block)
        observedDevice = device
    }

    private func removeDeviceListenersLocked() {
        guard let device = observedDevice, let block = deviceBlock else { return }
        var volume = CoreAudioSystemOutput.volumeAddress
        var mute = CoreAudioSystemOutput.muteAddress
        // The old device may already be gone; removal failures are harmless.
        AudioObjectRemovePropertyListenerBlock(device, &volume, queue, block)
        AudioObjectRemovePropertyListenerBlock(device, &mute, queue, block)
        deviceBlock = nil
        observedDevice = nil
    }

    private func emitCurrentState(from device: AudioDeviceID) {
        lock.lock()
        let isCurrentDevice = observedDevice == device
        lock.unlock()
        guard isCurrentDevice else { return }

        let raw = CoreAudioSystemOutput.readVolume(device) ?? 0
        let muted = CoreAudioSystemOutput.readMute(device) ?? false
        continuation.yield(VolumeConversion.hud(rawVolume: raw, isMuted: muted))
    }
}
