import Foundation
import Testing
@testable import Crema

/// The actuator that sends a drag back to the app whose bar it was.
struct BetterDisplayScreenBrightnessControllerTests {

    private final class SpyChannel: BetterDisplayCommanding, @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [(value: Double, displayID: Int)] = []
        var written: [(value: Double, displayID: Int)] { lock.withLock { calls } }
        var failure: Error?

        func setBrightness(_ value: Double, displayID: Int) async throws {
            lock.withLock { calls.append((value, displayID)) }
            if let failure { throw failure }
        }
    }

    private let external = DisplayUUID(rawValue: "UUID-EXT")

    @Test func theBuiltInScreenIsAddressedByItsOwnID() async throws {
        // `display == nil` is the domain's built-in; the neighbour needs it
        // spelled out as a number.
        let channel = SpyChannel()
        let controller = BetterDisplayScreenBrightnessController(
            channel: channel,
            displayID: { $0 == nil ? 1 : 2 }
        )

        try await controller.setBrightness(0.4, on: nil)

        // #expect does not halt the test, so the subscript needs its own guard —
        // a trap here would kill the host and every in-flight sibling.
        let first = try #require(channel.written.first)
        #expect(channel.written.count == 1)
        #expect(first.displayID == 1)
        #expect(first.value == 0.4)
    }

    @Test func anExternalScreenIsAddressedByItsOwn() async throws {
        let channel = SpyChannel()
        let controller = BetterDisplayScreenBrightnessController(
            channel: channel,
            displayID: { [external] display in display == external ? 7 : nil }
        )

        try await controller.setBrightness(0.9, on: external)

        let first = try #require(channel.written.first)
        #expect(first.displayID == 7)
    }

    @Test func aDisplayThatNoLongerResolvesIsNotWrittenTo() async {
        // Unplugged between the HUD and the drag: guessing another display would
        // dim the wrong screen.
        let channel = SpyChannel()
        let controller = BetterDisplayScreenBrightnessController(channel: channel, displayID: { _ in nil })

        await #expect(throws: BrightnessCommandError.unavailable) {
            try await controller.setBrightness(0.5, on: DisplayUUID(rawValue: "GONE"))
        }
        #expect(channel.written.isEmpty)
    }

    /// A channel that parks its first call until the test lets go, so a second
    /// write can arrive while the first is genuinely in flight.
    private final class ParkingChannel: BetterDisplayCommanding, @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [Double] = []
        private var release: CheckedContinuation<Void, Never>?
        private var parked = false

        var written: [Double] { lock.withLock { calls } }
        var callCount: Int { lock.withLock { calls.count } }

        func setBrightness(_ value: Double, displayID: Int) async throws {
            let shouldPark = lock.withLock {
                calls.append(value)
                let first = !parked
                parked = true
                return first
            }
            guard shouldPark else { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.withLock { release = continuation }
            }
        }

        func letGo() {
            let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                defer { release = nil }
                return release
            }
            continuation?.resume()
        }
    }

    @Test func writesCoalesceToTheLatestWithOnlyOneInFlight() async {
        // A drag fires on every frame and each write here is a round-trip to
        // another process. Without coalescing a two-second drag puts dozens in
        // the air at once, resolving out of order — the display lands on
        // whichever answered last instead of where the finger stopped.
        let channel = ParkingChannel()
        let controller = BetterDisplayScreenBrightnessController(channel: channel, displayID: { _ in 1 })

        let first = Task { try? await controller.setBrightness(0.2, on: nil) }
        #expect(await eventuallyOffActor { channel.callCount == 1 })

        // Three more frames of the same gesture, while the first is in flight.
        for value in [0.4, 0.6, 0.8] {
            try? await controller.setBrightness(value, on: nil)
        }
        #expect(channel.callCount == 1)      // none of them reached the channel

        channel.letGo()
        await first.value

        #expect(await eventuallyOffActor { channel.written == [0.2, 0.8] })
    }

    @Test func theNeighboursRefusalTravelsBackToTheCaller() async throws {
        // A failed apply must read as failure so the drag reports it, exactly
        // like the system actuator's own failures. The channel's error travels
        // wrapped, carrying the frame the failed write held — here the drive's
        // own, the only one there was — so the fallback always has a level to
        // honour.
        let channel = SpyChannel()
        channel.failure = BetterDisplayCommandChannel.CommandError.unanswered
        let controller = BetterDisplayScreenBrightnessController(channel: channel, displayID: { _ in 1 })

        do {
            _ = try await controller.setBrightness(0.5, on: nil)
            Issue.record("the channel refused; the call must throw")
        } catch let failure as BrightnessWriteFailure {
            #expect(failure.underlying as? BetterDisplayCommandChannel.CommandError == .unanswered)
            let orphan = try #require(failure.orphan)
            #expect(orphan.value == 0.5)
            #expect(orphan.display == nil)
        }
    }

    @Test func aFrameStillQueuedWhenTheChannelFailsLeavesWithTheError() async throws {
        // The frame that coalesces echoes at once, having written nothing — a
        // promise the driver normally keeps by draining it. When the driver's
        // write fails instead, no driver is left: the frame must leave WITH the
        // error, so the caller's fallback can write the finger's newest level
        // (and the display it was aimed at) instead of the drive's stale argument.
        let channel = ReentrantChannel()
        channel.firstWriteFailure = BetterDisplayCommandChannel.CommandError.unanswered
        let controller = BetterDisplayScreenBrightnessController(
            channel: channel,
            displayID: { [external] display in display == external ? 7 : 1 }
        )
        let coalesced = CoalescedReturns()
        channel.duringFirstWrite = { [weak controller, external] in
            guard let controller else { return }
            try await coalesced.append(controller.setBrightness(0.9, on: external))
        }

        do {
            _ = try await controller.setBrightness(0.1, on: nil)
            Issue.record("the channel failed; the drive must throw")
        } catch let failure as BrightnessWriteFailure {
            let orphan = try #require(failure.orphan)
            #expect(orphan.value == 0.9)
            #expect(orphan.display == external)
            #expect(failure.underlying as? BetterDisplayCommandChannel.CommandError == .unanswered)
        }
        // The echo already promised 0.9, which is exactly why it may not die in
        // the queue; and only the failed attempt ever reached the wire.
        #expect(coalesced.values == [0.9])
        #expect(channel.written == [0.1])
    }

    @Test func aFailureWithTheQueueEmptyCarriesTheFrameItWasWriting() async throws {
        // The narrower path of the same class: the drain dequeues the newest
        // frame, leaving the queue EMPTY, and that very write fails. The failed
        // frame queued after the drive's argument, so it is newer — an error
        // carrying nothing would point the caller's fallback at the argument,
        // a level the finger only passed through.
        let channel = ReentrantChannel()
        channel.secondWriteFailure = BetterDisplayCommandChannel.CommandError.unanswered
        let controller = BetterDisplayScreenBrightnessController(
            channel: channel,
            displayID: { [external] display in display == external ? 7 : 1 }
        )
        let coalesced = CoalescedReturns()
        channel.duringFirstWrite = { [weak controller, external] in
            guard let controller else { return }
            try await coalesced.append(controller.setBrightness(0.5, on: external))
        }

        do {
            _ = try await controller.setBrightness(0.3, on: nil)
            Issue.record("the channel failed; the drive must throw")
        } catch let failure as BrightnessWriteFailure {
            let orphan = try #require(failure.orphan)
            #expect(orphan.value == 0.5)
            #expect(orphan.display == external)
            #expect(failure.underlying as? BetterDisplayCommandChannel.CommandError == .unanswered)
        }
        // 0.3 reached the wire whole; 0.5 is the failed attempt. Its echo had
        // already promised it, which is exactly why it may not vanish with the
        // error.
        #expect(coalesced.values == [0.5])
        #expect(channel.written == [0.3, 0.5])
    }

    @Test func aFrameArrivingAsTheDriveWindsDownIsNeverDropped() async {
        // The exit race: with the drain's "queue is empty" check and the inFlight
        // reset in separate critical sections, a frame slipping between them saw
        // inFlight still true, echoed as coalesced, and was drained by nobody —
        // the gesture's last level died in the queue while both calls reported
        // success. The window is a few instructions wide and sits between two lock
        // acquisitions on the driver's path, so no fake can hook inside it; this
        // pins the invariant by racing a frame against many drives ending, which
        // is deterministic-green on the single-critical-section drain and reached
        // the window probabilistically on the split one.
        for round in 0..<200 {
            let channel = YieldingChannel()
            let racing = BetterDisplayScreenBrightnessController(channel: channel, displayID: { _ in 1 })
            let driver = Task { try? await racing.setBrightness(0.15, on: nil) }
            // Only after 0.15 is on the wire may 0.85 leave: fired earlier it could
            // be legally superseded BY 0.15, and a dropped frame would mean nothing.
            // From here on it is the strictly newest level, racing the drive's exit.
            #expect(await eventuallyOffActor { channel.written.contains(0.15) })
            let late = Task { try? await racing.setBrightness(0.85, on: nil) }
            _ = await driver.value
            _ = await late.value
            // Both calls have returned, so every drain they started has finished;
            // nothing superseded 0.85, so it must be on the wire by now.
            if !channel.written.contains(0.85) {
                Issue.record("round \(round): the newest frame was enqueued, echoed, and never written")
                break
            }
        }
    }

    /// A channel whose write suspends once, widening the interleaving between a
    /// drive winding down and a frame arriving — no wall clock involved.
    private final class YieldingChannel: BetterDisplayCommanding, @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [Double] = []
        var written: [Double] { lock.withLock { calls } }

        func setBrightness(_ value: Double, displayID: Int) async throws {
            await Task.yield()
            lock.withLock { calls.append(value) }
        }
    }

    @Test func theDrivingCallReportsWhatItLastWroteNotWhatItWasAskedFor() async throws {
        // The flick, found on hardware: dragging the bar drawn on the external
        // monitor fast enough makes it jump backwards for an instant before the next
        // frame pulls it forward.
        //
        // The cause is the coalescing telling the truth about the wire and lying
        // about itself. A frame arriving while a write is in flight queues its value
        // and returns AT ONCE, having written nothing. The frame that DRIVES stays
        // inside the drain loop putting every newer value on the wire, and returns
        // last — still holding the argument it was called with, by then several
        // frames behind the finger. The Coordinator builds the confirming echo from
        // that return value, so echoing the argument publishes a stale level over a
        // fresh one.
        //
        // The newer frames arrive from inside the first write, which is when they
        // arrive in life too — and makes the interleaving exact instead of raced.
        let channel = ReentrantChannel()
        let controller = BetterDisplayScreenBrightnessController(
            channel: channel, displayID: { _ in 2 }
        )
        // Collected inside the write and asserted outside it: the expectation macro
        // does not carry the closure's `throws` through its expansion.
        let coalesced = CoalescedReturns()
        channel.duringFirstWrite = { [weak controller] in
            guard let controller else { return }
            try await coalesced.append(controller.setBrightness(0.5, on: nil))
            try await coalesced.append(controller.setBrightness(0.9, on: nil))
        }

        let reported = try await controller.setBrightness(0.1, on: nil)

        // The two that coalesced wrote nothing and returned their own value at once,
        // which is right — they are level with the finger.
        #expect(coalesced.values == [0.5, 0.9])
        // 0.9 went out last. Reporting 0.1 here is the flick.
        #expect(reported == 0.9)
        #expect(channel.written == [0.1, 0.9])
    }

    @Test func aFrameQueuedForAnotherScreenIsWrittenToThatScreen() async throws {
        // Two bars share one actuator, and the coalescing outlives the call that
        // resolved the display: a frame arriving while another screen's write is in
        // flight is put on the wire by THAT write. With the display resolved once
        // per DRIVE instead of travelling with the level, the neighbour is told to
        // dim the screen the finger is not on — in silence, since the bar that asked
        // for it is on the other panel.
        let channel = ReentrantChannel()
        let controller = BetterDisplayScreenBrightnessController(
            channel: channel,
            displayID: { [external] display in display == external ? 7 : 1 }
        )
        let coalesced = CoalescedReturns()
        channel.duringFirstWrite = { [weak controller, external] in
            guard let controller else { return }
            try await coalesced.append(controller.setBrightness(0.9, on: external))
        }

        let reported = try await controller.setBrightness(0.1, on: nil)

        #expect(channel.addressed == [1, 7])
        #expect(channel.written == [0.1, 0.9])
        // 0.9 went out last, but it belongs to the other screen: echoing it here
        // would move this bar to a level nothing ever wrote on this display.
        #expect(reported == 0.1)
        #expect(coalesced.values == [0.9])
    }

    /// The values the coalesced calls returned, collected from inside a write.
    private final class CoalescedReturns: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Double] = []
        var values: [Double] { lock.withLock { stored } }
        func append(_ value: Double) { lock.withLock { stored.append(value) } }
    }

    /// A channel that lets the test run code INSIDE the first write, so newer drag
    /// frames land while that write is in flight — the arrangement the coalescing
    /// exists for, reproduced without a semaphore or a race.
    private final class ReentrantChannel: BetterDisplayCommanding, @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [(value: Double, displayID: Int)] = []
        var written: [Double] { lock.withLock { calls }.map(\.value) }
        /// The screens the levels landed on, in order. Levels alone cannot show a
        /// frame written to the driving call's display instead of its own.
        var addressed: [Int] { lock.withLock { calls }.map(\.displayID) }
        var duringFirstWrite: (@Sendable () async throws -> Void)?
        /// Thrown by the first write AFTER `duringFirstWrite` ran: the shape of a
        /// drive that failed with frames already queued behind it.
        var firstWriteFailure: Error?
        /// Thrown by the second write — the drained frame — with nothing queued
        /// behind it: the shape of a drain failing on a frame that emptied the
        /// queue.
        var secondWriteFailure: Error?

        func setBrightness(_ value: Double, displayID: Int) async throws {
            let ordinal = lock.withLock { () -> Int in
                calls.append((value, displayID))
                return calls.count
            }
            if ordinal == 1 {
                try await duringFirstWrite?()
                if let firstWriteFailure { throw firstWriteFailure }
            }
            if ordinal == 2, let secondWriteFailure { throw secondWriteFailure }
        }
    }
}
