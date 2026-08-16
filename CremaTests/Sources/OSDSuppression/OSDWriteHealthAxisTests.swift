import Testing
@testable import Crema

/// The write-health axis (docs/DECISIONS.md: write-health-axis) exists to catch
/// one thing the read-only probe cannot: a channel that reads fine and writes
/// dead. Its whole value depends on counting *only* that, and on tripping at
/// exactly the count it claims. Two ways it drifted: a failed READ billed to the
/// write, and a no-op crediting it.
@MainActor
struct OSDWriteHealthAxisTests {
    private static let threshold = MediaKeyInterceptionOSDSuppressor.writeHealthEscalationThreshold

    /// Drives one write-health episode and lets the probe recover the domain, so
    /// the next press starts from an engaged domain — the loop the axis is
    /// designed around, and the only way to accumulate episodes.
    private func failThenRecover(_ h: OSDSuppressorHarness, key: MediaKey, domain: OSDSuppressionDomain) async {
        h.keys.press(key)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(domain) })
        await h.clock.waitForSleep()
        h.clock.advance()
        #expect(await eventually { !h.suppressor.suspendedDomains.contains(domain) })
    }

    /// The boundary the axis claims, owned by the axis's own file: episodes below
    /// the threshold stay silent, and the threshold-th is what surfaces. Not a
    /// hole being closed — a mutant that escalates one episode early already dies
    /// in OSDSuppressionUnlockRegressionTests, but only as a side effect of its
    /// no-churn count: escalating below the count `reengage` latches on lets the
    /// probe's optimistic re-engage drop the warning again, so the change counter
    /// runs past one. A boundary asserted by accident somewhere else moves the day
    /// somebody rewrites that assertion for its own reasons.
    @Test func oneEpisodeShortOfTheThresholdStaysSilentAndTheNextSurfaces() async {
        let h = OSDSuppressorHarness()
        h.screen.writeIsDead = true   // accepted by the actuator, never moves
        h.suppressor.setEngaged(true)

        for _ in 0..<(Self.threshold - 1) {
            await failThenRecover(h, key: .screenBrightnessUp, domain: .screenBrightness)
        }
        await settle()
        #expect(h.suppressor.longSuspendedDomains.isEmpty)
        #expect(h.suspensionChanges == 0)   // the menu was never told

        await failThenRecover(h, key: .screenBrightnessUp, domain: .screenBrightness)
        #expect(await eventually { h.suppressor.longSuspendedDomains.contains(.screenBrightness) })
        // Told once, and the probe's re-engage across the last episode did not
        // take it back: at the threshold the warning outlives a read-only recovery.
        #expect(h.suspensionChanges == 1)
    }

    /// A nil read-back is a READ failure. It used to reach the axis through
    /// `OSDApplyVerification.verified`, which answers false for a nil `after`, so
    /// an output blinking out between write and verify looked exactly like a dead
    /// write — and after five of them the menu accused a channel whose write had
    /// landed every single time.
    @Test func aNilReadBackNeverEscalatesAsADeadWrite() async {
        let h = OSDSuppressorHarness()
        h.screen.readBackReturnsNilOnce = true
        h.suppressor.setEngaged(true)

        for _ in 0..<(Self.threshold + 2) {
            await failThenRecover(h, key: .screenBrightnessUp, domain: .screenBrightness)
        }

        #expect(h.suppressor.longSuspendedDomains.isEmpty)
        #expect(h.suspensionChanges == 0)
        // The writes did land — the reads are what failed.
        #expect(h.screen.applied.count >= Self.threshold)
    }

    /// A no-op wrote nothing, so it proves nothing. Sharing the verified branch
    /// let one press on an output that had just lost its volume control clear
    /// five episodes of accumulated evidence and drop the menu warning; the next
    /// time the device came back with the same dead write, the user had to earn
    /// the warning all over again.
    @Test func aNoOpNeverClearsAWriteDeadChannelsMenuWarning() async {
        let h = OSDSuppressorHarness()
        h.volume.writeIsDead = true   // accepted by the actuator, never moves
        h.suppressor.setEngaged(true)

        for _ in 0..<Self.threshold {
            await failThenRecover(h, key: .volumeUp, domain: .volume)
        }
        #expect(h.suppressor.longSuspendedDomains.contains(.volume))

        // The output loses its volume control entirely: the apply is a no-op.
        h.volume.available = false
        h.keys.press(.volumeUp)
        await settle()

        #expect(h.suppressor.longSuspendedDomains.contains(.volume))
    }

    @Test func retryInsideTheEscalatingSuspensionWindowActuallyClearsTheWarning() async {
        // The window the menu button used to miss. A read-alive/write-dead channel
        // suspends AND escalates in the same step on its fifth flap, so for as long
        // as the suspension lasts the domain is in both states at once — and the
        // retry reached only the kick branch, the probe re-engaged on the read, and
        // `reengage` found the write-health count still standing and kept the warning
        // up. The user clicked and the menu did not change.
        let h = OSDSuppressorHarness()
        h.screen.writeIsDead = true
        h.suppressor.setEngaged(true)

        // Flap until the escalation lands, leaving the domain suspended at that step.
        for _ in 0..<(OSDTest.escalation * 4) {
            h.keys.press(.screenBrightnessUp)
            _ = await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) }
            _ = await eventually {
                h.clock.advance()
                return !h.suppressor.suspendedDomains.contains(.screenBrightness)
            }
        }
        #expect(h.suppressor.longSuspendedDomains.contains(.screenBrightness))

        // Land IN the window, which is the whole subject: one more press and no
        // clock advance, so the domain is suspended AND escalated when the click
        // arrives. The loop above always ends re-engaged, which is the other branch
        // — a retry there was never the broken one.
        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })

        h.suppressor.retrySuspendedNow()

        // Only the clock from here — NO key press. A successful apply clears the
        // write-health axis on its own (`confirmWriteHealthy`, the passive cleaner),
        // so a probe loop that pressed would drop the warning with or without the
        // click and prove nothing about the button. What is asserted is the click's
        // own effect: the count is gone, so the probe's re-engage finds nothing
        // standing and the menu clears.
        #expect(await eventually {
            h.clock.advance()
            return h.suppressor.longSuspendedDomains.isEmpty
        }, "the retry left the warning up: the click did not consent to re-testing the write")
    }

    @Test func retryOnAStillDeadProbeEscalatedChannelKeepsTheWarning() async {
        // The other half, and the one that makes the obvious fix wrong: turning the
        // `else if` into a second `if` would let the retry drop the menu warning of a
        // domain escalated by the PROBE axis — still suspended, still dead — and that
        // probe's own `longSuspended` flag never raises it a second time, so the
        // channel would go dark permanently. A click must not be able to silence a
        // channel that is still broken.
        let h = OSDSuppressorHarness()
        h.screen.value = nil            // the read itself is dead: the probe axis
        h.suppressor.setEngaged(true)

        for _ in 0..<(OSDTest.escalation + 2) {
            h.keys.press(.screenBrightnessUp)
            _ = await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) }
            _ = await eventually { h.clock.advance(); return true }
        }
        _ = await eventually {
            h.clock.advance()
            return h.suppressor.longSuspendedDomains.contains(.screenBrightness)
        }
        #expect(h.suppressor.longSuspendedDomains.contains(.screenBrightness))

        h.suppressor.retrySuspendedNow()   // the channel is STILL dead

        await settle()
        // Each advance waits for the probe to park first: an advance before the
        // park is a no-op (TestSleepClock resumes nobody), and five no-ops would
        // pass this negative without the probe→re-engage cycle ever running. The
        // wait fails loudly on a blown deadline instead of hanging the suite.
        for _ in 0..<5 {
            await h.clock.waitForSleep()
            h.clock.advance()
        }
        #expect(h.suppressor.longSuspendedDomains.contains(.screenBrightness),
                "a click silenced a channel that is still broken")
    }
}
