import Foundation
import os

/// Asks BetterDisplay to apply a level, and waits for its verdict.
///
/// A distributed notification is a broadcast, not a call: the request carries a
/// uuid and the answer comes back on a different name carrying the same one, so
/// pairing is ours to do. And an app that is not running, or is busy, simply
/// never answers — hence a deadline, without which a swallowed key would wait
/// forever on a neighbour that may not exist.
protocol BetterDisplayCommanding: Sendable {
    /// Sets brightness (0...1) on the display BetterDisplay knows by `displayID`.
    /// Throws when the app refuses or does not answer in time; the caller treats
    /// that like any other failed apply.
    func setBrightness(_ value: Double, displayID: Int) async throws
}

@MainActor
final class BetterDisplayCommandChannel: BetterDisplayCommanding {
    enum CommandError: Error, Equatable {
        /// No answer inside the deadline: BetterDisplay is gone, wedged, or its
        /// integration is switched off.
        case unanswered
        /// It answered, and the answer was no.
        case refused
    }

    private static let requestName = "pro.betterdisplay.BetterDisplay.request"
    private static let responseName = "pro.betterdisplay.BetterDisplay.response"

    private let clock: any SleepClock
    private let timeout: Double
    private let post: @MainActor (String) -> Void
    private let newUUID: @MainActor () -> String
    /// In-flight requests by uuid. A broadcast channel carries other apps'
    /// answers too, so anything not in here is not ours to read. The raced value
    /// is optional on purpose: nil is the deadline (nobody answered), and a
    /// wrapped Bool is BetterDisplay's own yes or no — collapsing the two would
    /// report a refusal as a timeout and hide which side failed.
    private var pending: [String: SingleResumeRace<Bool?, Never>] = [:]
    // nonisolated(unsafe): written only while `init` runs (installObserver) and
    // read only in `deinit`, after every other access has ended — the lifecycle
    // brackets rule out the concurrent access the attribute waives; a nonisolated
    // deinit can't see that bracket, and removeObserver itself is thread-safe.
    //
    // A relay object rather than an opaque token, because the suspension behaviour
    // is only on the selector-based registration (see `installObserver`); the center
    // holds an observer unowned, so the deinit still has to name it.
    private nonisolated(unsafe) var responseRelay: DistributedPayloadRelay?

    private let logger = Logger.crema("External")

    /// A custom `post` means a test drives the channel: it captures the request
    /// and hands the answer back through `handle(response:)`, so no real
    /// notification is involved. Same idiom as the screen-lock source's injected
    /// session reader.
    init(
        clock: any SleepClock = ContinuousSleepClock(),
        timeout: Double = 1.5,
        newUUID: (@MainActor () -> String)? = nil,
        post: (@MainActor (String) -> Void)? = nil
    ) {
        self.clock = clock
        self.timeout = timeout
        self.newUUID = newUUID ?? { UUID().uuidString }
        self.post = post ?? { json in
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(Self.requestName),
                object: json,
                userInfo: nil,
                deliverImmediately: true
            )
        }
        if post == nil { installObserver() }
    }

    deinit {
        if let responseRelay {
            DistributedNotificationCenter.default().removeObserver(responseRelay)
        }
    }

    func setBrightness(_ value: Double, displayID: Int) async throws {
        let uuid = newUUID()
        guard let json = BetterDisplayCommandTranslation.setBrightnessRequest(
            uuid: uuid, value: value, displayID: displayID
        ) else { throw CommandError.refused }

        let race = SingleResumeRace<Bool?, Never>()
        pending[uuid] = race
        defer { pending[uuid] = nil }

        // The deadline runs detached so the wait never pins this actor, and it
        // commits its value rather than cancelling anything: there is nothing to
        // unwind — the answer either arrives or it does not.
        let deadline = Task.detached { [clock, timeout] in
            try? await clock.sleep(for: timeout)
            race.finish(nil)
        }
        defer { deadline.cancel() }

        post(json)
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
            race.begin(continuation)
        }
        switch outcome {
        case .none:
            logger.error("BetterDisplay did not answer a brightness command in time")
            throw CommandError.unanswered
        case .some(false):
            logger.error("BetterDisplay refused a brightness command")
            throw CommandError.refused
        case .some(true):
            return
        }
    }

    /// A delivered response. Internal so a test can answer a request without a
    /// real notification; answers for requests that are not ours are ignored,
    /// which is what makes a shared broadcast channel safe to listen on.
    func handle(response json: String) {
        guard let verdict = BetterDisplayCommandTranslation.verdict(fromJSON: json),
              let race = pending[verdict.uuid]
        else { return }
        race.finish(.some(verdict.succeeded))
    }

    private func installObserver() {
        // The answer comes back through the selector registration, for the
        // suspension behaviour no block-based cover can express: those default to
        // `NSNotificationSuspensionBehaviorCoalesce`
        // (`NSDistributedNotificationCenter.h`: "All other registration methods are
        // covers of this one, with the default for suspensionBehavior =
        // NSNotificationSuspensionBehaviorCoalesce"), which the server HOLDS while
        // the centre is suspended — and AppKit suspends it whenever the app is not
        // active, which an LSUIElement accessory essentially always is.
        //
        // The asymmetry that made it worse was ours: the request already goes out
        // with `deliverImmediately: true`, so the neighbour hears us however it
        // registered, while its answer was arriving into a registration that could
        // be held. And a held answer is indistinguishable from silence here — the
        // deadline fires, the drag reports a failed apply and rolls the bar back
        // over a write that actually landed.
        let relay = DistributedPayloadRelay { [weak self] json in self?.handle(response: json) }
        DistributedNotificationCenter.default().addObserver(
            relay,
            selector: #selector(DistributedPayloadRelay.payloadArrived(_:)),
            name: Notification.Name(Self.responseName),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        responseRelay = relay
    }
}
