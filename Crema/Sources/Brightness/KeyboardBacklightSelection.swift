/// Pure selection of the built-in keyboard among the opaque IDs the private
/// API reports. Strict on purpose: if none is flagged built-in we return nil
/// (feature degrades) rather than guessing and controlling the wrong keyboard.
enum KeyboardBacklightSelection {
    static func builtInID(from ids: [UInt64], isBuiltIn: (UInt64) -> Bool) -> UInt64? {
        ids.first(where: isBuiltIn)
    }
}
