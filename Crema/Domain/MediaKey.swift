/// One media-key press, already translated into the app's vocabulary at the
/// source border (the tap). Transport keys (play/pause/next) are deliberately
/// absent — media control flows through the now-playing pipeline, not here.
enum MediaKey: Equatable, Sendable {
    case volumeUp
    case volumeDown
    case mute
    case screenBrightnessUp
    case screenBrightnessDown
    case keyboardBrightnessUp
    case keyboardBrightnessDown
}
