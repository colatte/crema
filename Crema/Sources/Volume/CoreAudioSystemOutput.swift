import AudioToolbox
import CoreAudio

/// Thin Core Audio plumbing shared by the volume source and controller: reads,
/// writes and property addresses for the system's default output device.
/// Nothing above this layer sees a Core Audio type (the border rule).
/// (AudioToolbox is imported only for the 'vmvc' virtual-main-volume selector,
/// which lives in AudioToolbox and always has — Audio Hardware Services is an
/// AudioToolbox API, never a CoreAudio one, so this import is where the
/// selector comes from rather than a workaround for something CoreAudio
/// dropped; the calls themselves are all plain AudioObject* APIs.)
enum CoreAudioSystemOutput {
    enum Failure: Error {
        case notSettable
        case status(OSStatus)
    }

    // MARK: - Property addresses

    static var defaultOutputDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// The selected output data source: on a built-in device, speakers or the
    /// headphone jack (AudioHardware.h, kAudioDevicePropertyDataSource).
    static var dataSourceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var transportTypeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var nameAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    // MARK: - Reads

    static func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = defaultOutputDeviceAddress
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else { return nil }
        return deviceID
    }

    static func supportsVolume(_ device: AudioDeviceID) -> Bool {
        var address = volumeAddress
        return AudioObjectHasProperty(device, &address)
    }

    static func supportsMute(_ device: AudioDeviceID) -> Bool {
        var address = muteAddress
        return AudioObjectHasProperty(device, &address)
    }

    static func readVolume(_ device: AudioDeviceID) -> Float? {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = volumeAddress
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func readMute(_ device: AudioDeviceID) -> Bool? {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    static func supportsDataSource(_ device: AudioDeviceID) -> Bool {
        var address = dataSourceAddress
        return AudioObjectHasProperty(device, &address)
    }

    /// The device's kind, translated here so no reading leaves this layer. An
    /// unreadable transport reads as Core Audio's own "unknown" (0).
    static func readRoute(_ device: AudioDeviceID) -> AudioOutputRoute {
        var transportAddress = transportTypeAddress
        var dataSourceAddress = dataSourceAddress
        let transport = readUInt32(device, &transportAddress) ?? kAudioDeviceTransportTypeUnknown
        let dataSource = supportsDataSource(device) ? readUInt32(device, &dataSourceAddress) : nil
        return OutputRouteClassifier.route(transport: transport, dataSource: dataSource, name: readName(device))
    }

    private static func readUInt32(_ device: AudioDeviceID, _ address: inout AudioObjectPropertyAddress) -> UInt32? {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    /// kAudioObjectPropertyName hands back a CFString the caller releases
    /// (AudioHardwareBase.h), hence the retained take.
    private static func readName(_ device: AudioDeviceID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = nameAddress
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
              let name else { return nil }
        return name.takeRetainedValue() as String
    }

    // MARK: - Writes

    static func writeVolume(_ value: Float, to device: AudioDeviceID) throws {
        var address = volumeAddress
        try ensureSettable(device, &address)
        var value = value
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value
        )
        guard status == noErr else { throw Failure.status(status) }
    }

    static func writeMute(_ muted: Bool, to device: AudioDeviceID) throws {
        var address = muteAddress
        try ensureSettable(device, &address)
        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
        )
        guard status == noErr else { throw Failure.status(status) }
    }

    private static func ensureSettable(
        _ device: AudioDeviceID,
        _ address: inout AudioObjectPropertyAddress
    ) throws {
        var settable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(device, &address, &settable)
        guard status == noErr else { throw Failure.status(status) }
        guard settable.boolValue else { throw Failure.notSettable }
    }
}
