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
    struct Verdict: Equatable {
        let uuid: String
        let succeeded: Bool
        let payload: String?
    }

    /// A brightness write for one display. The value is normalized 0...1 here —
    /// the same scale the app's own actuators speak — because BetterDisplay's
    /// `brightness` feature takes a fraction; its 0...64 scale appears only in the
    /// OSD payload, which is a different message entirely.
    static func setBrightnessRequest(uuid: String, value: Double, displayID: Int) -> String? {
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

    /// A read of one identifier. No production caller — kept because it is the seam
    /// any future attempt at reading the neighbour needs, and because what it can
    /// and cannot fetch is now measured rather than assumed.
    ///
    /// This shape WORKS: `UUID`, `name`, `serial`, `vendor`, `model` and
    /// `productName` all come back with `result=true` and a payload, and the UUID it
    /// answers matches what macOS reports for the same panel. The LEVEL does not:
    /// `brightness`, `combinedBrightness`, `hardwareBrightness`,
    /// `softwareBrightness` and `ddcBrightness` are each refused with
    /// `result=false, payload=nil` (macOS 26.5.2, BetterDisplay 4.3.5).
    ///
    /// That refusal is why the brightness KEYS stay on the built-in display: with no
    /// level to read there is no step to compute and no read-back to verify, and a
    /// consumed key that cannot be verified is what the suppression contract
    /// forbids. The slider needs no read — it carries its own absolute value — which
    /// is why dragging works on an external and pressing the key does not.
    /// (docs/DECISIONS.md: external-brightness-is-write-only)
    static func identifierRequest(uuid: String, identifier: String, displayID: Int) -> String? {
        encode(Request(
            uuid: uuid,
            commands: ["get"],
            parameters: ["displayID": String(displayID), "identifier": identifier]
        ))
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
