# System-contact inventory

> Every place Crema touches a resource that can die underneath it, enumerated in
> five classes: live physical-world resources, parity that holds only by
> coincidence, restoration scopes, timeouts, and the blast radius of each
> protection. About 105 items. The audit that produced it labelled this section a
> **checklist for future review** — that is still what it is, and it is published
> because it is the map you want in hand before changing anything on the fragile
> border.
>
> **Dated, and that is load-bearing: the statuses below are from 2026-07-18.**
> PROTECTED / SILENTLY-FATAL was true of the `dev` branch on that day, and a
> good part of what was SILENTLY-FATAL has since been fixed (per-domain
> suspension, the fourth reinstall trigger, per-operation keyboard ID, the child
> process deadline, the settle tail from init). Re-verify an item against the
> code before trusting its status; a stale "PROTECTED" is exactly the kind of
> sentence this project treats as a doc bug. What does not go stale is the
> enumeration itself — the list of things that can die.
>
> Provenance: section D of the bug-class audit of 2026-07-18 (5 auditors, 11
> adversarial verifiers, 5 completeness critics; report only, no fixes applied),
> which lives with the author's working docs in `docs/internal/` (gitignored).
> The `A1…A9`, `B1…B3`, `S…`, `MG…`, `P…`, `G2` and `§C` markers are that audit's
> own finding IDs, kept as provenance; the findings that mattered were fixed and
> now live as anchors in [DECISIONS.md](https://github.com/colatte/crema/blob/main/docs/DECISIONS.md).

## D1 · Class 1 — live resources of the physical world (23 items + 6 from the critic)

| Resource | Status |
|---|---|
| dlopen + DisplayServices symbols; displayID per operation | PROTECTED (J2 fix complete) |
| dlopen + class + **CoreBrightness client instance + keyboardID** | **SILENTLY-FATAL** → A7 |
| Display ID (brightness write) | PROTECTED |
| Audio device for the volume/mute write (per operation) | PROTECTED |
| Volume + mute listeners (device switch re-subscribes) | PROTECTED for device switch; **a coreaudiod restart is not covered** → A9 |
| observedDevice (cache for routing the listeners) | PROTECTED |
| Event tap CFMachPort + runLoopSource | J1 health-check fine for *disabled*; **invalidated without reinstall** → A8 |
| The tap's consumer | PROTECTED (survives teardown/reinstall) |
| Streaming Perl subprocess (EOF → finish → re-select, new process) | PROTECTED |
| **adapter ← JXA preemption** | **SILENTLY-FATAL** → A4 |
| One-shot Perl probe (no timeout) | SILENTLY-FATAL → A6 |
| One-shot osascript (read/probe/commands; AppleEvent ~1–2 min) | SILENTLY-FATAL (bounded) → A6 |
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
| _From the critic:_ **brightness sources: the isAvailable guard at init, so the pollTask may never be born** | → A7 (aggravating) |
| _From the critic:_ the one-shot Perl command channel (not enumerated) | LOUDLY-FATAL (visible throw) |
| _From the critic:_ no sleep/wake observer at all | systemic hole behind A7/A9 |
| _From the critic:_ the adapter's Pipe fds under respawn (flapping) | low confidence; check under long flapping |

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

DELTAS: **the keyboard under sleep/wake** → A7; **the preferred source after a
failover** → A4; S4 / login-item snapshot-once (B3); MergedSystemHUDSource with
no re-subscription (§C); the narrow `commandsAvailable` heal (B2); **ghost
discard is quit-only** (B1).

## D4 · Class 4 — timeouts (24 items + 4 from the critic)

REAL-DEADLINE (with proof): the write's withDeadline (detached +
single-resume DeadlineRace — all 4 interleavings traced); the Coordinator's
timers (revert/linger/hover — cancel + stale-fire guard correct under a burst);
the tap poll and the 1 Hz ticker (a generation invalidates stale ticks); the
adapter's stream (EOF finishes, teardown does not wait); the clickable region's
tighten; artwork decode.

NO-DEADLINE: **the suppressor's reads on the MainActor** → A5; **child-process
probes/commands** → A6; the Coordinator's fire-and-forget actuators (off-main by
SE-0338 — leaks a suspended Task, does not freeze; low impact); the brightness
polls (off-main, isolated degradation); CGSessionCopyCurrentDictionary
(MainActor, a fast local query); _from the critic:_ SMAppService,
AXIsProcessTrustedWithOptions, dlopen at boot (§C). BOUNDARY: Sparkle
(Release-only, the framework's own timeouts).

**Weak proof corrected**: the @MainActor permission poll is a COOPERATIVE
deadline (synchronous IPC to tccd with no deadline), not a real one — "it is
fast" is a premise, not a proof.

## D5 · Class 5 — the blast radius of the protections (17 items)

PROPORTIONATE (with proof): a boundary no-op does not punish; the generation
guard (S9); passThroughUnavailable (an absent capability is a logged no-op);
failover on a malformed line (hides 1 tick, self-heals); MediaSourceFilter
(documented radius + toggle); KeyOriginBrightnessGate (S3 closed; silences only
the sensor); lock-aware suspension (**never touches the pref** — proven; a total
radius is the correct design given the lockscreen NO-GO); degrading without
Accessibility (only capture falls; self-heals on grant); an orphaned style and a
slitless notch resolve at runtime **without rewriting the pref** (proven by a
grep for setStyle); LoginItem/Sparkle with no persistence on failure; **the only
non-user pref write in the codebase = J5** (full grep).

DISPROPORTIONATE: **global auto-disengage + a persisted pref** → A1 (full map).
LATENT: re-enabling the tap with no backoff under non-lock secure input (§C);
the brightness sources' degradation decided at init (→ A7); `commandsAvailable`
with a conditional heal (B2).
