import Testing
@testable import Crema

/// The raw readings → route table, written from the headers' four-character
/// codes rather than from the classifier's own constants, so a mistyped code in
/// production fails here instead of agreeing with itself.
struct OutputRouteClassifierTests {

    /// Packs a four-character code the way Core Audio's constants are packed.
    private func code(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func route(_ transport: String, _ dataSource: String? = nil, name: String? = nil) -> AudioOutputRoute {
        OutputRouteClassifier.route(transport: code(transport), dataSource: dataSource.map(code), name: name)
    }

    @Test func packsCodesTheWayTheHeadersSpellThem() {
        // AudioHardwareBase.h: kAudioDeviceTransportTypeBuiltIn = 'bltn'.
        #expect(code("bltn") == 0x626C_746E)
    }

    // MARK: - Built-in device: the data source decides, never the name

    @Test func builtInSpeakersByDataSource() {
        #expect(route("bltn", "ispk") == .builtInSpeakers)
    }

    @Test func builtInHeadphoneJackByDataSource() {
        #expect(route("bltn", "hdpn") == .wiredHeadphones)
    }

    @Test func builtInWithoutDataSourceIsTheSpeakers() {
        #expect(route("bltn") == .builtInSpeakers)
    }

    @Test func builtInWithAnotherDataSourceIsUnknown() {
        #expect(route("bltn", "line") == .unknown)
        #expect(route("bltn", "spdf") == .unknown)
    }

    @Test func builtInNameNeverClassifies() {
        #expect(route("bltn", "ispk", name: "AirPods Pro") == .builtInSpeakers)
        #expect(route("bltn", "ispk", name: "Headphones") == .builtInSpeakers)
        #expect(route("bltn", "hdpn", name: "Alto-falantes (MacBook Pro)") == .wiredHeadphones)
        #expect(route("bltn", name: "Beats Studio") == .builtInSpeakers)
    }

    // MARK: - Bluetooth: the name, most specific model first

    @Test(arguments: ["blue", "blea"])
    func bluetoothModelsByName(transport: String) {
        #expect(route(transport, name: "AirPods Max") == .airPodsMax)
        #expect(route(transport, name: "AirPods Pro") == .airPodsPro)
        #expect(route(transport, name: "AirPods") == .airPods)
        #expect(route(transport, name: "Beats Studio Pro") == .beats)
        #expect(route(transport, name: "Powerbeats Pro") == .beats)
    }

    @Test(arguments: ["blue", "blea"])
    func bluetoothNamesAreLocalizedAndRenamed(transport: String) {
        #expect(route(transport, name: "AirPods Pro de Victor") == .airPodsPro)
        #expect(route(transport, name: "Victor’s AirPods Max") == .airPodsMax)
        #expect(route(transport, name: "airpods pro") == .airPodsPro)
        #expect(route(transport, name: "AIRPODS") == .airPods)
        #expect(route(transport, name: "AirPods de Victor") == .airPods)
    }

    @Test(arguments: ["blue", "blea"])
    func bluetoothWithoutAModelIsGenericHeadphones(transport: String) {
        #expect(route(transport, name: "WH-1000XM5") == .bluetoothHeadphones)
        #expect(route(transport, name: "") == .bluetoothHeadphones)
        #expect(route(transport, name: nil) == .bluetoothHeadphones)
        #expect(route(transport, "ispk", name: "Speaker") == .bluetoothHeadphones)
    }

    // MARK: - Transports that name the kind on their own

    @Test func airPlayByTransport() {
        #expect(route("airp", name: "Living Room") == .airPlay)
    }

    @Test func displaysByTransport() {
        #expect(route("hdmi", name: "LG TV") == .display)
        #expect(route("dprt", name: "DELL U2723QE") == .display)
    }

    // MARK: - Transports that do not

    @Test func aNonBluetoothDeviceNamedAirPodsStaysGeneric() {
        #expect(route("usb ", name: "AirPods") == .unknown)
        #expect(route("virt", name: "AirPods Pro") == .unknown)
        #expect(route("hdmi", name: "AirPods Max") == .display)
    }

    @Test func undecidableTransportsAreUnknown() {
        for transport in ["usb ", "thun", "grup", "virt", "pci ", "1394", "eavb"] {
            #expect(route(transport, name: "Headphones") == .unknown, "transport \(transport)")
        }
        #expect(OutputRouteClassifier.route(transport: 0, dataSource: nil, name: nil) == .unknown)
    }
}
