/// Pure translation of NX_SYSDEFINED auxiliary-button payloads into domain
/// MediaKey events. The IOKit ev_keymap.h constants are restated here so this
/// layer needs no import at all — the CGEventTap border feeds it raw integers.
enum MediaKeyTranslation {
    /// CGEvent type of NX_SYSDEFINED events (the tap's event mask).
    static let systemDefinedEventType: UInt32 = 14
    /// The same type as a CGEventMask bit. Stated once so the tap we install and
    /// the chain check that looks for rivals over the same events can never
    /// drift apart.
    static let systemDefinedMask: UInt64 = 1 << UInt64(systemDefinedEventType)
    /// NSEvent subtype for aux control buttons (NX_SUBTYPE_AUX_CONTROL_BUTTONS).
    static let auxiliaryControlSubtype: Int16 = 8

    /// Full decode of an aux-button `data1` payload: keyCode in the high word,
    /// key state in the second byte (0x0A down / 0x0B up), repeat in the low byte.
    /// Not folklore: the producer packs it as `(flavor << 16) | (eventType << 8) |
    /// repeat` and Apple's own NX event dumper reads it back with those exact shifts
    /// (IOHIDFamily 701.20.10 IOHIDSystem.cpp; 1633 tools/IOHIDNXEventDescription.c).
    /// Key-ups return nil; autorepeats emit (holding a key keeps adjusting).
    static func mediaKey(fromData1 data1: Int) -> MediaKey? {
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = data1 & 0x0000_FFFF
        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A
        guard isKeyDown else { return nil }
        return mediaKey(fromKeyCode: keyCode)
    }

    /// Phase-blind decode for the consumption path: when suppressing, both
    /// phases (down and up) of an owned key must be swallowed — an orphan
    /// key-up reaching the system after its down was eaten would confuse the
    /// system's key pairing. The stream keeps using the down-only decode.
    static func ownedKey(ignoringPhaseFromData1 data1: Int) -> MediaKey? {
        mediaKey(fromKeyCode: (data1 & 0xFFFF_0000) >> 16)
    }

    /// NX_KEYTYPE_* → domain. Anything not ours (play/pause, next, eject…)
    /// returns nil and the event passes by untouched.
    static func mediaKey(fromKeyCode keyCode: Int) -> MediaKey? {
        switch keyCode {
        case 0: .volumeUp                 // NX_KEYTYPE_SOUND_UP
        case 1: .volumeDown               // NX_KEYTYPE_SOUND_DOWN
        case 7: .mute                     // NX_KEYTYPE_MUTE
        case 2: .screenBrightnessUp       // NX_KEYTYPE_BRIGHTNESS_UP
        case 3: .screenBrightnessDown     // NX_KEYTYPE_BRIGHTNESS_DOWN
        case 21: .keyboardBrightnessUp    // NX_KEYTYPE_ILLUMINATION_UP
        case 22: .keyboardBrightnessDown  // NX_KEYTYPE_ILLUMINATION_DOWN
        default: nil
        }
    }
}
