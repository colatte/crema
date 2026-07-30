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

    /// A read of one METADATA identifier — UUID, name, serial, vendor, model,
    /// productName. No production caller yet; kept because it is the seam a reader
    /// of the neighbour needs, and because the shape is now measured.
    ///
    /// `identifier` is the metadata door and ONLY that. A feature is asked for by
    /// its own name as the parameter key with no value — `parameters: ["displayID":
    /// "2", "brightness": ""]` answers `result=true, payload=0.063` — and a relative
    /// write uses the documented `offset` parameter rather than a sign on the value,
    /// which is read as an absolute.
    ///
    /// Worth stating because the mistake was expensive: five spellings of brightness
    /// were probed through `identifier`, all refused, and that became a written
    /// claim that the neighbour could be written but never read — which retired the
    /// feature that needed the read. It was the wrong door, not a missing one
    /// (docs/DECISIONS.md: neighbour-features-are-not-identifiers).
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
