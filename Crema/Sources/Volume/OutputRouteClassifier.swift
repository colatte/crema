import Foundation

/// Pure translation of the default output device's raw Core Audio readings into
/// the domain's `AudioOutputRoute`. No Core Audio here: the readings arrive as
/// the four-character codes the headers define, so every row is testable.
///
/// The name decides only on a Bluetooth transport. A device name is localized
/// and the user can rename it ("AirPods Pro de Victor"), so it never classifies
/// the built-in device, whose data source answers instead. The product glyphs
/// may only refer to the product they draw (CoreGlyphs'
/// `symbol_restrictions.strings`), so a Bluetooth name that matches no model
/// falls back to plain headphones (docs/DECISIONS.md:
/// the-output-glyph-names-only-what-it-knows).
enum OutputRouteClassifier {
    // Transport types, `kAudioDevicePropertyTransportType` values
    // (CoreAudio, AudioHardwareBase.h).
    static let transportBuiltIn = fourCC("bltn")
    static let transportBluetooth = fourCC("blue")
    static let transportBluetoothLE = fourCC("blea")
    static let transportHDMI = fourCC("hdmi")
    static let transportDisplayPort = fourCC("dprt")
    static let transportAirPlay = fourCC("airp")

    // Output data sources, `kAudioDevicePropertyDataSource` item IDs on the
    // built-in device (IOKit, IOAudioTypes.h: kIOAudioOutputPortSubType*).
    static let dataSourceInternalSpeaker = fourCC("ispk")
    static let dataSourceHeadphones = fourCC("hdpn")

    /// Most specific first: "AirPods Max" and "AirPods Pro" both contain
    /// "AirPods", so the bare model is asked last.
    private static let airPodsModels: [(token: String, route: AudioOutputRoute)] = [
        ("AirPods Max", .airPodsMax),
        ("AirPods Pro", .airPodsPro),
        ("AirPods", .airPods),
    ]

    /// Beats' headphone mark may only refer to Beats headphones (CoreGlyphs'
    /// `symbol_restrictions.strings`), and the brand's earbuds and speakers carry
    /// marks of their own. Its headphone lines are Solo and Studio; Studio Buds
    /// are earbuds, so "Buds" rules a name out.
    private static let beatsHeadphoneLines = ["Beats Solo", "Beats Studio"]

    /// `dataSource` is nil when the device has no data-source control; `name` is
    /// nil when it could not be read.
    static func route(transport: UInt32, dataSource: UInt32?, name: String?) -> AudioOutputRoute {
        switch transport {
        case transportBuiltIn:
            builtInRoute(dataSource: dataSource)
        case transportBluetooth, transportBluetoothLE:
            bluetoothRoute(name: name)
        case transportAirPlay:
            .airPlay
        case transportHDMI, transportDisplayPort:
            .display
        default:
            // USB carries headsets, DACs, interfaces and a display's speakers
            // alike, and an aggregate's main sub-device is its clock, not where
            // the sound goes (AudioHardware.h,
            // kAudioAggregateDevicePropertyMainSubDevice: "the AudioDevice that is
            // currently serving as the time base"): neither names a kind.
            .unknown
        }
    }

    /// The headphone jack is the one built-in selection drawn apart. A built-in
    /// device with no data-source control counts as the speakers, and any other
    /// selection (line out, digital out) as unknown; both keep the speaker glyph.
    private static func builtInRoute(dataSource: UInt32?) -> AudioOutputRoute {
        switch dataSource {
        case nil, dataSourceInternalSpeaker: .builtInSpeakers
        case dataSourceHeadphones: .wiredHeadphones
        default: .unknown
        }
    }

    private static func bluetoothRoute(name: String?) -> AudioOutputRoute {
        guard let name else { return .bluetoothHeadphones }
        func names(_ token: String) -> Bool { name.range(of: token, options: .caseInsensitive) != nil }
        if let model = airPodsModels.first(where: { names($0.token) }) { return model.route }
        if beatsHeadphoneLines.contains(where: names), !names("Buds") { return .beats }
        return .bluetoothHeadphones
    }

    /// The big-endian packing Core Audio's four-character constants use.
    private static func fourCC(_ code: StaticString) -> UInt32 {
        code.withUTF8Buffer { bytes in
            bytes.reduce(0) { ($0 << 8) | UInt32($1) }
        }
    }
}
