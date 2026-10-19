import AppKit
import Foundation
import os

/// Applies a brightness level through the neighbour app that owns a display, and
/// waits for its verdict. The capability, not the technology: BetterDisplay's
/// channel below is today's one conformer, and Lunar would be the next.
protocol BrightnessCommandChannel: Sendable {
    /// Sets brightness (0...1) on the display the neighbour knows by `displayID`.
    /// Throws when the app refuses or does not answer in time; the caller treats
    /// that like any other failed apply.
    func setBrightness(_ value: Double, displayID: Int) async throws
}

/// Asks BetterDisplay to apply a level, or to read and write one of its feedback
/// switches, and waits for its verdict.
///
/// A distributed notification is a broadcast, not a call: the request carries a
/// uuid and the answer comes back on a different name carrying the same one, so
/// pairing is ours to do. And an app that is not running, or is busy, simply
/// never answers — hence a deadline, without which a swallowed key would wait
/// forever on a neighbour that may not exist.
@MainActor
final class BetterDisplayCommandChannel: BrightnessCommandChannel, OSDSettingsChannel {
    enum CommandError: Error, Equatable {
        /// No answer inside the deadline: BetterDisplay is gone, wedged, or its
        /// integration is switched off.
        case unanswered
        /// It answered, and the answer was no.
        case refused
        /// The request could not be encoded (a level that is not a number), so it
        /// never left the process: not the neighbour's no.
        case unencodable
        /// It answered yes to a read, with a payload that is not the value asked for.
        case unreadable
    }

    /// What a request waits for: the neighbour's verdict, or nil at the deadline.
    private typealias Answer = BetterDisplayCommandTranslation.Verdict?

    private static let requestName = "pro.betterdisplay.BetterDisplay.request"
    private static let responseName = "pro.betterdisplay.BetterDisplay.response"
    /// Posted "after initial app and device configuration, when normal operation
    /// is ready" (BetterDisplay Guide, "Third-party app integration", read
    /// 2026-10-18), which is the moment a request can be answered; the workspace's
    /// launch edge comes before it.
    private static let launchedName = "pro.betterdisplay.BetterDisplay.launched"

    private let clock: any SleepClock
    private let timeout: Double
    private let post: @MainActor (String) -> Void
    private let newUUID: @MainActor () -> String
    /// In-flight requests by uuid. A broadcast channel carries other apps'
    /// answers too, so anything not in here is not ours to read. The raced value
    /// is optional on purpose: nil is the deadline (nobody answered), and a
    /// wrapped verdict is BetterDisplay's own yes or no — collapsing the two would
    /// report a refusal as a timeout and hide which side failed.
    private var pending: [String: SingleResumeRace<Answer, Never>] = [:]
    // nonisolated(unsafe): written only while `init` runs (installObserver) and
    // read only in `deinit`, after every other access has ended — the lifecycle
    // brackets rule out the concurrent access the attribute waives; a nonisolated
    // deinit can't see that bracket, and removeObserver itself is thread-safe.
    //
    // A relay object rather than an opaque token, because the suspension behaviour
    // is only on the selector-based registration (see `installObserver`); the center
    // holds an observer unowned, so the deinit still has to name it.
    private nonisolated(unsafe) var responseRelay: DistributedPayloadRelay?
    private nonisolated(unsafe) var launchRelay: DistributedPayloadRelay?
    private nonisolated(unsafe) var terminationObserver: NSObjectProtocol?

    /// Called each time BetterDisplay says it is ready to answer: a neighbour
    /// launched after Crema has heard nothing Crema asked before it was there.
    var onNeighbourLaunched: (@MainActor () -> Void)?

    /// Called when BetterDisplay's process ends, by whatever means: whatever the
    /// last request learned about it stops being true.
    var onNeighbourTerminated: (@MainActor () -> Void)?

    private let logger = Logger.crema("External")

    /// How long a command waits for the neighbour's verdict before it counts as
    /// unanswered. A margin, not a measurement: BetterDisplay 5.1.1 answered every
    /// settings request in 1–7 ms (`scripts/probes/osd-settings-betterdisplay.swift`,
    /// 2026-10-18), and no probe has timed a brightness command, so the number is a
    /// choice far above the one round-trip measured, pinned by test so that it
    /// changes only on purpose.
    /// Invalidating signal: a drag whose bar rolls back while the screen did move
    /// (the "did not answer … in time" line beside a brightness change), or a
    /// probe that puts the round-trip near this bound.
    static let defaultTimeout: Double = 1.5

