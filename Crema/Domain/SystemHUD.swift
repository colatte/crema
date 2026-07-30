/// One system HUD event: what changed, to which level, and on which display.
struct SystemHUD: Equatable, Sendable {
    enum Kind: Equatable, Sendable, CaseIterable {
        case volume
        case screenBrightness
        case keyboardBrightness
    }

    /// Who produced this reading, and therefore who a drag on it must be sent
    /// back to. The two do not measure the same thing: an app that blends
    /// hardware brightness with software dimming reports its blended level, while
    /// the system's own reading is the hardware one — so a bar drawn from one and
    /// dragged into the other writes a level the user did not aim at
    /// (docs/DECISIONS.md: betterdisplay-osd-source).
    enum Authority: Equatable, Sendable {
        case system
        case betterDisplay
    }

    /// Which screen a reading speaks for — a ROLE, not an identity the producer
    /// had to resolve. Whoever turned the knob knows which knob it was; only the
    /// panel roster knows which PANEL that is, and this app's two inventories of
    /// screens disagree by design (the roster drops a screen with no
    /// NSScreenNumber or no resolvable UUID and AppKit collapses a mirror set to
    /// one NSScreen, while the active-display list keeps them). A UUID resolved at
    /// the border would be a key cut from the other lock, and a HUD naming a
    /// display no panel carries shows on no screen at all.
    enum Target: Equatable, Sendable {
        /// No screen owns this reading: volume belongs to the output device, the
        /// backlight to the one keyboard.
        case noDisplay
        /// The built-in panel — the only screen the local brightness border reads
        /// or writes. Matched against the roster at presentation time.
        case builtIn
        /// The display the producer named, built-in included.
        case display(DisplayUUID)
    }

    var kind: Kind
    /// Normalized to 0...1; sources convert whatever scale the system uses.
    var value: Double
    var isMuted: Bool = false
    /// Which screen this reading is about. Three distinct facts a single
    /// `DisplayUUID?` used to fold into one, and folding "the built-in" into
    /// "nobody said which screen" is what drew the built-in panel's bar on EVERY
    /// panel — measured in the field, pointer on the laptop, with a drag on the
    /// monitor's copy dimming the laptop in silence
    /// (docs/DECISIONS.md: hud-target-is-a-role).
    var target: Target = .noDisplay
    var authority: Authority = .system

    /// The actuation spelling of `target`: nil wherever an actuator already reads
    /// nil as "my own panel". Both brightness actuators do — the system one
    /// accepts nil OR the built-in's own UUID, the neighbour's resolves nil to the
    /// built-in ID — and the volume actuator rejects any non-nil display outright,
    /// so `.builtIn` has to arrive as nil or a drag on the local bar would throw
    /// where it used to write.
    var commandDisplay: DisplayUUID? {
        switch target {
        case .noDisplay, .builtIn: nil
        case .display(let uuid): uuid
        }
    }

    /// The same reading at a new level — what a drag on this HUD produced, kept
    /// on its own scale, target and authority so the echo lands where the bar is.
    func at(_ value: Double) -> Self {
        var copy = self
        copy.value = value
        return copy
    }

    /// The same reading credited to another authority — what a write that had to
    /// fall back reports, so the next drag goes where this one actually landed.
    func by(_ authority: Authority) -> Self {
        var copy = self
        copy.authority = authority
        return copy
    }
}
