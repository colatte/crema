// What does Core Audio say about the device the sound is going to?
//
// The volume HUD names the output device's kind from the transport type and the
// selected output data source, and from the name on a Bluetooth transport only
// (Crema/Sources/Volume/OutputRouteClassifier.swift). The model UID is not used,
// because its format on Bluetooth is unmeasured, and neither is the output
// streams' terminal type, because it does not speak the header's vocabulary
// (below). This prints all of them, for every device with an output stream, so
// the values can be harvested per device.
//
// The control is the full listing: every output device is read the same way,
// so an absent data source on one device is a property it lacks, not a read
// that fails for everybody (a built-in speaker reports 'ispk' through the same
// code path). "absent" means AudioObjectHasProperty said no; "error N" means the
// property exists and the read failed.
// Measured with this probe 2026-10-15, macOS 27.0.1, MacBook Pro (Apple
// Silicon, Mac16,8), built-in speakers as the only output device: name
// "Alto-falantes (MacBook Pro)", transport 'bltn', data source 'ispk', model UID
// "Speaker", manufacturer "Apple Inc.", device UID "BuiltInSpeakerDevice", and
// terminal type 0x301 — the USB Audio Class "Speaker" code, not the header's
// kAudioStreamTerminalTypeSpeaker 'spkr'. Invalidated by a terminal type that
// reads as one of the header's four-character codes.
//
// Read-only: it never sets a property, the default device or the volume.
//
// Run:  swift scripts/probes/output-device-route.swift

import CoreAudio
import Foundation

func fourCC(_ value: UInt32) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
    guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return "0x" + String(value, radix: 16) }
    return "'" + String(decoding: bytes, as: UTF8.self) + "'"
}

func address(_ selector: AudioObjectPropertySelector,
             _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func readUInt32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> String {
    var addr = address(selector, scope)
    guard AudioObjectHasProperty(object, &addr) else { return "absent" }
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value)
    return status == noErr ? fourCC(value) : "error \(status)"
}

func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
    var addr = address(selector)
    guard AudioObjectHasProperty(object, &addr) else { return "absent" }
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value)
    guard status == noErr, let value else { return "error \(status)" }
    return "\"" + (value.takeRetainedValue() as String) + "\""
}

func readIDs(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
             _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
    var addr = address(selector, scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

let system = AudioObjectID(kAudioObjectSystemObject)
var defaultAddress = address(kAudioHardwarePropertyDefaultOutputDevice)
var defaultDevice = AudioObjectID(kAudioObjectUnknown)
var defaultSize = UInt32(MemoryLayout<AudioObjectID>.size)
_ = AudioObjectGetPropertyData(system, &defaultAddress, 0, nil, &defaultSize, &defaultDevice)

let outputDevices = readIDs(system, kAudioHardwarePropertyDevices).filter {
    !readIDs($0, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput).isEmpty
}

if outputDevices.isEmpty { print("No device with an output stream — Core Audio listing failed.") }

for device in outputDevices {
    let streams = readIDs(device, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
    let terminals = streams.map { readUInt32($0, kAudioStreamPropertyTerminalType) }
    print(device == defaultDevice ? "device \(device) (DEFAULT OUTPUT)" : "device \(device)")
    print("  name          \(readString(device, kAudioObjectPropertyName))")
    print("  transport     \(readUInt32(device, kAudioDevicePropertyTransportType))")
    print("  data source   \(readUInt32(device, kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput))")
    print("  terminal      \(terminals.joined(separator: ", "))")
    print("  model UID     \(readString(device, kAudioDevicePropertyModelUID))")
    print("  manufacturer  \(readString(device, kAudioObjectPropertyManufacturer))")
    print("  device UID    \(readString(device, kAudioDevicePropertyDeviceUID))")
}
