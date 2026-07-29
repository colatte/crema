import CoreAudio
import Foundation
import os

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
    private let logger = Logger.crema("Volume")
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
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, queue, defaultBlock
        )
        // A failed registration is silent deafness: reads/writes keep working
        // while the HUD never updates — the status line is the only trace.
        if status != noErr {
            logger.error(
                "default-output listener registration failed (OSStatus \(status, privacy: .public)) — device switches will not re-arm observation"
            )
        }

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
    /// Runs on `queue`, never on the caller's thread. The caller is the
    /// suppressor's post-apply hook on the MainActor, and these three round trips
    /// are the same blocking Core Audio IPC the suppressor deadline-races for
    /// exactly this reason — doing them inline froze the whole app (HUD, now
    /// playing, menu) on a coreaudiod stall, on the HEALTHY path, once per volume
    /// key, and froze it precisely while the key had been swallowed. Sharing the
    /// listener queue also orders this against `emitCurrentState`, so a sample and
    /// a property callback can no longer interleave their reads.
    func sample() {
        queue.async { [weak self] in self?.sampleOnQueue() }
    }

    private func sampleOnQueue() {
        guard let device = CoreAudioSystemOutput.defaultOutputDeviceID() else { return }
        // A failed volume read stays silent rather than publish a fabricated
        // 0% (the OSD channel treats the same nil as a real failure); the mute
        // fallback is different — a device without a mute control is absent
        // capability, not a failed read.
        guard let raw = CoreAudioSystemOutput.readVolume(device) else {
            logger.debug("volume read failed on device \(device, privacy: .public) — skipping the boundary refresh")
            return
        }
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
        let volumeStatus = AudioObjectAddPropertyListenerBlock(device, &volume, queue, block)
        let muteStatus = AudioObjectAddPropertyListenerBlock(device, &mute, queue, block)
        // Self-heals on the next default-device switch (the system-object
        // listener survives); until then the HUD is deaf, so leave a trace.
        if volumeStatus != noErr || muteStatus != noErr {
            let statuses = "volume \(volumeStatus), mute \(muteStatus)"
            logger.error(
                "listener add on device \(device, privacy: .public) failed (OSStatus \(statuses, privacy: .public)) — HUD deaf until the next device switch"
            )
        }
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

        // Same discipline as sample(): a failed read must not become a HUD
        // asserting 0% — stay silent and leave a trace instead.
        guard let raw = CoreAudioSystemOutput.readVolume(device) else {
            logger.debug("volume read failed on device \(device, privacy: .public) — skipping the emit")
            return
        }
        let muted = CoreAudioSystemOutput.readMute(device) ?? false
        continuation.yield(VolumeConversion.hud(rawVolume: raw, isMuted: muted))
    }
}
