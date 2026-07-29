import Foundation

/// Pure translation of BetterDisplay's OSD notification into the domain.
///
/// BetterDisplay posts a JSON string as the notification's `object` (not in
/// `userInfo`), documented in its "OSD notification dispatch integration using
/// DNC" reference. Every field is optional there, so this decodes defensively
/// and answers nil for anything Crema does not draw — nothing of BetterDisplay's
/// shape travels above this file.
enum BetterDisplayOSDTranslation {
    /// The payload, exactly as documented. Fields Crema does not use (text,
    /// customSymbol, the fade timings) are decoded but ignored: the reference
    /// states a receiver may handle only part of the data.
    private struct Payload: Decodable {
        var displayID: Int?
        var systemIconID: Int?
        var controlTarget: String?
        var value: Double?
        var maxValue: Double?
        /// BetterDisplay marks a control the user cannot move right now. Drawing
        /// it as an ordinary bar would show a level that refuses to budge, so
        /// these are dropped rather than represented.
        var lock: Bool?
    }

    /// Which `controlTarget` values mean "the screen brightness Crema draws".
    /// BetterDisplay reports the target it drove, and the three brightness
    /// flavours (its combined curve, the hardware level, the software dimming)
    /// are all the same bar to the user.
    private static let brightnessTargets: Set<String> = [
        "combinedBrightness", "hardwareBrightness", "softwareBrightness",
    ]

    /// `systemIconID` 1 = brightness (3 = volume, 4 = mute, 0 = no icon).
    private static let brightnessIconID = 1

    /// Decodes one payload. `isBuiltInDisplay` answers whether BetterDisplay's raw
    /// CGDirectDisplayID is the built-in screen — injected so this stays a pure
    /// function; the system call lives in the source.
    ///
    /// Events for any other display are dropped. Not an oversight: `display == nil`
    /// is the domain's word for the built-in screen, and the screen-brightness
    /// actuator refuses every other target (`externalDisplayUnsupported`), so a HUD
    /// carrying an external display would come with a slider that throws on the
    /// first drag. Crema shows a bar only where it can also move it; external
    /// displays wait for the outbound half of this integration (ROADMAP.md).
    ///
    /// Volume and mute are deliberately NOT translated even though BetterDisplay
    /// reports them: Core Audio already emits for every volume change whoever
    /// caused it, so a second source for the same event would draw two HUDs.
    /// Brightness has no such notification — that absence is the whole reason
    /// this source exists (docs/DECISIONS.md: media-key-chain-contention).
    static func systemHUD(fromJSON json: String, isBuiltInDisplay: (Int) -> Bool) -> SystemHUD? {
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let value = payload.value,
              payload.lock != true,
              isBrightness(payload),
              // A payload with no display named is the built-in one — the same
              // default the domain uses when the field is absent.
              payload.displayID.map(isBuiltInDisplay) ?? true
        else { return nil }

        // The scale is BetterDisplay's own (observed: 0...64 on a built-in
        // display), so the ratio is the only portable reading — and a payload
        // that names no maximum is DROPPED rather than assigned a guessed one.
        // Inventing a scale would draw a confidently wrong bar, and with the
        // neighbour's own OSD turned off that bar is the user's only feedback:
        // no HUD beats a lying HUD. Clamping covers the rest.
        guard let maxValue = payload.maxValue, maxValue > 0 else { return nil }
        let normalized = min(max(value / maxValue, 0), 1)

        return SystemHUD(kind: .screenBrightness, value: normalized)
    }

    /// The target names the control precisely, so it decides when present; the
    /// icon is the fallback for a payload that omits it. Anything else — contrast,
    /// gamma, temperature, blue light — is a control Crema has no HUD for, and
    /// answering nil is how those stay invisible instead of drawing a wrong bar.
    private static func isBrightness(_ payload: Payload) -> Bool {
        if let target = payload.controlTarget {
            return brightnessTargets.contains(target)
        }
        return payload.systemIconID == brightnessIconID
    }
}
