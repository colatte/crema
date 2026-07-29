import Testing
@testable import Crema

/// The write-health axis (docs/DECISIONS.md: write-health-axis) exists to catch
/// one thing the read-only probe cannot: a channel that reads fine and writes
/// dead. Its whole value depends on counting *only* that. Two ways it drifted:
/// a failed READ billed to the write, and a no-op crediting it.
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
}
