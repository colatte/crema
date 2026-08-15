import Testing
@testable import Crema

/// The command half: a broadcast pretending to be a call. What has to hold is
/// that an answer is matched to its question, that a neighbour who never answers
/// cannot hang a caller, and that a refusal reads differently from silence.
@MainActor
struct BetterDisplayCommandChannelTests {

    /// Captures the request instead of broadcasting it, and hands answers back
    /// the way a delivered notification would.
    private final class Wire {
        var posted: [String] = []
    }

    private func makeChannel(_ wire: Wire, clock: TestSleepClock, uuid: String = "REQ-1")
    -> BetterDisplayCommandChannel {
        BetterDisplayCommandChannel(
            clock: clock,
            timeout: 1.5,
            newUUID: { uuid },
            post: { wire.posted.append($0) }
        )
    }

    @Test func aYesCompletesTheCall() async throws {
        let wire = Wire()
        let clock = TestSleepClock()
        let channel = makeChannel(wire, clock: clock)

        let call = Task { try await channel.setBrightness(0.75, displayID: 2) }
        await clock.waitForSleep()                      // the deadline is armed
        // #expect does not halt the test, so the subscript needs its own guard —
        // a trap here would kill the host and every in-flight sibling.
        let request = try #require(wire.posted.first)
        #expect(wire.posted.count == 1)
        #expect(request.contains("\"brightness\":\"0.75\""))
        #expect(request.contains("\"displayID\":\"2\""))

        channel.handle(response: #"{"uuid":"REQ-1","result":true}"#)
        try await call.value
    }

    @Test func aNoIsARefusalNotSilence() async throws {
        let wire = Wire()
        let clock = TestSleepClock()
        let channel = makeChannel(wire, clock: clock)

        let call = Task { try await channel.setBrightness(0.5, displayID: 1) }
        await clock.waitForSleep()
        channel.handle(response: #"{"uuid":"REQ-1","result":false}"#)

        await #expect(throws: BetterDisplayCommandChannel.CommandError.refused) {
            try await call.value
        }
    }

    @Test func silenceEndsAtTheDeadlineInsteadOfWaitingForever() async throws {
        // The neighbour may not be running at all; a distributed notification
        // to nobody looks exactly like one to somebody busy.
        let wire = Wire()
        let clock = TestSleepClock()
        let channel = makeChannel(wire, clock: clock)

        let call = Task { try await channel.setBrightness(0.5, displayID: 1) }
        await clock.waitForSleep()
        clock.advance()

        await #expect(throws: BetterDisplayCommandChannel.CommandError.unanswered) {
            try await call.value
        }
    }

    @Test func someoneElsesAnswerIsNotOurs() async throws {
        // The channel is a broadcast: other apps' responses arrive here too, and
        // reading one as our own would report a stranger's success as ours.
        let wire = Wire()
        let clock = TestSleepClock()
        let channel = makeChannel(wire, clock: clock)

        let call = Task { try await channel.setBrightness(0.5, displayID: 1) }
        await clock.waitForSleep()
        channel.handle(response: #"{"uuid":"SOMEONE-ELSE","result":true}"#)
        channel.handle(response: "not json")
        clock.advance()

        await #expect(throws: BetterDisplayCommandChannel.CommandError.unanswered) {
            try await call.value
        }
    }
}

/// The wire format on its own, where the shape of the request is decided.
struct BetterDisplayCommandTranslationTests {

    @Test func aBrightnessRequestNamesTheDisplayAndTheFeature() throws {
        let json = try #require(BetterDisplayCommandTranslation.setBrightnessRequest(
            uuid: "ABC", value: 0.4, displayID: 3
        ))
        #expect(json.contains("\"uuid\":\"ABC\""))
        #expect(json.contains("\"set\""))
        #expect(json.contains("\"displayID\":\"3\""))
        #expect(json.contains("\"brightness\":\"0.4\""))
    }

    @Test func aValueOutsideTheScaleIsClampedBeforeItLeaves() {
        // The neighbour is another app: sending it nonsense is not its problem
        // to reject.
        #expect(BetterDisplayCommandTranslation.setBrightnessRequest(uuid: "A", value: 5, displayID: 1)?
            .contains("\"brightness\":\"1.0\"") == true)
        #expect(BetterDisplayCommandTranslation.setBrightnessRequest(uuid: "A", value: -3, displayID: 1)?
            .contains("\"brightness\":\"0.0\"") == true)
    }

    @Test func aValueThatIsNotANumberNeverReachesTheWire() {
        // NaN compares false against everything, so the clamp passes it through
        // intact and the request would have carried the string "nan" — nonsense the
        // neighbour can only reject, arriving as a plausible command. Nil is a
        // failed apply at the caller, which rolls the bar back to the level the
        // screen still has.
        #expect(BetterDisplayCommandTranslation.setBrightnessRequest(
            uuid: "A", value: .nan, displayID: 1
        ) == nil)

        // The infinities are a different case and stay clamped: they saturate to the
        // near end like any out-of-range reading, exactly as the domain's own
        // conversions promise.
        #expect(BetterDisplayCommandTranslation.setBrightnessRequest(uuid: "A", value: .infinity, displayID: 1)?
            .contains("\"brightness\":\"1.0\"") == true)
        #expect(BetterDisplayCommandTranslation.setBrightnessRequest(uuid: "A", value: -.infinity, displayID: 1)?
            .contains("\"brightness\":\"0.0\"") == true)
    }

    @Test func averdictCarriesItsQuestionsIdentity() throws {
        let verdict = try #require(BetterDisplayCommandTranslation.verdict(
            fromJSON: #"{"uuid":"XYZ","result":true,"payload":"0.69"}"#
        ))
        #expect(verdict == .init(uuid: "XYZ", succeeded: true, payload: "0.69"))
    }

    @Test func anAnswerWithNoIdentityIsNoAnswer() {
        // Nothing to match it against, so acting on it would be guessing.
        #expect(BetterDisplayCommandTranslation.verdict(fromJSON: #"{"result":true}"#) == nil)
        #expect(BetterDisplayCommandTranslation.verdict(fromJSON: "garbage") == nil)
    }

    @Test func aMissingResultReadsAsFailure() {
        // Every field is optional in the published format; absence of a yes is
        // not a yes.
        let verdict = BetterDisplayCommandTranslation.verdict(fromJSON: #"{"uuid":"X"}"#)
        #expect(verdict?.succeeded == false)
    }
}
