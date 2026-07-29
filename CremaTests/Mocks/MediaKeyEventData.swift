/// Builds the NX_SYSDEFINED `data1` payload for a synthetic media/special key
/// event: keyCode in the high word, key state 0x0A (down) / 0x0B (up) in the
/// second byte, repeat flag in bit 0. One builder for every suite that fires
/// synthetic keys — the layout used to live as three private mirrors, which is
/// exactly how a bit drifts in one copy and its suite keeps testing a payload
/// the tap never sees.
func mediaKeyData1(keyCode: Int, down: Bool, isRepeat: Bool = false) -> Int {
    (keyCode << 16) | ((down ? 0x0A : 0x0B) << 8) | (isRepeat ? 1 : 0)
}
