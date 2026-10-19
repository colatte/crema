import Foundation

/// The wire format of BetterDisplay's request/response integration, kept pure so
/// the encoding and the verdict reading are testable without a notification in
/// sight. Nothing of this shape travels above the channel that uses it.
///
/// Request and response are JSON strings carried in the notification's `object`
/// (never `userInfo`), matched by a `uuid` the caller mints — that pairing is the
/// only thing making a shared broadcast channel usable as a call.
enum BetterDisplayCommandTranslation {
    private struct Request: Encodable {
        let uuid: String
        let commands: [String]
        let parameters: [String: String]
    }

    private struct Response: Decodable {
        let uuid: String?
        let result: Bool?
        let payload: String?
    }

    /// The verdict BetterDisplay returned for one request.
    struct Verdict: Equatable, Sendable {
        let uuid: String
        let succeeded: Bool
        let payload: String?
    }

    /// A brightness write for one display. The value is normalized 0...1 here —
    /// the same scale the app's own actuators speak — because BetterDisplay's
    /// `brightness` feature takes a fraction; its 0...64 scale appears only in the
    /// OSD payload, which is a different message entirely.
    static func setBrightnessRequest(uuid: String, value: Double, displayID: Int) -> String? {
        // NaN is refused rather than clamped: it compares false against everything,
        // so `max(value, 0)` returns it intact and the wire would carry the string
        // "nan" — a request the neighbour can only reject, arriving as a plausible
        // one. Nil is read by the channel as a failed apply, which rolls the bar
        // back to the level the screen still has; a fabricated 0 would darken a
        // display over a number nobody asked for. The infinities need no branch —
        // they saturate to the near end like any out-of-range reading, which is the
        // same contract the domain's own conversions document
        // (VolumeConversion.normalize).
        guard !value.isNaN else { return nil }
        let clamped = min(max(value, 0), 1)
        return encode(Request(
            uuid: uuid,
            // `brightness` rather than `combinedBrightness`: BetterDisplay
            // documents it as auto-selecting the display's most appropriate
            // control, which is what keeps the write on the same scale the user
            // sees, whatever they configured for that display.
            commands: ["set"],
            parameters: ["displayID": String(displayID), "brightness": String(clamped)]
        ))
    }

    /// A read of one of the neighbour's feedback switches. A feature is asked for
    /// by its own name as the parameter key, with no value (docs/DECISIONS.md:
    /// neighbour-features-are-not-identifiers).
    static func getRequest(uuid: String, setting: NeighbourOSDSetting) -> String? {
        encode(Request(uuid: uuid, commands: ["get"], parameters: [parameter(for: setting): ""]))
    }

    /// A write of one of the neighbour's feedback switches.
    static func setRequest(uuid: String, setting: NeighbourOSDSetting, value: Bool) -> String? {
        encode(Request(uuid: uuid, commands: ["set"], parameters: [parameter(for: setting): value ? "on" : "off"]))
    }

    /// The switch a `get` answered with, or nil for anything that is not the
    /// documented `on` or `off`: a guess here would decide what to hand back.
    static func switchValue(fromPayload payload: String?) -> Bool? {
        switch payload {
        case "on": true
        case "off": false
        default: nil
        }
    }

    /// BetterDisplay's names for the switches, from its CLI reference (BetterDisplay
    /// Guide, "CLI reference", read 2026-10-18): `osdIntegrationNotification` is
    /// Settings → Application → Integration → "Dispatch OSD notifications", and
    /// `osdShowBasic` is Settings → Keyboard → OSD → "Show brightness, volume, mute
    /// OSD". `osdShowCustom` stays the user's: it covers shortcuts Crema draws
    /// nothing for.
    private static func parameter(for setting: NeighbourOSDSetting) -> String {
        switch setting {
        case .dispatchesToOtherApps: "osdIntegrationNotification"
        case .showsOwnIndicator: "osdShowBasic"
        }
    }

    /// Nil for anything that is not a verdict we can act on — a malformed body, or
    /// one with no uuid to match a request against.
    static func verdict(fromJSON json: String) -> Verdict? {
        guard let data = json.data(using: .utf8),
              let response = try? JSONDecoder().decode(Response.self, from: data),
              let uuid = response.uuid
        else { return nil }
        return Verdict(uuid: uuid, succeeded: response.result ?? false, payload: response.payload)
    }

    private static func encode(_ request: Request) -> String? {
        guard let data = try? JSONEncoder().encode(request) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
