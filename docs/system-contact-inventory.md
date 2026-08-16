# System-contact inventory

> Every place Crema touches a resource that can die underneath it, enumerated in
> five classes: live physical-world resources, parity that holds only by
> coincidence, restoration scopes, timeouts, and the blast radius of each
> protection. About 90 enumerated items — the section headers below carry the source audit's own claimed counts (summing to ~105), which overcount their own tables; the headers are kept as provenance, the tables are the truth. The audit that produced it labelled this section a
> **checklist for future review** — that is still what it is, and it is published
> because it is the map you want in hand before changing anything on the fragile
> border.
>
> **Dated, and that is load-bearing: the statuses below are from 2026-07-18**,
> except those carrying a **2026-08-15** stamp, which were read back against the
> code on that date — the volume listeners, the tap's port, the adapter↔JXA
> promotion, both one-shot child processes, the brightness cadence, the wake
> edges, the suppressor's reads and the ghost discard, all of which had been fixed
> without this file being told; the CoreBrightness row, split by the same pass into
> the half that is closed and the half that is now a declared gap; and the
> neighbour's two distributed registrations, added.
> PROTECTED / SILENTLY-FATAL was true of the `dev` branch on the original day, and a
> good part of what was SILENTLY-FATAL has since been fixed (per-domain
> suspension, the fourth reinstall trigger, per-operation keyboard ID, the child
> process deadline, the settle tail from init). Re-verify an item against the
> code before trusting its status; a stale "PROTECTED" is exactly the kind of
> sentence this project treats as a doc bug. What does not go stale is the
> enumeration itself — the list of things that can die.
>
> Provenance: section D of the bug-class audit of 2026-07-18 (5 auditors, 11
> adversarial verifiers, 5 completeness critics; report only, no fixes applied).
> The report itself has since been retired; this inventory is what survived of
> it. The `A1…A9`, `B1…B3` and `§C` markers
> are its own finding IDs, kept as provenance; the findings that mattered were
> fixed and now live as anchors in [DECISIONS.md](https://github.com/colatte/crema/blob/main/docs/DECISIONS.md).
> The `S…`, `MG…`, `P…` and `G2` markers are contract ids and resolve in
> [CONTRACTS.md](https://github.com/colatte/crema/blob/main/docs/CONTRACTS.md).

## D1 · Class 1 — live resources of the physical world (23 items + 6 from the critic)

| Resource | Status |
|---|---|
| dlopen + DisplayServices symbols; displayID per operation | PROTECTED (J2 fix complete) |
| dlopen + class + **CoreBrightness client instance + keyboardID** | **Split, re-verified 2026-08-15.** The keyboardID half is PROTECTED: enumerated per operation (`copyKeyboardBacklightIDs` + `isKeyboardBuiltIn:`), never frozen at init, and `isAvailable` asks the provider on every call. The client INSTANCE half stands — resolved once in `CoreBrightnessKeyboardBridge.init`, re-created by no wake or session edge, so a connection that dies takes the backlight HUD with it until relaunch. Registered as a deliberate gap ([KNOWN-GAPS.md](https://github.com/colatte/crema/blob/main/docs/KNOWN-GAPS.md)) → A7 |
| Display ID (brightness write) | PROTECTED |
| Audio device for the volume/mute write (per operation) | PROTECTED |
| Volume + mute listeners (device switch re-subscribes) | **PROTECTED, re-verified 2026-08-15** (was: a coreaudiod restart is not covered → A9). `CoreAudioVolumeSource` observes `kAudioHardwarePropertyServiceRestarted` — the one property whose purpose is to say every registration is gone — and `installServiceRestartListener` re-adds ITSELF before the device listeners, or it would survive exactly one restart and be deaf to the second. It also removes the previous block before re-adding, so recovery no longer depends on the header's premise that the reset took that listener with it. Silent by design: recovery is not a change the user made |
| observedDevice (cache for routing the listeners) | PROTECTED |
| Event tap CFMachPort + runLoopSource | **PROTECTED, re-verified 2026-08-15** (was: invalidated without reinstall → A8). `healTapLocked` splits the two failure modes — an invalidated port is uninstalled and reinstalled from scratch, since no `setEnabled` revives one, and a valid-but-disabled port is re-enabled keeping its consumer wiring. Reached from the health poll and from the four preventive-reinstall edges, every mutation on the tap's own thread |
| The tap's consumer | PROTECTED (survives teardown/reinstall) |
| Streaming Perl subprocess (EOF → finish → re-select, new process) | PROTECTED |
| **adapter ← JXA preemption** | **PROTECTED, re-verified 2026-08-15** (was SILENTLY-FATAL → A4). While a lower-priority source is active, `ChainedNowPlayingSource.startPromotionProbe` polls the preferred candidate on an interval and `armPromotion` arms the cutover for the selection it was started under; the cutover lands at a quiet boundary rather than mid-track, and a source that has emitted nothing since selection is stopped so it cannot wait forever for a boundary it will never reach |
| One-shot Perl probe (no timeout) | **PROTECTED, re-verified 2026-08-15** (was SILENTLY-FATAL → A6). Every one-shot child goes through `runChildProcess` (`ChildProcessDeadline`): a pure single-resume race over `SleepClock`, and on expiry the child is `terminate()`d escalating to SIGKILL and abandoned, never awaited |
| One-shot osascript (read/probe/commands; AppleEvent ~1–2 min) | **PROTECTED, re-verified 2026-08-15** (was SILENTLY-FATAL, bounded → A6). Same `runChildProcess` deadline — 5 s on the interactive commands, where the user re-taps long before — so the AppleEvent's own ~1–2 min ceiling is no longer the only bound |
| The JXA pollTask (never finishes on its own) | contributes to A4 |
| Lock observers (edge → authoritative re-read) | PROTECTED |
| didChangeScreenParameters observer → updateScreens | PROTECTED |
| Display UUID as a key (fresh on every describeAll) | PROTECTED |
| NSEvent monitors for hover / for clicks | PROTECTED (closed cycle) |
| One NSPanel per display (rebuilt by UUID/geometry) | PROTECTED |
| Accessibility permission (re-read on every use, 2 s poll) | PROTECTED |
| Long-lived tasks/streams/continuations | PROTECTED (with the caveat about the brightness sources below) |
| Sparkle / SMAppService | PROTECTED (no live resource held) |
| Volume read-modify-write × a device switch | narrow race → A1 map |
| _From the critic:_ **brightness sources: the isAvailable guard at init, so the pollTask may never be born** | **PROTECTED, re-verified 2026-08-15** (was → A7, aggravating). `PolledBrightnessSource.startPollingIfAvailable` runs at launch AND at the first key the channel sees, so a channel that answered nothing at a cold boot arms its cadence on the evidence that it exists rather than staying dead for the session. Deliberately not a retry timer: hardware with no backlight at all is still never polled |
| _From the critic:_ the one-shot Perl command channel (not enumerated) | LOUDLY-FATAL (visible throw) |
| _From the critic:_ no sleep/wake observer at all | **PARTLY CLOSED, re-verified 2026-08-15.** `AppCore.wireWakeReinstall` reinstalls the media-key tap preventively on `screensDidWake` and `didWake` — with unlock and `didChangeScreenParameters`, the four physical edges — because a tap goes deaf while `isValid`/`isEnabled` keep answering healthy. The volume side is covered by the HAL's own restart property instead of a wake edge. What no edge covers is the keyboard-backlight client (see the CoreBrightness row) |
| _From the critic:_ the adapter's Pipe fds under respawn (flapping) | low confidence; check under long flapping |
| _Added 2026-08-01:_ desktop picture file (`NSWorkspace.desktopImageURL` for `NSScreen.main`, behind `DesktopPictureSource`) | PROTECTED (nil is an answer — the Settings tiles draw their own desk; the border is asked on every backdrop, so a wallpaper just changed is a new URL, and the bounded thumbnail decode is cached per URL with failure remembered) |
| _Added 2026-08-01:_ Low Power Mode (`ProcessInfo.isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChange` observer) | PROTECTED (edge triggers an authoritative re-read, never a flip — the system posts it for any power-source change; seeded synchronously at init, since a Mac launched already in Low Power posts nothing; observer removed and stream finished in deinit) |
| _Added 2026-08-07, ~~RETIRED~~ 2026-08-08:_ **SkyLight raised space** | GONE — the app dlopens nothing and holds no private symbol. The five calls (`SLSMainConnectionID`, `SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel`, `SLSShowSpaces`, `SLSSpaceAddWindowsAndRemoveFromSpaces`) left with the surface that used them (docs/DECISIONS.md: the-lock-screen-was-built-and-taken-out). The row stays as the record that the app once had exactly one private window API and now has none, and that the degradation shape was the right one: every lookup checked, nil meaning the feature is not offered rather than a crash |
| _Added 2026-08-07:_ the lock surface's NSPanel (screen-sized, `canBecomeVisibleWithoutLogin`) | PROTECTED (built on the lock edge, closed on unlock and in `deinit`; re-framed on `didChangeScreenParameters` before the space is re-asserted, since a topology change can move the main screen under a window sized to the old one) |
| _Added 2026-08-07:_ **distributed notification DELIVERY for the lock edges** (`com.apple.screenIsLocked`/`Unlocked`) | PROTECTED, and it was not before. Every block-based registration defaults to `NSNotificationSuspensionBehaviorCoalesce` (`NSDistributedNotificationCenter.h`), which is HELD while the centre is suspended — and AppKit suspends it on its own "when the application is not active". Crema is an LSUIElement accessory: never active, and certainly not at the instant the screen locks. Now registered with `.deliverImmediately`, the documented opt-out. The settle re-reads and the periodic tail are unchanged; they cover distnoted being best-effort even while it IS delivering |
| _Added 2026-08-07, ~~RETIRED~~ 2026-08-08:_ **MusicBrainz + the Cover Art Archive** | GONE — the app makes no such request any more. The contact existed to fill a 300 pt expanded tile; that state was removed with the rest of the lock surface, and the largest artwork slots left — the desktop skins' — are thumbnails the player's own bytes already oversupply (docs/DECISIONS.md: the-lock-screen-was-built-and-taken-out). Kept as a row because the guest-relationship discipline it recorded is the reusable part: MusicBrainz publishes 1 request per second per IP and asks for a descriptive User-Agent, and `RequestPacer` reserved its slot BEFORE any await because actors are reentrant and a pacer that awaits first paces nothing. Whoever adds the next rate-limited guest inherits both |
| _Added 2026-08-08, ~~RETIRED~~ the same day:_ **the wall clock, for the lock surface's own time** | GONE — the contact left with the surface that needed it. The lock widget no longer paints a ground (docs/DECISIONS.md: the-lock-surface-is-a-card), so it no longer covers the system's clock, so it draws no clock and reads no wall time. The row is kept rather than deleted because the measurement behind it is the kind someone re-does: `Task.sleep` waits on an absolute `ContinuousClock` deadline, which counts THROUGH system suspension, so a missed boundary collapses into one wake carrying the current minute rather than a burst — verified over the shield with a dispatch-timer control that delivered the same count, which is what ruled out a scheduler-specific fault, and reproduced with SIGSTOP across five boundaries. Whoever adds a clock back to any surface inherits that and owes no observer |

| _Added 2026-08-15:_ **distributed notification DELIVERY for the neighbour's two channels** (`pro.betterdisplay.BetterDisplay.osd` and `…​.response`) | PROTECTED, and it was not before — the same defect as the lock edges above, two rows up, found by mirroring that fix outward. Both were block-based registrations, so both defaulted to `NSNotificationSuspensionBehaviorCoalesce`, which is held while the centre is suspended; AppKit suspends it whenever the app is not active, and an LSUIElement accessory essentially never is. Both now register by selector with `.deliverImmediately` (a shared `DistributedPayloadRelay`, since the suspension behaviour is only on the selector API). The response side also carried an asymmetry of our own making: the REQUEST already went out with `deliverImmediately: true`, while a held ANSWER is indistinguishable from silence to the caller — the deadline fires, the drag reports a failed apply, and the bar rolls back over a write that actually landed. Not a proof of delivery: whether the neighbour's post arrives at all remains best-effort, which is why the OSD side stays inert-by-design when nothing comes |

## D2 · Class 2 — parity by coincidence (27 items + 5 from the critic)

**By construction (proven)**: MediaKeyStepper identical on all 3 channels; mute
only on volume, with verify by exact equality; MG7 slider/filled in one place;
MG1 empty↔visible freeze now on all 3 styles (Notch fixed); MG5 Reduce Motion
gated in `SurfaceAnimation` (geometry); shared StyleContent; the en↔pt-BR catalog
with no orphans and no divergent terms (P1/P2 fixed); post-failover command
routing (`activeCommandChannel`); all 3 engage paths converge on
`applyEngagement → setEngaged`; card-only hover and notch-only slit inset by
design.

**Coincidence-fine-today (real asymmetry, same result)**: an event-driven source
(volume) vs. sampled + poke (the brightnesses); boundary refresh through two
mechanisms (`boundaryRefreshHUD` with no changed-guard vs. the gate with
`!changed` → a cosmetic double-emit of volume); the volume HUD delayed under
suppression (the router's comment only holds in OFF mode); boundary + observe:
brightness shows a HUD, volume does not (the native one covers it);
`ClassicStyle.windowFrame` expanded-only (G2); the simplified demo sources;
adapter vs. JXA capabilities (the 1 Hz ticker only on the adapter).

**Asymmetries that bite**: continuous vs. quantized verify → **A2**; a frozen
keyboardID vs. a per-operation display → **A7**; the slider not unmuting while
the key does → **A3** (from the critic); the Notch's content crossfade outside
the Reduce Motion house (§C).

## D3 · Class 3 — restoration scopes (14 cycles)

RESTORES-FULLY (with proof): lock/unlock (physical tap + consumer + generation +
a live guard via `isSuppressionSafe`); auto-disengage → manual re-engage (the
same `setEngaged`); revoke → re-grant of Accessibility (the consumer is preserved
across teardown, so suppression auto-resumes); panel rebuild (born showing the
current state; hover re-sampled); quit (the tap dies with the process — every
exit path restores the native OSD); volume/screen under sleep/wake (per
operation); demo enter/exit (relaunch-only, no partial state).

DELTAS: **the keyboard under sleep/wake** → A7, the one still open (its reasoning,
palliative and reopening gate are in
[KNOWN-GAPS.md](https://github.com/colatte/crema/blob/main/docs/KNOWN-GAPS.md));
S4 / login-item snapshot-once (B3); MergedSystemHUDSource with no re-subscription
(§C); the narrow `commandsAvailable` heal (B2).

**Closed since, re-verified 2026-08-15**: the preferred source after a failover
(A4) — the promotion probe arms a cutover that lands at a quiet boundary — and
ghost discard, which is no longer quit-only (B1): `fireActiveSourceEnded` fires
whenever the active source's stream ends, whether its process died or a promotion
broke the loop, so the consumer drops the stale snapshot and the next selected
source rebuilds the state from its own.

## D4 · Class 4 — timeouts (24 items + 4 from the critic)

REAL-DEADLINE (with proof): the write's withDeadline (detached +
single-resume SingleResumeRace, since unified at the Sources root — all 4 interleavings traced); the Coordinator's
timers (revert/linger/hover — cancel + stale-fire guard correct under a burst);
the tap poll and the 1 Hz ticker (a generation invalidates stale ticks); the
adapter's stream (EOF finishes, teardown does not wait); the clickable region's
tighten; artwork decode.

NO-DEADLINE: the Coordinator's fire-and-forget actuators (off-main by
SE-0338 — leaks a suspended Task, does not freeze; low impact); the brightness
polls (off-main, isolated degradation); CGSessionCopyCurrentDictionary
(MainActor, a fast local query); _from the critic:_ SMAppService,
AXIsProcessTrustedWithOptions, dlopen at boot (§C). BOUNDARY: Sparkle
(Release-only, the framework's own timeouts).

**Closed since, re-verified 2026-08-15**: the suppressor's reads on the MainActor
(A5) go through `readWithDeadline`, and the one-shot child processes (A6) through
`runChildProcess`. Both are single-resume races over `SleepClock`, and both put the
blocking half on `DispatchQueue.global()` rather than the cooperative pool — that
pool has fixed width and does not overcommit, so blocked orphans there would
eventually strangle the deadline that is supposed to free them.

**Weak proof corrected**: the @MainActor permission poll is a COOPERATIVE
deadline (synchronous IPC to tccd with no deadline), not a real one — "it is
fast" is a premise, not a proof.

## D5 · Class 5 — the blast radius of the protections (17 items)

PROPORTIONATE (with proof): a boundary no-op does not punish; the generation
guard (S9); passThroughUnavailable (an absent capability is a logged no-op);
failover on a malformed line (hides 1 tick, self-heals); MediaSourceFilter
(documented radius + toggle); KeyOriginBrightnessGate (S3 closed; silences only
the sensor); lock-aware suspension (**never touches the pref** — proven; a total
radius is the correct design precisely because the app draws nothing over the
lock shield — the opt-in now-playing widget that did was removed whole
(docs/DECISIONS.md: the-lock-screen-was-built-and-taken-out) — and suspending
suppression is what leaves the KEYS with native feedback); degrading without
Accessibility (only capture falls; self-heals on grant); an orphaned style and a
slitless notch resolve at runtime **without rewriting the pref** (proven by a
grep for setStyle); LoginItem/Sparkle with no persistence on failure; **the only
non-user pref write in the codebase = J5** (full grep).

DISPROPORTIONATE: **global auto-disengage + a persisted pref** → A1 (full map).
LATENT: re-enabling the tap with no backoff under non-lock secure input (§C);
the brightness sources' degradation decided at init (→ A7); `commandsAvailable`
with a conditional heal (B2).
