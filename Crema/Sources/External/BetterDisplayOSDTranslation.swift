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

    /// Where a reported level belongs. Resolved at the border from BetterDisplay's
    /// raw CGDirectDisplayID, because the domain keys displays by UUID and the
    /// numeric ID is reassigned across sessions and reconnections.
    ///
    /// It deliberately does NOT distinguish built-in from external. What matters is
    /// whether the neighbour NAMED a display, and it names one every time — folding
    /// "it named the built-in" into the domain's nil threw that away, and nil is
    /// what the presentation layer reads as "nobody said which screen, so draw on
    /// all of them" (docs/DECISIONS.md: hud-belongs-to-its-display). Field symptom:
    /// with the pointer on the laptop the bar appeared on BOTH displays, while with
    /// the pointer on the monitor it correctly appeared only there.
    enum Target: Equatable {
        /// The payload carried no display at all — genuinely unnamed.
        case unnamed
        /// The display the neighbour named, built-in included.
        case display(DisplayUUID)

        /// The domain's own spelling: nil means no display was named.
        var display: DisplayUUID? {
            switch self {
            case .unnamed: nil
            case .display(let uuid): uuid
            }
        }
    }

    /// Decodes one payload. `target` resolves BetterDisplay's raw display ID —
    /// injected so this stays a pure function; the system call lives in the
    /// source. A display it cannot resolve is dropped: a bar for a screen the app
    /// cannot name is one it can neither place nor send a drag back to.
    ///
    /// Volume and mute are deliberately NOT translated even though BetterDisplay
    /// reports them: Core Audio already emits for every volume change whoever
    /// caused it, so a second source for the same event would draw two HUDs.
    /// Brightness has no such notification — that absence is the whole reason
    /// this source exists (docs/DECISIONS.md: media-key-chain-contention).
    static func systemHUD(fromJSON json: String, target: (Int) -> Target?) -> SystemHUD? {
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let value = payload.value,
              payload.lock != true,
              isBrightness(payload),
              // A payload naming no display is the built-in one — the same
              // default the domain uses when the field is absent.
              let resolved = payload.displayID.map(target) ?? .unnamed
        else { return nil }

        // The scale is BetterDisplay's own (observed: 0...64 on a built-in
        // display), so the ratio is the only portable reading — and a payload
        // that names no maximum is DROPPED rather than assigned a guessed one.
        // Inventing a scale would draw a confidently wrong bar, and with the
        // neighbour's own OSD turned off that bar is the user's only feedback:
        // no HUD beats a lying HUD. Clamping covers the rest.
        guard let maxValue = payload.maxValue, maxValue > 0 else { return nil }
        let normalized = min(max(value / maxValue, 0), 1)

        return SystemHUD(
            kind: .screenBrightness,
            value: normalized,
            display: resolved.display,
            authority: .betterDisplay
        )
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
