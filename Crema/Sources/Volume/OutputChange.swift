/// One Core Audio notification on the output side, as the volume source sorts
/// it. Pure so the rule below is pinned by a test: the notifications themselves
/// arrive from Core Audio, which no unit test touches.
enum OutputChange: CaseIterable {
    /// The observed device's volume or mute moved.
    case level
    /// The observed device selected another data source (a jack plugged into a
    /// built-in port).
    case dataSource
    /// Another device became the default output.
    case defaultDevice

    /// Only a level change pops the HUD. A new device or data source is the
    /// sound moving, not the user turning it up: the route is re-read in
    /// silence and the next volume event draws it.
    var popsHUD: Bool { self == .level }
}
