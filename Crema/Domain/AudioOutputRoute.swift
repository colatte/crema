/// What kind of device the system's sound goes to, as far as the volume source
/// could tell. The source settles it at the edge from the device's transport,
/// data source and, on Bluetooth only, its name; nothing above it sees those
/// readings (docs/DECISIONS.md: the-output-glyph-names-only-what-it-knows).
enum AudioOutputRoute: Equatable, Sendable, CaseIterable {
    case builtInSpeakers
    /// Headphones on the Mac's own jack.
    case wiredHeadphones
    /// A Bluetooth device whose name names no model the glyphs can show.
    case bluetoothHeadphones
    case airPods
    case airPodsPro
    case airPodsMax
    case beats
    case airPlay
    /// A screen's speakers, reached over HDMI or DisplayPort.
    case display
    /// A device whose kind the readings cannot settle: USB, Thunderbolt, an
    /// aggregate, a virtual driver, an unreadable transport.
    case unknown
}
