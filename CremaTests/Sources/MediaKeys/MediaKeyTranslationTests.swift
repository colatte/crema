import Testing
@testable import Crema

/// Pure translation of NX_SYSDEFINED aux-button payloads into domain
/// MediaKey events. The CGEventTap border itself is manual-smoke.
struct MediaKeyTranslationTests {

    /// Builds a synthetic `data1` payload: keyCode in the high word, key state
    /// (0x0A down / 0x0B up) in the second byte, repeat flag in bit 0.
    private func data1(keyCode: Int, down: Bool, isRepeat: Bool = false) -> Int {
        (keyCode << 16) | ((down ? 0x0A : 0x0B) << 8) | (isRepeat ? 1 : 0)
    }

    @Test func mapsVolumeKeys() {
        #expect(MediaKeyTranslation.mediaKey(fromKeyCode: 0) == .volumeUp)
        #expect(MediaKeyTranslation.mediaKey(fromKeyCode: 1) == .volumeDown)
        #expect(MediaKeyTranslation.mediaKey(fromKeyCode: 7) == .mute)
    }

    @Test func mapsScreenBrightnessKeys() {
        #expect(MediaKeyTranslation.mediaKey(fromKeyCode: 2) == .screenBrightnessUp)
        #expect(MediaKeyTranslation.mediaKey(fromKeyCode: 3) == .screenBrightnessDown)
    }

    @Test func mapsKeyboardBrightnessKeys() {
        #expect(MediaKeyTranslation.mediaKey(fromKeyCode: 21) == .keyboardBrightnessUp)
        #expect(MediaKeyTranslation.mediaKey(fromKeyCode: 22) == .keyboardBrightnessDown)
    }

    @Test func ignoresKeysThatAreNotOurs() {
        // Play/pause (16), next (17), previous (18), eject (14): media
        // transport belongs to MediaRemote, not to this tap.
        for code in [16, 17, 18, 14, 5, 99] {
            #expect(MediaKeyTranslation.mediaKey(fromKeyCode: code) == nil)
        }
    }

    @Test func decodesKeyDownFromData1() {
        #expect(MediaKeyTranslation.mediaKey(fromData1: data1(keyCode: 0, down: true)) == .volumeUp)
        #expect(MediaKeyTranslation.mediaKey(fromData1: data1(keyCode: 3, down: true)) == .screenBrightnessDown)
    }

    @Test func ignoresKeyUps() {
        #expect(MediaKeyTranslation.mediaKey(fromData1: data1(keyCode: 0, down: false)) == nil)
        #expect(MediaKeyTranslation.mediaKey(fromData1: data1(keyCode: 7, down: false)) == nil)
    }

    @Test func autorepeatStillEmits() {
        // Holding a volume key repeats the adjustment; each repeat is an event.
        #expect(MediaKeyTranslation.mediaKey(fromData1: data1(keyCode: 1, down: true, isRepeat: true)) == .volumeDown)
    }

    @Test func unknownKeyDownsAreIgnoredInFullDecode() {
        #expect(MediaKeyTranslation.mediaKey(fromData1: data1(keyCode: 16, down: true)) == nil)
    }

    @Test func mediaKeyIsSendable() {
        func requireSendable<T: Sendable>(_: T.Type) {}
        requireSendable(MediaKey.self)
        #expect(Bool(true))
    }
}