    /// A custom `post` means a test drives the channel: it captures the request
    /// and hands the answer back through `handle(response:)`, so no real
    /// notification is involved. Same idiom as the screen-lock source's injected
    /// session reader.
    init(
        clock: any SleepClock = ContinuousSleepClock(),
        timeout: Double = BetterDisplayCommandChannel.defaultTimeout,
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
        for relay in [responseRelay, launchRelay].compactMap(\.self) {
            DistributedNotificationCenter.default().removeObserver(relay)
        }
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
    }

    func setBrightness(_ value: Double, displayID: Int) async throws {
        let uuid = newUUID()
        guard let json = BetterDisplayCommandTranslation.setBrightnessRequest(
            uuid: uuid, value: value, displayID: displayID
        ) else { throw CommandError.unencodable }
        _ = try await send(json, uuid: uuid, describing: "a brightness command")
    }

    func read(_ setting: NeighbourOSDSetting) async throws(OSDSettingsError) -> Bool {
        do {
            let uuid = newUUID()
            guard let json = BetterDisplayCommandTranslation.getRequest(uuid: uuid, setting: setting) else {
                throw CommandError.unencodable
            }
            let payload = try await send(json, uuid: uuid, describing: "a read of \(setting.rawValue)")
            guard let value = BetterDisplayCommandTranslation.switchValue(fromPayload: payload) else {
                logger.error("BetterDisplay answered a read of \(setting.rawValue, privacy: .public) with no on/off")
                throw CommandError.unreadable
            }
            return value
        } catch {
            throw Self.settingsError(error)
        }
    }

    func write(_ setting: NeighbourOSDSetting, to value: Bool) async throws(OSDSettingsError) {
        do {
            let uuid = newUUID()
            guard let json = BetterDisplayCommandTranslation.setRequest(uuid: uuid, setting: setting, value: value) else {
                throw CommandError.unencodable
            }
            _ = try await send(json, uuid: uuid, describing: "a write of \(setting.rawValue)")
        } catch {
            throw Self.settingsError(error)
        }
    }

    /// A delivered response. Internal so a test can answer a request without a
    /// real notification; answers for requests that are not ours are ignored,
    /// which is what makes a shared broadcast channel safe to listen on.
    func handle(response json: String) {
        guard let verdict = BetterDisplayCommandTranslation.verdict(fromJSON: json),
              let race = pending[verdict.uuid]
        else { return }
        race.finish(.some(verdict))
    }

    /// Posts one request and waits for its verdict, returning the payload of a yes.
    private func send(_ json: String, uuid: String, describing what: String) async throws -> String? {
        let race = SingleResumeRace<Answer, Never>()
        pending[uuid] = race
        defer { pending[uuid] = nil }

        // The deadline commits nil (nobody answered) and unwinds nothing: the
        // answer either arrives or it does not.
        let deadline = race.armDeadline(seconds: timeout, on: clock, committing: .success(nil))
        defer { deadline.cancel() }

        post(json)
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<Answer, Never>) in
            race.begin(continuation)
        }
        guard let verdict = outcome else {
            logger.error("BetterDisplay did not answer \(what, privacy: .public) in time")
            throw CommandError.unanswered
        }
        guard verdict.succeeded else {
            logger.error("BetterDisplay refused \(what, privacy: .public)")
            throw CommandError.refused
        }
        return verdict.payload
    }

    /// The settings protocol speaks the domain's two outcomes, so the caller reads
    /// no type of BetterDisplay's: silence is silence, and every other way a
    /// request fails is a no the person can only answer in the neighbour's window.
    private static func settingsError(_ error: any Error) -> OSDSettingsError {
        (error as? CommandError) == .unanswered ? .unanswered : .refused
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
        // The asymmetry to avoid is ours: the request already goes out
        // with `deliverImmediately: true`, so the neighbour hears us however it
        // registered, while an answer taken through a cover would arrive into a
        // registration that can be held. And a held answer is indistinguishable from silence here — the
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

        // A lifecycle name carries nothing to read ("Do not rely on their object
        // contents", same Guide page), so the relay fires on the post itself.
        let launched = DistributedPayloadRelay(signal: { [weak self] in self?.onNeighbourLaunched?() })
        DistributedNotificationCenter.default().addObserver(
            launched,
            selector: #selector(DistributedPayloadRelay.payloadArrived(_:)),
            name: Notification.Name(Self.launchedName),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        launchRelay = launched

        // The workspace edge, not BetterDisplay's own `.terminated`: that one is
        // posted "during orderly shutdown" only (same Guide page), and a crash is
        // just as much an end to what the last answer said.
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == BetterDisplayOSDSource.bundleID else { return }
            MainActor.assumeIsolated { self?.onNeighbourTerminated?() }
        }
    }
}
