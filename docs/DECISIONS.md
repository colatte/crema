# Design decisions

> Design memory for Crema — the load-bearing decisions behind the fragile parts
> of the system (OSD suppression, the event tap, the now-playing chain,
> concurrency deadlines). Each entry is a stable anchor: a short problem
> statement and the decision that answered it, distilled so a future reader (or
> contributor) understands *why* the code is shaped the way it is before
> changing it. This is not a changelog and not an exhaustive dump — only
> decisions with durable value are recorded. Code comments cite these anchors as
> `(docs/DECISIONS.md: <anchor>)`, but always carry the lesson themselves; the
> anchor is a pointer for depth, never the only copy of the knowledge.

## Jurisprudence — bug classes we ruled on

### J1-tap-zumbi
A `CGEventTap` can be disabled by the system (timeout, user input, secure input)
and go on *existing* while delivering nothing — a live handle wired to a dead
tap, silent.
Decision: a health-check re-enables the tap on every delivered disable event and
polls its state every 2 s, so a silent disable self-heals instead of killing key
capture for the session. (Covers *disabled* and — since the A8 fix — the
*invalidated* port too: both are port state, locally readable, and the
health-check reinstalls on invalidation; the *enabled-but-deaf* death, which
no local read can see, is J7.)

### J2-display-id-stale
A system-resource identifier captured once at init (a `displayID`, a keyboard
backlight ID) goes stale when the hardware topology changes — the frozen ID
addresses a resource that no longer exists.
Decision: resolve the resource **per operation**, never freeze it at init.
Read/write re-resolve the ID each time (the screen-brightness bridge is the
reference; the keyboard bridge, once the latent sibling, was brought to parity
in the v1.2 seal round — both bridges re-resolve per operation, with the
frozen-ID death pinned by each bridge's own test pair).

### J3-deadline-cooperativo
A deadline is only real if the timer that fires it is not strangled by the same
executor the guarded work occupies. A blocking operation raced against a
deadline on the fixed-width cooperative pool piles up orphans, and the deadline —
resuming on that same starved pool — cannot cut in.
Decision: the apply write runs as a detached, single-resume race against a
deadline; blocking sync work that a deadline guards runs on `DispatchQueue.global()`
(see read-deadline-pool-rule), which grows under blocking, so a stuck orphan
never steals capacity from the deadline itself.

### J4-paridade-presumida
Two channels or two code paths that share the same logic are presumed to behave
identically — but the parity is coincidental, and a real asymmetry bites when
conditions differ. The keyboard backlight is quantized; the screen is
continuous; the shared apply-verify passes for one and fails for the other. A
value animation must suspend under drag on one path where the other never
noticed.
Decision: audit shared paths for *real* vs *coincidental* parity and pin the
intended per-channel behavior by test — never assume shared code means shared
behavior.

### J5-raio-global
An apply failure in one suppression channel disengaged consumption for **all
three** domains and persisted the preference off — an over-broad blast radius
that survived relaunch with no signal, leaving the user's own choice silently
overwritten.
Decision: scope failure handling to the channel that failed, never globally, and
treat a transient failure as a non-persisted suspension with a menu signal — the
molds now known as per-domain-suspension and pref-sacred.

### J6-latch-do-edge
A single notification edge + read-at-the-moment + dedup with no decoupled
re-verification latches on stale state when the authoritative source lags: the
unlock edge reads a stale `CGSession` dict, the reconciler dedups the redundant
value, and the state sticks — waiting forever for a transition that already
happened.
Decision: an edge never flips state on its own; it triggers an authoritative
re-read and, because the notification can beat the underlying update, schedules
settle re-reads (short backoff + periodic tail) until the settled read emits the
missed transition (see settle-rereads).

### J7-estado-do-outro-lado
A resource whose real state lives beyond an IPC boundary cannot be audited by a
local health-check. The tap port can be valid **and** enabled while the
WindowServer has quietly stopped routing events to it — "enabled-but-deaf" — and
no local check reads the routing, only the port.
Decision: where the truth is unreachable, act preventively rather than detect —
reinstall the tap unconditionally at the unlock and wake edges (see
preventive-reinstall). Confirmed in-process cure is still inferred, not
hardware-proven; the decision holds because the failure is otherwise
undetectable.

### J8-a-guard-that-cannot-read
A guard that cannot read its evidence must fail, never pass. Three of them were
written the other way and all three were measured: CI's ad-hoc/hardened-runtime
check greps `codesign` output into FLAGS and, with a missing .app or an unsigned
bundle, compares an EMPTY string against both patterns — "no flags found" reads
as "no bad flags" and the step goes green; the test watchdog took xcodebuild's own
exit code when no verdict line was printed, so a run that reported nothing passed
through the one rule this repository states about test results; and release.sh's
`set -e` aborts AT an assignment whose command substitution fails, so four checks
that each carry a written explanation (generate_appcast missing, no
sparkle:edSignature, sparkle:version absent, sign_update missing) died one line
before the sentence that says what happened — the optional one becoming a mute
hard abort.
Decision: evidence that was never read is not clean evidence. Every guard names
the three states apart — read and good, read and bad, not read — and the third
joins the second. In shell that means the assignment is split from its test
(`X="$(…)" || true`, then the check that owns the message), because errexit and
pipefail turn "found nothing" into "exited before explaining". The lesson is not
about bash: a check whose failure mode is silence is a check nobody is running.

## Named decisions

### per-domain-suspension
An apply failure suspends **only** the channel that failed (volume /
screen-brightness / keyboard-brightness; mute rides with volume): its keys return
to the system for native feedback while the other domains stay suppressed, and a
read-only backoff probe (1→16 s, then 30 s) silently re-engages on recovery.
Rationale: a keyboard-brightness failure must never kill volume suppression —
that was the J5 blast radius. Only a durable suspension with the channel present
surfaces in the menu.
The suspension is per domain; the apply CHAIN is not, and saying so is the honest
part. Applies are serialized globally so an autorepeat burst cannot read the same
base value twice, which means a hung write on one channel also delays the next
consumed key of every OTHER domain, by up to the 2 s deadline. Accepted, and
bounded twice — the deadline abandons the hung write, and the failure suspends
only the channel that hung, so its keys go back to the system instead of entering
the chain again. A per-domain chain would be the honest shape (the stated reason
for the global order is per domain to begin with: volume and brightness never
share a base value), and is not worth tripling the pending/generation state for a
bounded 2 s worst case that already ends in a suspension the menu names.

### pref-sacred
The only writer of the persisted `suppressesNativeOSD` preference is explicit
user action. No failure path — and no lock-aware suspension — ever writes it.
Rationale: the durable harm of J5 was the auto-disengage persisting the pref off,
surviving relaunch, with no signal. Suspension is runtime state; the preference
is the user's intent, and only the user changes it (pinned by test).

### preventive-reinstall
The tap can go enabled-but-deaf (valid port, delivery stopped) after
display-sleep/wake — undetectable locally (J7). So the tap is reinstalled
**unconditionally** (fresh port, paired uninstall→install with no orphan, the
consumer preserved by construction) at every physical edge that can have
re-routed delivery — the four triggers: display wake (`screensDidWake`), system
wake (`didWake`), the unlock/return edge, and a display-topology change
(`didChangeScreenParameters`, the hotplug with no sleep that fires neither wake
nor lock) — independent of the suppression preference: the deafness kills plain
brightness observation too, so pref-off must still reinstall. Order is pinned:
unlock → reinstall → re-engage.

### tap-mutation-on-its-own-thread
Reconfiguring the tap's mach port — install, uninstall, setEnabled — happens only
on the thread that owns its run-loop source (the main run loop), because that is
also the thread the callback is delivered on. From anywhere else two things go
wrong: the callback takes the source's lock, so a mutation holding it across a
WindowServer round-trip stalls the main thread *inside* a tap callback — and a
callback the system deems slow gets the tap disabled; and invalidating a port whose
callback is mid-flight loses that event's swallow decision (the key applies AND
reaches the system — the double HUD the reinstall family exists to cure). Mutating
on the main thread makes both impossible by construction.
The four preventive-reinstall edges buy this with `queue: .main`. The 2 s health
poll buys it by splitting DETECTION from MUTATION: it reads the permission and the
port state on its own thread (both blocking IPC, which must not become a periodic
cost on the main thread) and hops only for the rare tick with something to change,
where every guard is re-derived under the lock. Detection is therefore advisory: a
stale "faulty" read costs a hop that no-ops, a stale "healthy" read is retried one
interval later, so the filter can never latch. Those two reads stay on the
cooperative pool rather than `blockingCall`/`DispatchQueue.global` because the tap
token is a non-Sendable `AnyObject` and cannot cross into a `@Sendable` closure;
one periodic caller parks at most one pool thread. Still open by design: `deinit`
uninstalls on whatever thread drops the last reference — a lifecycle fix (an
explicit main-thread stop), not a threading one.

### settle-rereads
The lock source never lets a notification edge flip state directly: each edge
fires an authoritative `CGSession` re-read and puts a short, finite backoff in
front of the periodic tail — and the tail itself runs FROM CONSTRUCTION, not
from the first edge (parity with the tap health-check, which verifies from
init). A finite backoff closes the notification-vs-dict skew only
probabilistically; the launch-armed tail makes it deterministic and covers the
[launch, first-edge) window when the session's first lock notification is
dropped (DistributedNotificationCenter is best-effort). Same class of safety
poll as the tap health-check — the cure for J6.

### unreadable-session-is-unsafe
The lock source decodes the session dictionary through a pure translation
(`ScreenLockSessionTranslation`), and the absences that dictionary can have point
opposite ways on purpose. `CGSSessionScreenIsLocked` is absent while unlocked and
appears only once the screen locks (measured), so a missing key is the normal
desktop — reading it as locked would suspend suppression forever and kill the
feature in silence. Anything else unreadable — no dictionary at all, or a session
that cannot report `kCGSSessionOnConsoleKey` — is "cannot tell", and cannot tell
decodes as NOT safe: suppression steps aside.
Rationale: being wrong is asymmetric. Engaged over a lock shield the user gets no
feedback at all — native OSD swallowed, our own HUD impossible there, the NO-GO
the whole lock-aware policy exists to prevent; disengaged on a healthy session
costs only our own HUD, with the native OSD taking over. The unreadable-dictionary
trigger is believed unreachable for a GUI app (the dictionary is there for any
process inside an Aqua session), so this is a direction chosen for a case nobody
has seen, and logged so the field can prove or refute it. Holding the last reading
instead was rejected: launch has no last reading, so the same choice would still
have to be made, with one more path to get wrong. The decoding sits above the
border for the same reason `ScreenLockReconciler` does — the production read was
the one part of this source no test could reach.

### write-health-axis
A second recovery axis beside the read-only probe: a counter of unconfirmed apply
failures catches the "consumed the key but the write is silently dead while reads
still succeed" hole that the probe alone misses. It resets only on a verified
apply (plus the `setEngaged` flip and an explicit user retry). Reset on the
lock-flip is intentional and load-bearing — the re-engage after unlock is born
healthy.

### read-deadline-pool-rule
A blocking sync operation raced against a deadline runs on `DispatchQueue.global()`
— never the cooperative pool, nor `Task.detached`. The cooperative pool has fixed
width and does not overcommit, so blocked orphans accumulate and the deadline,
resuming on the same pool, strangles itself; the GCD global pool grows when
threads block, so an orphan there costs a thread out of that queue's own ceiling
instead of the app's concurrency. Async operations use unstructured detached
tasks instead. (The applied form of J3-deadline-cooperativo. Which side of the
rule an operation falls on is decided by its BODY, not its signature — see
async-signature-is-not-a-suspension-point.)

### async-signature-is-not-a-suspension-point
The rule above was written for reads and quietly broken for writes, because the
three actuators *looked* async: `func setVolume(…) async throws` whose body is a
straight-line Core Audio or dlsym'd C call, with no `await` anywhere in it. Such
a function never suspends — it runs to completion on the thread that picked it
up — and since a nonisolated `async` function hops off its caller's actor onto
the global concurrent executor, that thread is a cooperative-pool thread whether
the call came from `Task.detached` or from `Task { @MainActor in … }`. So the
write path was the exact pool-starving orphan the read rule exists to prevent,
and the file stating the rule was the file breaking it. All three legs measured
on a 12-core machine: an `async` body with no `await` called from a `@MainActor`
task reports `pthread_main_np() == 0` on another thread id (it hops); 12 blocked
orphans leave a fresh `Task` never scheduled AND the deadline's own
`Task.detached` sleep never firing; 24 blocked blocks on `DispatchQueue.global()`
still let a new one run.
Decision: the hop belongs at the border that owns the blocking call, not at the
one caller that happens to bound it — the actuators wrap their C call in
`blockingCall`, so both the deadline-raced key path and the Coordinator's slider
drag are covered by construction. Reviewing "is this async?" means reading the
body: a signature is a promise about the caller, never evidence about the
callee.
The hop is not a property of the language mode's number, but of one upcoming
feature. Absent `NonisolatedNonsendingByDefault` — this project's state today — a
nonisolated `async` function switches away from its caller's actor; under it
(SE-0461, implemented in Swift 6.2, opt-in now and the default in a future language
mode) it stays on the caller's actor, so the same straight-line C call blocks the
main thread rather than the pool. The hazard changes address instead of going away,
and `blockingCall` answers both. The idiomatic replacement, when the floor allows
it, is SE-0417's task executor preference, whose own motivation names this exact
case ("you may not want to perform [blocking IO primitives] on the width-limited
default pool of Swift Concurrency") — but `TaskExecutor` and
`withTaskExecutorPreference` are macOS 15.0+ and `DispatchQueue`'s conformance to
it macOS 15.4+, against this app's macOS 14.0 target, so the
continuation-plus-`DispatchQueue` shape is not a workaround for a missing idiom, it
is the one available spelling. What bounds the residual GCD's growing pool costs is
not a count of call sites but their shape: every one is single-flight (one apply per
key, one read in flight per channel, one decode per panel).
Mechanical backing was tried and measured out (2026-07-31): SwiftLint's
`async_without_await` was enabled under the strict gate and produced 31 hits —
every one a conformance whose protocol forces the `async` keyword (`isAvailable()`,
actuator commands, and their mocks), zero real findings. The rule cannot tell a
forced signature from a chosen one, and 31 scattered disables would teach readers
to ignore the marker, so it was removed with this measurement recorded beside the
opt-in list in .swiftlint.yml. Reviewing "is this async?" stays a reading of the
body, and this entry is where the shape to look for is written.
The AVAILABILITY guards of the brightness sources fall under the same rule, and one
of them was breaking it: `PolledBrightnessSource.isAvailable()` was a straight-line
border call behind an `async` signature — on the keyboard channel, an enumeration of
the backlight IDs over the private client's connection, IPC that can hang. It hops
through `blockingCall` now, and onto the GLOBAL pool rather than that channel's
serial queue: availability records no value, so it needs no ordering against the
readings and must not park behind a stalled read.

### child-process-deadline
Every one-shot subprocess interaction is time-bounded: waiting on a
`terminationHandler` with no deadline is waiting forever, and one hung child once
stalled the entire now-playing chain selection. The pattern is a pure, testable
race (a deadline over `SleepClock` + single-resume) plus a thin edge that on
expiry `terminate()`s and escalates to SIGKILL — the child is abandoned and
killed, never awaited.

### promotion-quiet-boundary
The now-playing chain fails over adapter→JXA on outage, but failover was
one-way: JXA became a sticky terminal state for the whole session even after the
adapter recovered. Decision: while a lower-priority source is active, a periodic
read-only probe (30 s) re-checks the higher-priority candidate and preempts it —
promoting at the next quiet boundary (a silent source is forced to a boundary so
the swap never strands a live snapshot).

**Amendment: an answer that outlives its own forwarding arms nothing.** The
promotion probe asks about availability through a call that can take its time — in
production, spawning a child process under a deadline — and the answer can come back
AFTER the forwarding that created it has ended. The `cancel()` on the forwarding's
way out does not cover that: it reaches a task already past the point where
cancellation is observed. Under the old guard (`activeSource != nil`) such an answer
armed a promotion on whatever source had been selected next — and if that source was
priority 0 (nothing above it to promote to) and still silent since selection, the
"boundary c" path STOPPED it: a fresh source killed the beat it was chosen, ghost
discard fired, one spawn/kill cycle wasted and the re-selection backoff on top.
Every selection now bumps a `selectionGeneration`, each probe carries the generation
of the forwarding that started it, and `armPromotion(generation:)` arms only while
that generation is still current. The general rule, which is the jurisprudence: an
answer returning from outside arrives in a world that may have changed — whoever acts
on it checks the generation, never merely the presence of state (the same family as
`runCapabilityRecheck` and `noteAbsent` in OSD suppression).

### ghost-discard
End-of-stream means unavailability, with no unrepresentable ghost left behind.
When the active media source ends — death, total outage, or promotion hand-off —
the Coordinator discards the snapshot and disarms click-invoke, never leaving
armed controls that would resurrect a dead expanded player no live source can
represent.

Everything armed on the snapshot goes with it, the HUD's resume promise
included. That promise is a bool ("the HUD interrupted a visible appearance")
while the revert resurfaces whatever `nowPlaying` holds *then*, so a promise
outliving its snapshot is spent on the next one. A discard under a HUD is the
case with no other guard: the state is `.hud`, so the discard's `hide()` never
runs, and the usual sequel to a discard — a browser stealing the focus, a chain
failover, the browser filter being switched back on — is now-playing landing on
a paused app, which arms no resume of its own yet gets surfaced by the stale
one: a card opening by itself about a second after a volume key, over media the
user never played. Same rule as the surface: a discard means the appearance
would be hidden, and a hidden surface owes no resume. The REPLACEMENT case is
deliberately not the same — a snapshot that merely changes identity while the
promise stands keeps it, because outside the HUD a visible appearance would have
refreshed to the new content: that is parity with the no-HUD path, not a stale
promise.

### observer-model-rejected
Evaluated migrating away from consuming the media keys to the SlimHUD model:
don't consume keys, suppress the OSD by freezing the renderer process, draw the
HUD by observation. Rejected (2026-07-20, hardware smoke): on Tahoe, freezing
`OSDUIHelper` does **not** suppress the per-key OSD — the per-key renderer is
ControlCenter, which is NO-GO to freeze (it hosts the menu bar and has
KeepAlive) — and SIGSTOP leaves an orphan that strands the entire system OSD
under a crash, violating crash-reversibility. The consuming architecture stays.
Reopening gate: a future macOS routing the per-key OSD to a freezable process
without collaterals, or the ecosystem demonstrating a new path on Tahoe.

### hud-capsule-track
The HUD level indicator is drawn by Crema, not by the stock `Slider`
(2026-07-27, live pixel measurement of the Tahoe OSD/Control Center on
hardware). Crema replaces the system's HUD, so it must track the system's
*HUD* look — a thumbless 4 pt capsule whose fill ends flat inside the clip
(the flat end has since been deliberately deviated from — see the amendment
below) — not the system's *control*, whose pill thumb was exactly the
misalignment reported; owning the drawing also removes the exposure that produced the bug
(Apple restyling the stock control underneath us). The capsule sits centered in
a 16 pt hit row (the stock Slider's measured height): the drag target does not
regress and no surrounding layout moves. A knob (17.5×14 pt, the measured
native size) appears **only under the pointer** — this supersedes the earlier
"no knob" deviation: the original refusal assumed a transient HUD, so the hold
was introduced with the knob to make its premise real — the pointer's arrival
cancels the HUD revert timer and its exit restarts the full delay
(`Coordinator.publishPointer`), so a hovered HUD is genuinely not transient —
precisely when the affordance matters, and exactly the Control Center's own
affordance-on-demand. The knob signal is per display
(`SurfaceDisplayPolicy.pointerInside`): only the hovered surface reveals it,
and an active drag keeps it. Scope: the knob belongs to the capsule
(Notch/Card); Classic renders the pre-Tahoe bezel's
16-segment bar filled by width (design-reference §4.4 — its documented
identity) and stays bare; the now-playing scrubber deliberately keeps the stock
Slider (precision gesture, wants a permanent grab handle).
Two amendments from the hardware follow-up (2026-07-28): (1) the fill's end is
now CURVED — a capsule, not the native flat cut — a deliberate deviation by
author taste (the iOS Music/players language); the fill width floors at the
4 pt thickness so a low value reads as a circle-capped nub, never a squashed
vertical oval, and exactly 0% stays empty. (2) The knob no longer clamps to
the fill boundary: the boundary-clamp mapping froze it for the last ~half-knob
of travel at each extreme while the value and the fill kept following the
pointer — the jam reported from hardware at 0/100%. It now travels the inset
track [halfKnob, width − halfKnob] linearly with the value (the native thumb
mapping); the fill boundary never escapes the knob's own body
(|boundary − center| ≤ halfKnob), so the capsule still reads as one piece.

### hud-fixed-dark-palette
Every skin surface commits to one fixed dark palette, in every state and under
either system appearance: Card and Classic pin `.colorScheme = .dark`
**enclosing** `vibrantSurface` (the environment reaches the AppKit-backed
material; one level lower it would darken only the ink over light glass), with
the `NSVisualEffectView` appearance also pinned as belt-and-braces — the same
commitment the notch's opaque black always made. Rationale: the hudWindow
material follows the window appearance (measured: light frosted glass under
aqua), so a system-following surface renders per-style inconsistency (Notch
dark, the rest light) and inactive-gray control chrome in a never-key panel;
and an appearance scoped per branch would flip the palette mid HUD↔now-playing
morph — one appearance per surface, always. Consequence: the artwork accent
needs a single brightness band (the light band was deleted with it).

### scrub-grace
The now-playing scrubber's release once fought its own stream: every drag
delta fired a real seek (one subprocess per pixel), the 1 Hz ticker kept
counting from the pre-seek anchor and pulled the thumb back until the
player's echo landed, and PositionReconciliation ate deliberate
sub-tolerance backward seeks as anchor jitter (J4 — the brightness drag's
cousin). Decision (2026-07-28): the drag owns the gesture — a view-local
draft shows under the finger, ONE seek fires on release, and a value set
outside an edit session seeks immediately so tap-to-seek never depends on
the stock Slider's callback order. On release the user's value takes
authority: optimistic position write (S7-safe, position-only), the source
re-anchors its ticker (`noteSeek`, a no-op default for sources with no
local extrapolation), and a grace window holds stale echoes off until the
stream itself flows at ≈ the target. Both the display override and the
source hint are bounded by honest exits — confirmation, track change, a
failed command (`noteSeekFailed` restores the pre-seek line), and a
timeout/anchor budget — so neither can ever be left stuck.

### shared-skin-skeleton
The three skin views each carried a private copy of the non-visual skeleton
(~120 identical lines: the layout enum, the empty-freeze rule, per-state
sizes, content derivation and intent passthroughs). Copies are how the
empty-boundary freeze once landed on two skins and missed the Notch — and the
mirrored test suites had already diverged the same way (Classic was missing
two pins its siblings had). Decision (2026-07-28): the skeleton lives once in
SurfaceStyleCore (`SurfaceLayoutKind` + `SurfaceLayout` + `SurfaceStyleBody`);
each view keeps only its visual body, the provenance @State the freeze
contract binds to, and one-line statics that pin the per-skin Metrics
parameter (which the per-view tests still exercise). This supersedes the
earlier "each skin's private LayoutKind stays private" choice once recorded at
SurfaceAnimation.geometryAnimation — whose boolean interface stays for its own
reason: the motion gate reads exactly two provenance facts, never the enum.

Amendment: the residue this entry licensed shrank again. The two provenance
@States became one `SurfaceProvenance` value in SurfaceStyleCore, carrying the
advance rule — `previous` follows every kind (an appearance is not a morph),
`lastVisible` skips `.empty` so the fade-out sits on the rect it is leaving — and
the motion gates that read it (`geometryAnimation`, `contentAnimation`) moved into
`SurfaceStyleBody`, which now requires the provenance and the Reduce Motion
environment read as members. Byte-identical copies were the whole exposure: the
geometry gate existed three times and the content crossfade twice, so a provenance
fix could still land on two skins and miss the third — the exact failure this entry
was opened for. What stays per view is unchanged in kind: the visual body, the
@State storage SwiftUI has to own, and the one-line statics that fix the Metrics
parameter (`surfaceSize`, `effectiveLayoutKind`, the Card's radius, the Notch's
shape), which the per-view tests still exercise.

### hover-follows-the-eye
Hover and clicks derive from the same rendered truth, on every skin. The hover
exit region used to be a state-blind union of the compact and expanded frames
+24 pt, never retargeted outside the Card: with the notch compact or showing a
HUD, a 233×100 pt invisible sticky band hung below the visible surface — and
because the monitor reports only transitions, a cursor RESTING there emitted
no exit, so no dismissal timer ran: the surface (and a held HUD) stayed
forever. Measured live, then fixed: regions retarget on every panel apply and size
report (exit = enter plus a per-edge band) — the apply-time retarget errs
TIGHT, rule frame ∩ last rendered, because the reported size predates the
state change (either stale rect alone re-created a closed bug: the previous
silhouette held the stuck band, the bare ceiling re-armed the card's dead
air) — the monitor's event mask gained the mouse-ups (the release re-syncs a
drag-exit, closing the unbounded wait; drags themselves are deliberately NOT
sampled — a live drag on the surface's own control overshoots the edge and
must not release the hold mid-gesture), and arming runs last in every apply
path. The band is directional
on the notch (lateral 5 over the clickable menu bar — tightened 8→5 by
hardware calibration, 2026-07-28 — bottom 16 over app content, top 0 at the
pinned screen edge; comfort 6 on enter everywhere) and uniform 10 elsewhere;
every band on a movable edge absorbs the open spring's overshoot (pinned,
with the exemption derived from the frame rule itself: the notch's width is
invariant across the visible states, so its static lateral edges owe no
headroom — which is what admits the 5). Calibration-in-test: any finished hover re-arms the
REACTIVE linger at 1.5 s instead of a fresh 3 s (the invoked appearance keeps
its full tail, provenance-flagged rather than value-compared — its pointer is
born on the surface from the click, so a cap would make the invoked linger
unreachable again, a production bug already pinned), and the close spring
tightened 0.45→0.35. Two
hypotheses stay deliberately unimplemented pending a hardware probe: the
multi-display pointer mirror and mouseMoved delivery to an inactive accessory.

A last contract of the monitor itself, invisible until it had a suite of its own:
disarming reports a PENDING exit. The Coordinator mirrors the pointer from these
reports, so a display that stops being armed with the cursor on it must say so once
— a silent reset leaves the mirror holding a pointer that is on no surface, and the
timers keyed on it never fire again — while a display that never held the pointer
must stay quiet, or the mirror learns a transition that never happened. Re-arming
re-samples where the cursor is NOW (the event monitors exist only while armed),
which is why the disarm clears the inside flag as it reports it. The monitor's
cursor read is a constructor parameter defaulting to NSEvent.mouseLocation for
exactly this: with the real pointer as the only input, a mutation deleting the
pending exit passed the whole suite. The border is otherwise untouched — the NSEvent
monitors stay real (SurfaceHoverMonitorTests).

### signed-without-hardened-runtime
Self-signed distribution must NOT enable the hardened runtime. `--options
runtime` turns on dyld library validation, which demands a real matching Team
ID between the process and every non-platform library it maps — a self-signed
certificate has none, so the app crashes at launch loading Sparkle.framework
("mapping process and mapped file (non-platform) have different Team IDs"),
even with every component signed by the same identity. This is the J7 lesson
on another frontier: load policy lives on dyld's side of the boundary, and
`codesign --verify --deep --strict` passes the exact bundle that cannot launch,
because it checks integrity and not load policy.
Covered at three edges. release.sh sets the runtime flag only on the Developer ID
path, compares authority + Team across the nested Mach-Os, and boots the
installed app from the final dmg requiring it to survive 5 s. CI rejects the
pairing statically: `adhoc` and `runtime` together in the code directory is
enough to condemn a build, and unlike the load failure itself that pairing is
plainly readable from `codesign -d`. That CI check now fails closed as well: a
missing .app, a `codesign` that refuses (what an unsigned bundle answers), or output
carrying no `flags=` field each end the step with their own message instead of
passing on an empty match — measured, both an absent path and an unsigned bundle
left the flags string empty and the step went green, which is a guard reporting
"nothing read" as "nothing wrong" (docs/DECISIONS.md: J8-a-guard-that-cannot-read).
And the project pins
`ENABLE_HARDENED_RUNTIME = NO` in both configurations — flipped from the YES
that made Xcode's own Product → Archive produce the unlaunchable app while
release.sh escaped by archiving unsigned. The key stays explicit: `= NO` is the
exact remedy the CI gate's error names.
Shipped broken exactly once — the v1.2 E2E caught the crash before publish, which
is why the smoke exists; reproduced again on 2026-07-29 straight from the project
settings (`flags=0x10002(adhoc,runtime)`, `TeamIdentifier=not set`, dyld:
"mapping process and mapped file (non-platform) have different Team IDs",
SIGABRT), which is why the static gate now exists too.

### key-origin-brightness-gate
The brightness HUDs show only for changes the USER made. Brightness has no
change-notification API (the sources poll), and the poll cannot tell a keypress
from the ambient-light sensor — surfacing every polled delta would flash a HUD
each time a cloud passes. Decision: a change surfaces only when it is
key-originated — a brightness key samples the source directly (zero latency)
and arms a short window for the poll to attribute follow-up deltas; outside
that window the poll stays quiet. Consequence, accepted deliberately: without
the Accessibility permission there is no tap, no key origin, and therefore no
brightness HUD at all — volume (event-driven via Core Audio) still flows. The
docs must never promise brightness HUDs without Accessibility.

Second decision, same gate: arming and reading run in different places. The
value read is a blocking private-API call (a dlsym'd DisplayServices entry
point; a round trip to the keyboard-backlight client, which re-enumerates the
keyboard IDs on every call), and `sample()` is called on the MainActor by the
suppressor's post-apply poke and by the slider echo — once per drag frame — as
well as on the cooperative pool by the router and the poll. So the reading moved
to the channel's own serial queue (read-deadline-pool-rule; the volume sibling
had already paid for that lesson) and the window stayed on the caller's thread
as `armKeyWindow()`. Splitting them is not tidiness: the window has to carry the
key's own instant rather than whenever the read returned. And because a
key-driven reading emits on any change whether the window is open or not, a
reading in flight is no longer protected by ordering — so `standDown()` now
speaks for the readings the key already asked for, and one that comes back
spoken for degrades to a plain reading (see betterdisplay-osd-source: without
that, a neighbour reporting the same press gets our hardware-scale bar drawn on
top of its own). The launch baseline read is the deliberate exception, once per
process on the constructing thread, because that thread is already blocked far
harder building the backend.

### login-item-intent
The launch-at-login registration lives beyond the Background Task Management
boundary, and macOS revokes it whenever the bundle's code identity changes — a
rebuild, a reinstall, and, in one stroke for every installed user, the eventual
move to Developer ID. Diagnosed on hardware: a boot where the app simply never
launched, the system logged nothing at all, and a ghost record lingered until
System Settings pruned it. With the system status as the ONLY source of truth,
the user's choice vanishes silently — the toggle reads off and no one is any
wiser. Decision: persist the user's INTENT (and the build it was made under),
never to act on it, only to notice the loss. The build is what tells the two
authors of "gone" apart — a registration lost across a build change was revoked
by macOS (warn, and offer one click); one lost under the same build was removed
by the user in System Settings (forget the intent, say nothing). Auto-repair was
deliberately rejected: the invalidation is a security signal ("this binary is
not the one you approved"), and re-registering behind the user would contradict
the app's own rule of never adding a login item uninvited. Measured and ruled
out along the way: the DMG's quarantine attribute does not block registration.

Two corollaries the first implementation got wrong, and the reason the write is
now split from the read. First, the intent is recorded only by an attempt that
did NOT fail: the build stamp is the discriminator, so stamping a failed enable
with the current build makes the next reading say "gone under the same build" and
file the user's own request away as their own removal — the failed one-click
repair of a revoked registration erased its own warning, and the app went back to
not launching with nothing left to say. A failed disable keeps the intent for the
mirror reason: the registration it could not remove is still there. Second,
forgetting a user-side removal is a WRITE, so it belongs to a lifecycle edge
(once at launch) and not to the menu's verdict: that verdict is read inside a
SwiftUI view body, rebuilt whenever SwiftUI invalidates it rather than when the
user opens the menu, and nothing user-visible waits on the bookkeeping anyway (a
user-side removal already renders as silence).

### media-key-chain-contention
Session event taps are a chain, and `.headInsertEventTap` means the app that
inserted LAST is served FIRST. Two apps can legitimately want the same key — a
display utility driving brightness with its own curve, Crema drawing the HUD —
and at login the winner is decided by a race nobody can see. Field evidence
(2026-07-29): Crema started at 10:52:06 and had its tap up at 10:52:07.0; the
neighbouring display app started at 10:52:07 and inserted after us. The system's
registry then listed it ahead of us, and the persisted log shows the exact
signature — `media key observed: volumeUp/volumeDown` flowing, not one
`screenBrightness` line, native OSD on screen. Quitting the neighbour restored
Crema's HUD; reopening it broke it again; relaunching Crema cured it (a fresh
tap goes back to the head). Note what this class is NOT: the tap was healthy and
delivering the whole time, so the J7 deafness cure — preventive reinstall — is a
placebo here, and an earlier broken instance did reinstall three times without
curing, consistent with the neighbour re-inserting on the same physical edge that
triggered our own reinstall. Before suspecting our own port, ask who is in front
of it. `CGGetEventTapList` is the only view of that from outside the process;
list order is insertion order and therefore delivery order — verified on hardware
in both directions, but NOT documented (what the SDK does promise is that a HID
tap precedes every session tap, and that each read resets every tap's min/max
latencies — for every tap in the system, neighbouring apps included). Never on a
poll, then; and not once per menu rebuild either, because a SwiftUI body is
rebuilt whenever SwiftUI invalidates it and the app does not choose when — the
reading sits behind a coalescing window (see `menu-status-before-warnings`).
Decision: **Crema does not fight for the position.** Re-inserting periodically is
an arms race decided by whoever moved last, with a key-loss window on every
reinstall; moving to `kCGHIDEventTap` wins deterministically but silently takes
the keys from every third-party app that legitimately wants them — including the
very app the external-display integration is meant to cooperate with. So the app
names who is ahead and leaves the choice where it belongs. The naming errs toward
silence: listen-only taps, disabled taps, taps with a disjoint mask, a chain we
have no tap in, and a contender macOS has no display name for all produce no
warning — a missed line costs a diagnostic, a false one accuses a neighbour.
Naming it is only half the answer; the other half — cooperating instead of
contending — shipped alongside it, see `betterdisplay-osd-source`.

### betterdisplay-osd-source
The way out of the key contention above is not to win the key but to stop needing
it: BetterDisplay publishes an OSD notification for third-party HUDs (the same
door MediaMate and DynamicLake Pro use), so the neighbour keeps the key and its
own brightness curve while Crema draws the bar. Both halves ship — the
notification in, for every display the neighbour names, and the drag back out
over the same channel's request/response direction (**The way back**, below),
round-trip measured on hardware. What stays roadmap is Crema applying a key on
an external panel itself, which needs the apply+verify cycle. The contract below
was measured on the wire against
BetterDisplay 4.3.5, not read off a wiki:
`pro.betterdisplay.BetterDisplay.osd`, with the payload as a **JSON string in the
notification's `object`** (not `userInfo`); brightness arrives as
`{"controlTarget":"combinedBrightness","displayID":1,"maxValue":64,
"systemIconID":1,"value":40}` — a scale of the app's own choosing, so only the
ratio is portable — one notification per key press, no autorepeat flood. Four
decisions came out of that measurement. **One prefix only**: 4.2.2+ publishes
every event under both the current and the legacy `com.betterdisplay…` name, so
subscribing to both would double it. **The exact name, never a wildcard**: macOS
does not deliver nil-name distributed observation at all — a wildcard listener is
silent by construction, which cost two probes to discover. **Volume and mute are
left alone** even though BetterDisplay reports them: Core Audio already emits for
every volume change whoever caused it, so a second source would draw two HUDs;
brightness has no such notification, and that absence is the whole reason this
source exists. **Every reported display is named, the built-in included**:
`displayID` resolves at the border to `SystemHUD.Target.display(uuid)` through
the same translation the panel roster uses, and the only drop is a UUID that
will not resolve — a screen the app cannot name is one it can neither place a
bar on nor send a drag back to. (This bullet once read "other displays are
dropped", over a `display == nil` that meant the built-in: `hud-target-is-a-role`
split that flattened `DisplayUUID?` into three roles, `hud-belongs-to-its-display`
confined a named bar to its own screen, and the way back below gave the drag
somewhere to go — together, what retired the drop.) No preference gates any of
this: with
BetterDisplay absent nothing ever arrives, so there is no state to turn off.

Two payload rules follow from one fact: once the neighbour's own OSD is off, the
bar Crema draws is the user's ONLY feedback. So a payload naming no `maxValue` is
dropped rather than given a guessed scale (a confidently wrong bar is worse than
none), and a payload flagged `lock` is dropped too — a bar that refuses to move
reads as a broken HUD rather than as a locked control.

**When can both draw for one press?** Only one path, and it is closed
deliberately. With suppression ON, Crema consumes the key and BetterDisplay is
never told it happened — verified on hardware with timestamps: Crema observed
five brightness keys while BetterDisplay stayed silent, then Crema quit and the
next five presses produced five notifications and no observation. With
suppression OFF, though, Crema's tap merely OBSERVES: the key travels on to the
neighbour, which applies and reports, while the observation has already armed
Crema's own key-origin window — so the polled source would draw a second,
hardware-only reading a beat later and win, which is the wrong number exactly
where combined brightness and hardware brightness diverge. Hence `standDown()`:
a reported level spends that window (`ManuallySampledSource`, default no-op for
sources with no origin gate) AND speaks for the readings the key already asked
for: those come back from the source's own serial queue (a blocking private-API
read must never run on the caller's thread), and a key-driven reading emits on
any change whether the window is open or not — so ordering alone stopped being
enough the moment the read left the caller's thread. One press, one bar, whoever
applied it.

**The way back.** Drawing a neighbour's level and then writing through the
system's own actuator would be a bar in one scale and a write in another —
measured on the built-in display: BetterDisplay reports 0.625 (its blended level)
where the hardware reads 0.504. So a drag on a bar the neighbour drew is sent
back to the neighbour, over the same distributed channel in the other direction
(request with a uuid, answer carrying it back, deadline because an app that is
not running never answers). Three things that costs, each measured rather than
assumed. The bar has NO local value — it draws whatever the last reading said —
so the level is published BEFORE the write leaves, or the fill freezes under a
moving finger while a round-trip is in flight; the write's echo then confirms or
corrects it. A drag fires per frame, so writes coalesce latest-wins with at most
one in flight — nobody wants the levels a finger passed through, only the one it
stopped at. Those two together set a trap, sprung on hardware: the correcting
echo has to carry what the actuator WROTE, never what the caller asked for. The
call that drives the write stays inside the drain loop putting newer values on
the wire while its own argument goes stale, so echoing the argument re-draws the
bar at a level the finger already left — a fast drag flicked backwards for an
instant before the next frame pulled it forward again. Coalescing is what makes
the two numbers differ, so any actuator that coalesces owes its caller the
written value as its return; the argument is only what was asked. And a refusal
is not fatal: the neighbour's command channel is a
SEPARATE setting from its OSD one, so "reports but refuses commands" is a real
configuration — a failed command falls back to the system actuator in the same
drag (a smaller lie than a dead control), stops being asked until the neighbour's
next report proves it is answering again, and never retries mid-gesture.

External displays were held back one round for a presentation reason, not an
actuation one, and `hud-belongs-to-its-display` is what unblocked them.

The menu says which of the two is happening, because the user cannot see the tap
chain: a **confirmation** once BetterDisplay has actually reported, and an
**actionable** line — turn on its OSD notification integration — while it holds
the keys and has never reported. Presence of the app is never treated as evidence
that the integration is on; only a delivered payload is, and that claim is
dropped when the app terminates. The neighbour is matched by bundle ID, never by
the localized name shown to the user.

**Amendment: the claim is observable.** Evidence-not-presence has a corollary about
WHEN the claim is read. The Settings line reporting it is a body SwiftUI has already
built, and the person reading that line is usually the one about to switch the
neighbour's integration on in the other app — so a claim that only refreshes on the
next open answers "no" to someone who just made it true. `hasReported` is therefore
observable and the line flips with the window open; the write is guarded in both
directions, since BetterDisplay quitting with its integration off is the ordinary
case and an unchanged write still rebuilds every view reading the claim. It stays a
plain forwarding read on the way up (`AppCore.betterDisplayIsReporting` is a computed
property over the source): caching it into a stored field anywhere on that path puts
the staleness back.

### the-bar-never-outruns-the-screen
The bar has no local value: it draws the last reading, and a drag publishes the
new level BEFORE the write leaves so the fill follows the finger instead of
freezing on a round-trip (`betterdisplay-osd-source`). That trade buys
responsiveness with a promise — every level put on screen will be honoured — and
one arrangement breaks the promise outright. A bar naming an external display,
drawn from the neighbour's report, with the neighbour's COMMAND channel off: its
own actuator refuses, and the fallback refuses too, because DisplayServices is
the built-in panel's and this app writes no DDC of its own. Nothing reaches any
wire, and the fill sits wherever the hand left it — a control that did nothing,
looking exactly like one that worked.

Rule: a drag no actuator honoured returns to the last level with EVIDENCE behind
it — a reading that arrived on its own, or a level a write confirmed. Three
things this is not:

- **Not immediate.** The refusal lands while the hand is usually still down, and
  a fill that snaps backwards under the pointer is dragged forward again on the
  next frame, sixty times a second. The correction waits for the gesture to end,
  which is why the view reports the END of a drag and not merely its values: "the
  hand let go" is not derivable from the numbers, since a drag that stops on 0.4
  and a drag still held at 0.4 send the same one. A quiet-period guess would fire
  on a finger that merely paused.
- **Not release-only.** A tap lets go in a frame or two, before either actuator
  answers, so its refusal arrives with nothing holding the bar. The refusal
  corrects the bar itself when no gesture is in progress — otherwise the quickest
  gesture is the one that leaves the lie on screen, and a tap is what a person
  tries first on a control that seems stuck.
- **Not outliving its bar.** The HUD dismisses on its own timer, button down or
  not. A correction still owed when the bar goes has nothing left to correct, and
  carrying it forward pulls the NEXT drag — a good one, mid-write — back to a
  reading two events old.

We deliberately do NOT disable the control instead. Greying it out needs a
failure to learn from, so it can never help the first gesture, which is the one
that matters; the reachability it would key on is a single flag that a refusal on
an external monitor would use to disable a bar on the built-in panel, where the
fallback genuinely writes; and a control that greys and un-greys as evidence
comes and goes is jumpier than one that consistently springs back. The
spring-back already says "not taken" in the language macOS uses for a rejected
drag, and it says it on the first try.

**Amendment: a queued level carries its screen.** The coalescing outlives the call
that resolved the display — one drive drains the frames that arrived after it — so
while the queue held a bare number, a frame queued for one screen went out under the
DRIVING call's display id. The neighbour was told to dim a display nobody was
dragging on, and in silence, because the bar that asked for the change is on another
panel. Rule: a queued level travels with the display it was meant for, and a call
echoes only what reached the wire FOR THE DISPLAY IT NAMED — the last frame out of a
drain can belong to another bar, and echoing it would move this one to a level
nothing ever wrote on its screen. The single latest-wins slot stays single on
purpose: a per-display queue would preserve a frame the pointer has already left and
put it on the wire after the gesture moved on, which is the out-of-order flood the
coalescing exists to prevent (there is one pointer, so there is one gesture). Pinned
in `BetterDisplayScreenBrightnessControllerTests`: a frame queued for the external
screen while the built-in's write is in flight must reach the wire under the
external's id, and the driving call must not echo it. The display-blind
`lastWrittenValue` accessor went with the fix — nothing read it, and a "last written"
with no screen attached is the same blindness under a friendlier name; the flick it
documented lives on in the comment over the return value.

### hud-belongs-to-its-display
The app has ONE state and one panel per screen, so every panel drew every HUD.
Harmless while nothing named a display — and wrong the moment something did: a
brightness bar for the external monitor, drawn on the laptop, is a control for a
screen the user is not looking at, and its drag would dim the neighbour in
silence. Rule: a HUD that NAMES a display is shown only on that display; every
other panel treats the state as `.hidden`, which also disarms hover there, so an
empty region never reacts to the pointer. A HUD that NO screen owns keeps
appearing everywhere, deliberately: volume belongs to the output device and the
keyboard backlight to the one keyboard, so scoping either would move feedback
nobody asked to move. That exemption was originally written wider than this, and
wrongly: it covered the built-in brightness too, because the field then said only
`display: DisplayUUID?` and `nil` was overloaded between "nothing owns this" and
"the built-in owns this". The ambiguity is gone — `hud-target-is-a-role` split the
field into three and the local brightness bar now names the built-in panel as a
role — so the exemption survives only for the two channels no display can own.
A HUD naming a
display that is no longer attached shows nowhere, which is what an unplug between
the report and the frame pass should look like. The decision lives in
`WindowManager.effectiveState`, already the per-display policy seam (the
"show now playing here" preference is its other rule), so presentation scoping
never leaks into the Coordinator: the app's state stays whole and a drag on the
panel that shows the bar still acts on the display the bar names.

### global-style-default
The Settings picker footer says "Applies to every display", but the writer looped
over the displays attached at that instant and wrote one key per display UUID
(`style.<uuid>`). A monitor plugged in afterwards had no key, so it fell to the
shipped default — Notch, resolved to Card on a slitless screen — and the picker
offered no way out: it acts on CHANGE, so re-picking the value already shown is a
no-op.
Decision: the picker DECLARES one global style (`declaredStyle`), which is the
fallback of `style(for:)`; per-display keys stay as OVERRIDES on top, and the
declaration drops them, because an override left behind would hold its display on
the style the user just replaced with no UI to clear it (the per-display picker is
roadmap; resolution is already override-aware, so shipping it is a UI change
only). Two details are load bearing: the global key is NOT under the `style.`
prefix the sweep walks, or the declaration would delete itself; and an unknown
override rawValue (a style removed since) falls through to the declaration rather
than to the shipped default, since it is not a choice the user made.
Upgrades adopt, ONCE, the override of the display the picker speaks for (internal
first, then AppKit order — one shared order, or the app would adopt a style the
picker never showed), never overwrite an existing declaration, and never rewrite
the overrides. That last restraint is deliberate: overrides can disagree (a pick
made with only the laptop attached, another made in clamshell) and no timestamp
says which is newer, so adoption may take the older one — leaving the overrides
in place keeps every display that carries a key looking exactly as it looks
today, and the only visible correction is the bug itself: a display that had
fallen to the shipped default while another carried the user's choice adopts that
choice on the next launch. An install with no override writes no key at all, so
the shipped default stays a decision the app can still change.

### rendered-style-gates-settings
Settings gated the Card-only indicator picker on `.disabled(style != .card)`,
where `style` is the DECLARATION the all-displays picker holds. But what a display
draws is that declaration put through one fallback — the notch skin needs a
physical slit, so notch renders as card wherever `safeTop <= 0` — and the shipped
default declares notch. So on every Mac without a notch (mini, Studio, iMac, older
Air) and on any external-only or clamshell setup, the app drew the Card HUD on
every display in the DEFAULT state while the one control over that HUD's
appearance sat gray, the only escape being to pick "Card" explicitly: the style
already on screen. Not an edge case — a class of hardware, out of the box.
Decision: the declared→drawn mapping lives once, in `Style.resolved(on:)`, and
every reader asks IT. `WindowManager.resolvedStyle` builds each panel through it,
and the panel roster answers `WindowManager.renders(_:)` — is any connected
display drawing this style right now — which is what Settings gates on, via
`AppCore.rendersAnywhere(_:)`. The gate is an ANY over displays, never the leading
one: a notched laptop with an external monitor renders both skins at once and the
Card controls belong to the monitor.
Three consequences are load bearing. The mapping stays in that one function — the
notch style's own `safeTop > 0` guard is in-skin defense for a rule that would
run anyway, not a second resolver, and a third copy (least of all in a view) would
be the same divergence in a new place. The gate reads the ROSTER rather than
re-resolving from Preferences, so "what the user declared" and "what is on screen"
cannot drift apart by construction; Settings re-reads it immediately after writing
the declaration, since the panels are re-resolved synchronously there. And the
declaration reader keeps its own name (`currentStyle()` — what the picker shows),
so the two questions stay impossible to confuse at the call site.

### sample-dont-integrate
A UI ticker that adds a fixed step per tick is a clock that runs slow. Timers are
not real time — they fire late under load, App Nap, battery coalescing — and the
adapter source's 1 Hz tick used to do `position += 1` per delivered tick, so
every late or dropped tick was playback time permanently lost from the bar.
Measured: with music playing, the adapter emitted ONE payload in 20 s (players
register elapsed+timestamp on state changes and never re-report during steady
playback), so nothing re-anchored the display and the error accumulated for the
whole track — always in the same direction, since a `sleep(1s)`-then-work loop
never runs faster than its interval. Decision: the tick SAMPLES, never
accumulates — the source keeps an anchor (position, instant, rate) and every
tick recomputes `position + age × rate`, clamped to the duration and aged with a
non-negative age. A late tick lands on the truth, a dropped tick costs nothing, and
two ticks in the same instant count once. This is the contract of the data model, not an
invention: MediaRemote publishes elapsed WITH a timestamp and a rate, and the
adapter's own help says to compute the current time from that pair rather than
poll. Re-anchoring happens only where a payload's line is ACCEPTED by the
reconciliation — when it holds the previous value, the old anchor stays, or the
elapsed time under it would be discarded. The JXA fallback needs none of this:
it re-polls the player's real position every 2 s.

Which clock it samples is part of the decision. The tick ages on a MONOTONIC
stopwatch (`ProcessInfo.systemUptime`), never the wall clock: sampling means the
bar follows whatever clock it reads, so reading the wall clock let an NTP step
correction or a manual time change move the bar with it — backward, undoing
playback already shown, and forward, throwing it to the duration clamp until the
next payload (which this adapter only sends on a state change). Every anchor is
stamped with our own reading of that stopwatch when it is installed; the payload's
own timestamp is folded into the position before then, so the wall clock is not
part of the tick's arithmetic at all.
A FLOOR at the position already shown was tried first and REMOVED — history now,
and kept because the reasoning is what makes the current answer legible rather
than lucky. It could only stop the backward half of a wall-clock step, and it
needed a `rate > 0` exception so a rewind scan could still walk the bar back. Two
things it got right, and any future floor has to get right again: it floored the
SHOWN line and never a high-water mark (a remembered maximum strands the bar above
the truth after a legitimate backward re-anchor — an accepted payload, a seek, a
failed seek's rollback), and it kept the origin fixed instead of re-anchoring on
the backward edge, because moving the origin is exactly what makes a tick
accumulate again and lets a noisy clock ratchet the bar forward. What replaced it
is smaller and covers both directions: read a clock that cannot lie. The `max(0, …)`
still in the source is a clamp, not that mechanism, and its comment says so.

Sleep is the second half of that choice, and the word "monotonic" hides it.
`systemUptime` is `CLOCK_UPTIME_RAW`, which "does not increment while the system is
asleep" and is "identical to the result of mach_absolute_time" (clock_gettime(3);
Apple's own mach_absolute_time page says the same and points at CLOCK_UPTIME_RAW as
the equivalent). Read side by side on a Mac that had slept 8.74 h since boot, it
sits exactly that far behind `mach_continuous_time`/`CLOCK_MONOTONIC_RAW` — and
behind `CLOCK_MONOTONIC` too, which on Darwin likewise keeps counting through sleep
— and exactly equal to `SuspendingClock.now`. So the Swift twin of this reading is
`SuspendingClock`, NOT `ContinuousClock`: on Darwin SE-0329 maps the continuous one
to the monotonic clock, the one that keeps counting through sleep. That is the
behaviour a music position wants — the machine sleeping stops the playback too, so
the bar must not be credited with the closed-lid hours; a continuous reading would
jump it to the duration clamp on wake, and this adapter only sends again on a state
change. The residual is honest: audio that really did keep playing elsewhere
(handed off to another device) advanced while we slept, and the bar sits behind
until the next payload re-anchors it — the same class of residual the
backward-step rule already accepts. The other timeline in the same file is
deliberate, not drift: the ticker WAITS on `SleepClock`/`ContinuousSleepClock`,
i.e. `Task.sleep(for:)`, whose default clock is `.continuous`, so that wait keeps
running through sleep and its deadline should already be past at wake (reasoned
from the documented default clock, not measured across a real sleep — and by the
sampling rule above a late tick answers the same anyway). Waiting continuous,
ageing suspending: unifying the two would be a regression in whichever direction.

### neighbour-features-are-not-identifiers
BetterDisplay's request channel answers two different vocabularies, and asking in
the wrong one looks exactly like a platform limitation.

METADATA is asked for through `identifier`: `{"commands":["get"],"parameters":
{"displayID":"2","identifier":"UUID"}}` answers UUID, name, serial, vendor, model,
productName. A FEATURE is asked for by its own name as the parameter KEY, with no
value: `{"commands":["get"],"parameters":{"displayID":"2","brightness":""}}` →
`result=true, payload=0.063`. Same for `combinedBrightness` and
`hardwareBrightness`. And a relative write is the documented `offset` parameter —
`{"set", {"brightness":"-5%","offset":""}}` → `result=true` — not a sign on the
value, which is read as an absolute (a probe sending `+0.0625` set the monitor to
6.3% and looked like it had been accepted as a delta).

This entry replaces one that claimed the opposite. Five spellings of brightness
were measured through `identifier` — the metadata door — all refused, and that
became an anchor, a public ROADMAP item and a code comment asserting the neighbour
could be written but never read. The consequence was not a wrong sentence: it
retired a feature. "Brightness keys follow the screen you are working on" was
declined as impossible, because stepping needs a `before` and there appeared to be
none. There is one, so the apply-verify cycle runs against an external display like
any other.
Decision: an integration's own documentation is a primary source and gets read
BEFORE a refusal becomes a limitation. Five failures in one category are evidence
about that category, never about the platform — and a vendor wiki was one search
away the whole time. When a measurement says a neighbouring app cannot do something
its docs describe, the null hypothesis is that we are asking wrong.

### automation-is-fallback-only
The app required a permission it never named. The now-playing chain is adapter →
JXA → off, and the JXA elbow spawns `osascript` against Spotify/Music, which needs
Automation (Apple Events) consent — nothing in the app read that state, mentioned
it, or offered a way to it. The Permissions tab covered Accessibility only, so a
user whose adapter had died read "Accessibility: Granted", saw "Now Playing
unavailable", and had nowhere to go.
Decision: Automation gets a row, and the row is allowed to say "I don't know".
State is read with `AEDeterminePermissionToAutomateTarget(askUserIfNeeded: false)`,
which answers from the consent database and CANNOT prompt. Measured, not assumed: a
RUNNING target macOS had never decided about returns -1744
(`errAEEventWouldRequireUserConsent`) with no dialog; a closed or uninstalled one
returns -600 (`procNotFound`); only -1743 (`errAEEventNotPermitted`) is a refusal;
the bundle ID matches case-insensitively, so only a wrong id fails, never a typo in
case. The four answers stay distinct because three of them are not a refusal, and
collapsing either absence into `denied` would accuse the user of a "no" they never
said. `procNotFound` in particular is the RESTING state of a machine with no music
app open, which is why it gets its own words in the UI ("No music app open") rather
than sharing "Unknown" with the answer we could not interpret — same word for two
states that offer different buttons is what confuses people.
The aggregate over players is optimistic on purpose: ONE granted target is a
working fallback, since the fallback reads whichever player is playing.
The row's action follows the same honesty. Never-asked offers the prompt, and that
prompt is the whole path to a grant — so, unlike the Accessibility flow, there is
no pane to open afterwards. A refusal offers only the pane, because the prompt never
comes back. The two absences offer the prompt VISIBLE-but-DISABLED rather than the
pane: an app that has never asked for consent is not listed in the Automation pane,
so sending someone there lands them on a list Crema is absent from — the same trap
the Accessibility path avoids by prompting before it opens its pane.
Two scoping rules are load bearing. First, tone: a missing grant here costs the
BACKUP reader, not Now Playing, so the row states a fact in the neutral style and
never the warning orange — the escalation lives in the menu's existing
"unavailable" warning, which now carries the trail to this tab and names the same
concept ("backup reader") the tab does. Second, cost: the read is a blocking round
trip to the consent daemon per player, so it is polled only from the Permissions
tab's lifecycle edges — and the observable it writes is read ONLY by that row, never
the menu, whose body also reads `CGGetEventTapList` (which zeroes the min/max
latency counters of every tap in the system), so a state changing on a 2 s poll
would have re-run that read on someone else's dime. Scoping to a tab is as strong as
SwiftUI's tab lifecycle: both ends are idempotent, so the worst case a missed edge
buys is one poll while the Settings window is open in front of the user, and the
menu's cost is unchanged either way.
The poll also stands down while the consent dialog is up. A non-prompting read taken
then can only report the pre-decision state, and it merges last-writer-wins — it
would land after the grant and undo it on screen.
What deliberately gets NO row: the Media/Apple Music consent (`kTCCServiceMediaLibrary`).
The app has no MusicKit/iTunesLibrary/MPMediaLibrary call anywhere — scripting
Music.app is Automation, not the media library — so a row for it would assert a
requirement that does not exist and could never leave "unknown".
The subject of the question is worth recording: the events are sent by a spawned
`osascript`, and macOS attributes them to the RESPONSIBLE process (Crema), which is
what this check asks about. Probed from the other side — a child process asking this
question gets its parent's grant back. If that attribution ever changed, the row
would report a state unrelated to the fallback's real luck.

**The badge column belongs to the permission the app requires.** The tone rule
above — a fact in the neutral style, never the warning orange — was being applied
to the words while a symbol beside them said something else, and said it wrong in
both directions: a REFUSAL of the optional permission drew a harsher mark (a
cross) than the REQUIRED permission's warning triangle, and the resting state of
a Mac with no music app open drew a question mark against a machine where nothing
is wrong. So the optional row states its fact in words and carries no glyph at
all, the way the other optional integration already reports "Receiving" one tab
over. With the glyph gone, nothing ranked the two sections, so the ranking moved
into a word — the section headers say Required and Optional — which survives a
screenshot, greyscale, and colour blindness, none of which an orange-versus-grey
ranking does. The one badge left in the window sits on the required permission,
always above a button that fixes it. And where a symbol does stay, the colour
lives on the SYMBOL and never on the word: tinting a whole Label put the line
people open the tab to read at roughly 2.2:1 on a light grouped row, which passed
review only because it looks fine in the dark appearance.

**Amendment: a guard checked before an await says nothing about the world after
it.** "The read stands down while the dialog is up" was enforced at the entry of
`refresh()`, and the blocking read hops off the actor: a pass already in flight when
the user clicked is past that guard, and it resumes into a last-writer-wins merge
carrying the answer it took before the decision existed — putting `undecided` back
over the grant the user just gave. Re-checking `isAsking` on the way back does not
close it either, because the ask clears the flag before recording its own answer, so
the resumption sees a quiet monitor. The fix is a generation counter bumped when an
ask BEGINS — every read already in flight was taken of a world where nobody had
decided — and compared when the read returns; a read from before an ask is dropped,
and the poll re-reads within its interval. Pinned by
`aReadAlreadyInFlightWhenTheDialogIsAnsweredCannotUndoTheGrant`, which parks a read
across an ask that starts and finishes.

### menu-status-before-warnings
The menu bar was six conditional warning blocks stacked above three actions, each
followed by its own separator, and the only positive line in it — the one saying
the BetterDisplay integration was working — sat among them behind a "✓". With two
conditions firing at once it read as a wall of warning glyphs; with none firing it
said nothing at all about what the app was doing.
Decision: the menu is **status first, warnings only when they exist, actions
last**, and the whole split is decided in one pure place (`MenuStatus`) so the
order and the gating are pinned by tests rather than resting on the shape of a view
body.
Five rules that type enforces:
- **A status row is a fact, never a wish.** Every row is gated on the feature being
  in effect: the brightness-target row speaks only while Crema is the one applying
  the key — preference AND suppressor AND permission AND no suspended domain, the
  `cremaApplies` gate — and where Crema does not apply, the row says nothing rather
  than aiming a sentence at someone else's work. The claim about replacing the
  system indicators was this rule's first example; see the amendment.
- **The style row reports what the displays DRAW, not only what the picker
  declared.** On any Mac without a slit the shipped default declares Notch while
  every panel draws Card, so "Style: Notch" alone is false there — the same
  contradiction `rendered-style-gates-settings` was written about. The fallback gets
  its own row, in the very sentence the Settings footer already uses.
- **The neighbour reporting is status, not a warning.** Same reading, moved: it is
  the arrangement the app asked the user to make, not a fault.
- **The brightness target is status too** — see `brightness-key-target-in-the-menu`.
- **Warnings are ordered by urgency, and the order is the contract**: Accessibility
  first (without it no media key arrives at all, and the chain reading cannot even
  see us), launch-at-login last (it is about the next launch, not this session). A
  warning that offers a repair is fenced by separators from its neighbours, stated
  as one rule over the PAIR so two adjacent actionable warnings produce one
  separator instead of two. One warning carries no button but a second sentence
  instead — the dead Now Playing, whose trail out is the Automation access its
  backup reader needs.
Emoji are out, in both directions. "⚠️" carried the meaning the sentence has to
carry anyway, VoiceOver reads it mid-sentence as noise, and six of them stacked is
what made the menu unreadable. "✓" was worse than decorative: a checkmark in an
NSMenu means a CHECKED item, so a title starting with one reads as a toggle that is
on — which is exactly why the app's only good news read as noise. AppKit's own
status menus (Wi-Fi, Bluetooth, Time Machine) carry no glyph on an informational
row; they use plain disabled sentences, and that is what ships. SF Symbols via
`Label` were considered and dropped: menu-item icons are for items that stand for
an object, and a symbol that silently fails to render on an informational row
leaves the sentence unmarked anyway.
Cost, faced rather than inherited: the block reads two things that live outside the
process, and one of them — `CGGetEventTapList`, behind `mediaKeyChainNotice()` —
resets the min/max latency counters of every tap in the system, neighbouring apps'
included. A view body is rebuilt whenever SwiftUI invalidates it, which is NOT the
same as the user opening the menu, so a status block with more inputs means more
rebuilds and, unbounded, more of those reads. `MediaKeyChainNotice.Cache` bounds
them with a one-second **coalescing window**: a burst of rebuilds costs one
reading, and the answer is never more than a window old. A window and not a set of
invalidation edges, deliberately — the edges that change the answer are not
enumerable from in here (a neighbour can install or drop a tap while already
running, which is exactly what toggling its key handling does, with no notification
behind it), so an edge list would serve a stale line for an unbounded time, and the
stale line here is an ACCUSATION against a named neighbour — the direction
`media-key-chain-contention` says to err away from. The neighbour's delivered
payload is a different kind of input, a free local flag that can flip with no
notification at all, so it is part of the memo KEY rather than of its age.
Two things the window deliberately does not buy: freshness within the window, and
any claim about `loginItem.status`, which still crosses into Background Task
Management once per rebuild — one reading, not two, which is why the instance-level
`loginItemOutcome()` was removed in favour of `menuStatus`.

**Amendment (2026-07-31): the menu now leads with the switch — the rule finished,
not breached.** "✓" is banned inside a sentence because a checkmark in an NSMenu
means a CHECKED ITEM; a real `Toggle` is that meaning used on purpose, and the
menus this entry cites lead with theirs. A status row is a fact, so it could only
speak once the feature was already in effect — and the feature is opt-in and ships
OFF, so a fresh install's menu never named the headline feature at all. The
suppression row went with the switch: over a checked item its only extra claim was
"no domain suspended", and a suspension already speaks as the warning below. Cost
unchanged — the switch reads the same two values the Settings toggle gates on and
this body already receives, and the write stays behind a click.

### brightness-key-target-in-the-menu
Correct behavior nobody can see reads as a bug: with an external monitor as the
main display, the brightness key dims the laptop panel the user is not looking at.
Crema's screen brightness drives the built-in panel because that is what it has
been taught to drive, and no surface said so. (The first version of this entry
justified it as a limit of the integration — the neighbour readable only for
writing — which was our own probe asking through the metadata door; see
`neighbour-features-are-not-identifiers`. The row is right; the reason was not.)
Decision: the menu names the target, in one row of the status block, and only where
the row is both true and informative. Three states, from the display census: a lone
built-in panel says nothing (there is no other screen to confuse it with); a
built-in panel alongside another display gets the naming row; no built-in panel in
use — clamshell, or a Mac that has none — gets a row about what Crema cannot do,
because the brightness write degrades to false there instead of reaching for
whatever display happens to be main.
Four constraints shaped it.
The subject of the sentence is CREMA, never "the brightness keys". Suppression is
opt-in and off by default, so on most installs the key is applied by macOS and not
by us; a line claiming what the KEY does would assert someone else's behavior, and
on a Mac driving an Apple external display it can be plainly false.
The census is read from CoreGraphics' ACTIVE display list — the same list
`DisplayServicesBridge` resolves its write target from — and deliberately not from
the panel roster, which disagrees: the roster drops displays with no NSScreenNumber
or no resolvable UUID, and AppKit collapses a mirror set to one NSScreen. Sharing
the list is what makes the sentence unable to contradict the hardware: wherever the
list has no built-in entry the write returns false for the same reason, so line and
behavior fail together instead of disagreeing.
Silence has three causes and only two are contention. Without the Accessibility
permission there is no tap and the top-of-block warning is the only true thing to
say; with an app ahead of us the keys may never arrive, and naming a target under
that warning would contradict it. The third is load-bearing: once the neighbour is
reporting, the HUD slider writes ITS display through the neighbour's channel, so
the sentence would be false rather than merely unhelpful — narrowing the gate to
the two "someone is ahead" cases ships a lie. The arrangement this loses is a
neighbour that reports without being ahead: the keys are ours and we say nothing,
the same asymmetry the chain lines already accept, where a lost line costs a
diagnostic and a false one misinforms (`media-key-chain-contention`).
It is a pull-read, not a mirrored value. An @Observable mirror recomputed at the
display-topology edge was designed first and rejected: it would add an invalidation
source to a body whose every rebuild costs a `CGGetEventTapList`. The census is the
cheap kind — `CGGetActiveDisplayList`, local and side-effect free — so reading it
where the menu is built adds zero expensive reads, is as fresh as the build, and
needs no edge to stay correct. The census is consulted only after the gate, so a
silenced menu asks the system nothing.
No warning glyph on either row. An arrangement is not a fault, and a ⚠️ on correct
behavior trains the user past the lines that do ask for action.
The row's SENTENCE was replaced when the keys learned to follow the pointer
(`brightness-key-follows-the-pointer`). The three states, the census they come from
and every gate above still hold; what changed is that the line describes an AIM
instead of a limit, and stops short of saying what happens on the other display —
this row appears only where no neighbour is ahead or reporting, which is exactly
where nobody may be managing that display, so "left to the system" is the last true
word available.

### menu-reads-mirrors
A menu that names the track reads MIRRORS of title and artist, never the live
snapshot.
`Coordinator.nowPlaying` is rewritten once per second by the position tick — which
is exactly why the tick stays out of `state` (CLAUDE.md, Fluxo de estado) — and
Observation invalidates per PROPERTY, not per value: any read of that property,
`nowPlaying?.title` included, subscribes the reader to a 1 Hz rebuild. The reader
here is a `MenuBarExtra` content body, which SwiftUI re-evaluates whenever it likes
and not when the user opens the menu, and the block beside it pull-reads the
event-tap chain (`AppCore.mediaKeyChainNotice()`, whose every call resets the
min/max latencies of every tap on the machine, third-party taps included). So the
naive line does not cost a menu line: it costs a system-wide diagnostic probe once
per second, forever, invisible from inside the app.
Decision, three parts. (1) The Coordinator publishes `nowPlayingTitle` and
`nowPlayingArtist` as GUARDED mirrors — written only when the value actually
changes, exactly like `skipSupportedByTrack` — and clears them with the snapshot in
`discardActiveMedia`, so a dead track cannot keep naming itself under an enabled
transport. (2) The media lines live in their own View, because observation is
tracked per body: a real track change then repaints that view and leaves the status
block's pull-reads untouched. (3) The Play/Pause label comes from `mediaActive`,
already written only on play/pause edges, so no second flag learns a fact the
Coordinator already publishes.
Half a contract is worse than none here: a guard that compares is one keystroke
from a muzzle that never writes, so both directions are pinned — a tick fires no
observation, a track change does (`CoordinatorMenuMirrorTests`).
The menu's transport RENDERS the Coordinator's existing verdicts
(`commandsAvailable`, `skipControlsEnabled` — the same two the surface binds to)
and adds only "is there media at all", which the surface never needs because it
exists only when media does. One decision, two renderers: a menu that decided
availability for itself would drift from the surface the first time a source
accepted play/pause and rejected a skip. That one added predicate comes off the
SAME value the status row is drawn from (`NowPlayingMenuLine.namesMedia`) — a
separate `title != nil` test is how a row saying "Nothing playing" ends up over an
enabled Pause.
Corollary for anything else the menu wants to show: the question is never "is this
value cheap to read" but "how often is the property I subscribe to written". A
per-second property is a per-second menu.
One correction to part (1), because a comment beside that guard used to justify it
with the opposite of what the runtime does. "Invalidates per property, not per
value" is about the property you SUBSCRIBE to — reading `nowPlaying?.title` binds
you to `nowPlaying`, whose value genuinely changes every second because the position
moves — and it is true. What is NOT true is the narrower claim that writing an equal
value to a mirror would itself invalidate: measured on Swift 6.3.3, an equal-value
write through the generated setter fires nothing at all. So the guard is
belt-and-braces rather than load-bearing, and no test can tell it from an unguarded
write. It stays because the alternative is resting a 1 Hz system-wide tap probe on an
optimization inside Observation that no Apple document promises — the same reason
this codebase never leans on behaviour it cannot see the other side of.

### brightness-key-follows-the-pointer
The brightness key always acted on the built-in panel, whatever the user was
looking at. With a monitor as the main display that is a key which dims the laptop
while the person reads the monitor — reported from the field — and it was correct
by the old design: `DisplayServicesBridge` resolves the BUILT-IN display for every
read and write, deliberately, because the framework governs no other panel.
Decision: **a brightness key acts on the display under the POINTER** — the rule the
display utilities that own these keys already use, and the one a person reading a
screen expects. It lives in `BrightnessKeyTargeting`, pure over the cursor and the
display bounds, and answers one of three things: the built-in panel, another
display, or nothing at all.
What the app DOES with the answer is the second half, and it is deliberately
smaller than the rule. Crema reads and writes the built-in panel and no other, so
only `.builtIn` is swallowed; any other answer hands the key back, where a display
utility behind us in the tap chain — or macOS — applies it and draws its own
indicator. That answers the obvious alternative, which is to keep dimming the
built-in panel because it is the one we can move: a consumed key owes feedback, and
a key consumed to change a screen the user is not looking at pays that debt in the
wrong currency. The two other alternatives die on the same rule — swallowing and
drawing nothing, or drawing a bar that refuses to move, which
`betterdisplay-osd-source` already rejected for the neighbour's `lock` payload.
Passing it back is also what makes the neighbour arrangement whole for the first
time: with suppression on, Crema used to swallow the very key BetterDisplay was
waiting for, so the monitor stopped responding at all. Now the neighbour receives
it, applies it on its own display and reports the level back, which Crema draws on
that display (`hud-belongs-to-its-display`).
**A handed-back key stands the local bar down.** The tap keeps OBSERVING the key it
declines, so `MediaKeyHUDRouter` arms the brightness poll, the poll reads the panel
macOS just moved, and the app would draw a second bar over the system's own
indicator — every press, in the exact arrangement this change targets. So the
suppressor fires `onHandedBackToTheSystem` and AppCore spends the source's key
window with `standDown()`, the same seam the neighbour's report already uses. One
press, one indicator, whoever drew it. The seam is named for the consequence and
not for this rule, because a second reason to hand a key back arrived later — a
control the route does not have (`absent-capability-hands-the-key-back`) — and it
wants the identical standing-down. The suppressor still DERIVES the handback from
its own state rather than carrying a reason down from the tap: an autorepeat that
passes on the latch, after the pointer has already crossed back, must stand down
too, and a carried reason would say it is ours.
Five properties of the rule, each one a case that cost a decision.
**No fallback to the built-in panel**: that fallback IS the bug. Clamshell needs no
branch of its own — with no built-in among the bounds the rule never answers
`.builtIn` — and a pointer nobody can place answers nothing rather than picking a
screen. A quiet consequence: in clamshell Crema no longer swallows a brightness key
it cannot apply, so the escalation that used to end in "Crema couldn't apply the
change" — five failed applies against a panel that is not there — cannot start.
**A single display answers itself, pointer or no pointer**: with one screen
attached the pointer disambiguates nothing, so a failed reading must not disable
the keys on the Mac that has exactly one panel. Not a disguised fallback — in
clamshell the single display is the external one and is answered as such.
**One coordinate space, chosen so there is no conversion to get wrong.** The
pointer is read with `CGEvent(source: nil)?.location` and the bounds with
`CGDisplayBounds`: both are CoreGraphics' global display space, origin at the
top-left of the main display, y growing DOWN. An earlier draft took the bounds from
the AppKit panel roster and flipped y inside the rule; the flip's sign is the
difference between the display above and the display below, and it is a line of
arithmetic that exists only because the wrong list was chosen. Bounds are half-open
on both axes, the way CoreGraphics tiles them, so a seam belongs to exactly one
display and the answer never depends on list order — and the load-bearing seam,
with a monitor placed ABOVE the laptop, is the laptop's menu bar sitting on the
laptop's own `minY`, which the laptop owns for free.
**The list is the ACTIVE display list, not the panel roster** — the same list the
brightness write resolves its target from and the menu reads its census from, for
the reason `brightness-key-target-in-the-menu` already wrote down: the roster drops
displays with no NSScreenNumber or no resolvable UUID and collapses a mirror set to
one NSScreen, so a key aiming by the roster while the menu speaks from the census
is how a true sentence ends up over the opposite behavior. It is read fresh at each
press rather than snapshotted at the topology edge: `CGGetActiveDisplayList` is
nonisolated and local, so a snapshot would buy nothing and cost a lock, an
invalidation edge, and a window in which a key aims at a display that already left.
The only per-press readings are that list and the cursor — nothing like
`CGGetEventTapList`, whose every call resets the latency counters of every tap on
the machine (`media-key-chain-contention`), and nothing on any poll: a key-up pays
nothing and the menu asks this nothing at all.
**A mirror set gives the tie to the built-in.** Mirroring reports one rectangle per
display, so the point is inside both and, without an explicit tie-break, list order
decides — handing the key back half the time for a screen the built-in panel is
itself lighting.
The verdict is latched for the whole press, in BOTH directions
(`SuppressionDecider`): a pointer crossing displays under a held key cannot turn a
passed press into a swallowed one, which would leave the system downs with no up —
half a press with no closing event. (Not the autorepeat: that one is generated
upstream of every CGEventTap, armed and cancelled by the physical key edges, so no
tap can strand it.) Same latch that already kept a swallowed press swallowed, now
stated as one rule.
What is NOT here: applying on the external display, and any identity for it. The
write half exists (`BetterDisplayScreenBrightnessController`, used by drags), but a
stepped key also needs a LEVEL to step from and verify against, and the neighbour's
brightness read (`neighbour-features-are-not-identifiers`) has no caller yet. Until
it does, `.anotherDisplay` carries no UUID — a field nobody reads is a field that
goes stale, and adding it back is one stored property.
What this does NOT fix, stated plainly so nobody reads more into it: with no
neighbour behind us, the key handed back goes to macOS, which dims the built-in
panel anyway and shows its own indicator. Crema stops being the one that dims the
wrong screen; it cannot stop the system from doing so. That is the same contract
`per-domain-suspension` already accepts, and it is why the menu row promises an aim
and never an outcome on the other display.

### hud-target-is-a-role
`SystemHUD.display` was one `DisplayUUID?` carrying two different facts, and the
field found the seam: with a monitor attached and the pointer on the laptop, a
brightness key moved the laptop's panel correctly and drew the bar on BOTH
screens, while the neighbour's path — which names a display — correctly drew only
on the monitor. The type itself documented `nil` as "the internal display" while
the presentation layer read the same `nil` as "nobody said which screen, so draw
everywhere". Both sentences were load-bearing and they contradicted each other.

Why that stopped being untidy and became a defect: the extra bar is not spare
feedback, it is a live CONTROL. Every panel is handed the `.hud` state and draws a
slider, and a drag on the monitor's copy wrote the BUILT-IN panel — so the second
bar was a control for a screen the user is not looking at that dims a different
one in silence, word for word the harm `hud-belongs-to-its-display` was written to
prevent, in the direction nobody had checked. The app had also already committed
to the premise: since `brightness-key-follows-the-pointer` it BETS that the pointer
marks attention when choosing which panel to dim. It cannot know where the user is
looking for actuation and not know it for presentation, in the same gesture.

Decision: the HUD names a ROLE — `.noDisplay`, `.builtIn`, `.display(uuid)` — and
whoever owns the panel roster resolves it. The producer states only what it really
knows: `BrightnessBackend.target` is a compile-time constant of the technology
(DisplayServices governs Apple-controlled panels and that bridge resolves the
built-in for every read and write; a keyboard backlight belongs to no screen), so
the shared source stamps it with no system call on the emit path and, crucially,
with no `kind` branch — one source type serves both channels over one emit line,
and a target decided there rather than by the backend would scope the keyboard bar
too.

Why identity is resolved at presentation and not at the border. The app has TWO
inventories of screens and they disagree by design: the panel roster drops a
screen with no `NSScreenNumber` or no resolvable UUID and AppKit collapses a mirror
set to one `NSScreen`, while `CGGetActiveDisplayList` keeps them. A UUID resolved
at the border is a key cut from the other lock — every disagreement resolves to a
HUD naming a display no panel carries, which shows on NO screen: worse than the
reported bug, and with the key already swallowed. `WindowManager` instead asks the
roster which of ITS panels is internal (`isInternal`, taken in the same snapshot
that created the panel), so role and panel cannot drift apart. It also costs
nothing on the hot path: resolving a UUID at emit time would put a display
enumeration inside the serial queue that already serializes this channel's
blocking reads.

The built-in role falls OPEN, not shut. With no internal panel in the roster a
`.builtIn` HUD shows on every display — today's behaviour — instead of none. That
case is reachable with the key already swallowed (`BrightnessKeyTargeting` gives a
mirror set's tie to the built-in on purpose), and a consumed key owes feedback, so
too much of it beats silence. The fall-open is narrow and decided BEFORE there is
an owner: a display that was NAMED and is gone still shows nowhere, which is what
an unplug between the report and the frame pass should look like. Both shapes
leave a log line, because a HUD nobody draws is the one scoping outcome with no
visible trace.

Two constraints any future shortcut will break. First, the target must be stamped
by the SOURCE: the drag's confirming echo closes the loop by re-sampling the source
rather than re-publishing the applied value, so a stamp added in the key router or
the Coordinator is undone one frame later and the bar jumps from one screen to all
of them inside the gesture. Second, actuation reads `commandDisplay`, where
`.builtIn` and `.noDisplay` both spell nil: every actuator already treats nil as
"my own panel" (the system brightness one accepts nil or the built-in's own UUID;
the neighbour's resolves nil to the built-in ID) and the volume actuator rejects a
named display outright, so the roles have to arrive as nil or a drag on the local
bar would throw where it used to write.

Known gaps, stated rather than sold as fixed. A mirror set is a coin flip: the one
`NSScreen` AppKit reports may or may not be the internal one, and when it is not,
the bar falls open to every display plus a log line. And a payload from the
neighbour that names no display stays `.noDisplay` and still draws everywhere — it
has never been observed, and calling it the built-in would be a guess that also
routes a later drag to a panel it may not have meant, which
`betterdisplay-osd-source` already rules against ("drop rather than guess"); it is
also the payload shape the local source's stand-down depends on seeing. The trigger
that reopens this decision: the day the app can read a SECOND Apple-controlled
panel, `.builtIn` stops naming exactly one screen and the producer has to name the
display it read.

### assumed-isolation-is-measured
The rule first, because it outlives the case: an assumption that cannot be caught
may rest on an archived guarantee only if it ALSO rests on a measurement someone
can re-run, and the comment names both — archive status included. A citation that
hides its own age reads as authority it no longer has.
Nine `MainActor.assumeIsolated` calls sit on system callbacks, each a fatalError if
its callback ever arrives off the main thread, and they do not all rest on the same
footing. Five are NotificationCenter block observers registered with `queue: .main`
— live, undeprecated doc that names the exact predicate ("the operation queue where
the block runs", and `OperationQueue.main` is "the operation queue associated with
the main thread"). Four are NSEvent monitors, and for those Apple's only written
statement is in the Documentation Archive: the Cocoa Event Handling Guide,
"Monitoring Events", updated 2016-09-13 — "The handlers are always called on the
main thread". The live NSEvent pages, the AppKit header and the SDK annotations are
all silent.
The trap is kept, for reasons that outlive the citation. What the runtime checks is
thread identity, not dispatch-queue identity: outside Swift Concurrency the
main-executor check is `isMainExecutor() && isExecutingOnMainThread()`, bottoming
out in `pthread_main_np()`. So "main thread" is the right guarantee and not an
approximation of one — and a custom OperationQueue with `underlyingQueue = .main`
would NOT be the same contract, which is the edit to refuse here. The non-trapping
alternative — guard on `Thread.isMainThread`, hop otherwise — guards on the same
predicate in practice, so its fallback is unreachable, and the hop it would perform
is the reordering these call sites exist to avoid (`settle-rereads` depends on that
ordering). Graceful degradation has nothing to degrade to: `sample()`,
`routeClicks()` and the Coordinator are all MainActor, so off-main delivery is
already corruption, and a trap beats corrupting quietly.
What changed is the evidence, not the code. Measured on macOS 26.5.2 / Swift 6.3.3,
posting from a background thread: all five mechanisms (local monitor, GLOBAL
monitor, NotificationCenter, DistributedNotificationCenter, NSWorkspace center)
delivered on the main thread — which is the predicate the runtime checks, so the
assumption holds by construction. The global monitor is the one no live document
covers at all, and it was the one never measured.

### absent-capability-hands-the-key-back
With suppression on, a key consumed for a control that does not exist produced
nothing at all. Not our bar — the apply returned a no-op, and `applyVerified` had
no branch for a no-op, so no HUD poke and no echo — and not the native OSD either,
because the tap had already eaten the press. An HDMI output with no volume control,
a device with volume and no mute plane, a Mac whose keyboard backlight had not
enumerated yet: press, silence. On screen brightness with the private symbols
unresolved it was worse than silence, since every brightness key was swallowed
forever and the panel simply stopped responding, with one `logger.notice` as the
only trace. That breaks the rule this project already wrote down in
`brightness-key-follows-the-pointer`: **a consumed key owes feedback**, and
swallowing while drawing nothing is the alternative that rule already killed.
Decision: **an absent capability hands that key back to the system, which applies
it and draws its own indicator.** It is not a new state and not a new machine. It
is the answer the app already knows how to give — "this key is not mine to take" —
so it rides the seam that answer already has: the swallow verdict is refused at the
press, the whole press goes back (down and up together, never half), and the local
bar stands down so one press produces one indicator.
**Absence is not failure, and the two must never be conflated.** A suspension means
something malfunctioned, so it opens a recovery probe, feeds the write-health axis
and can escalate to the menu with a repair button. A missing control has nothing to
repair: it never suspends, never counts toward escalation, never reaches the menu.
That separation is enforced by WHERE the fact may be written — only at the five
guards that ask a channel for a capability. Five guards for four capabilities: the
mute plane is asked twice, by the mute key's own plan and by volume-up's
unmute-first step, and both must record, because volume-up is pressed far more
often and a suite that learns only through the mute key would let that second site
be deleted in silence, never in the `catch`. AirPods dropping
between the write and the verify fails INSIDE the apply and throws; it must stay on
the suspension path with its probe, and it does, because the absence guards run
before any write and return rather than throw.
**The grain is the CAPABILITY, not the domain.** Mute rides with volume as a
suspension domain, deliberately, because their recovery is one. But `supportsVolume`
and `supportsMute` are two separate Core Audio properties on the same device and
plenty of outputs answer yes to one and no to the other — the channel protocol says
so in as many words. Marking the domain when only the mute plane is missing would
hand back volume-up and volume-down on hardware whose volume works perfectly, which
loses the app's own bar for the domain that is the point of the feature. So there
are four capabilities (volume level, mute, screen brightness, keyboard backlight),
and what is learned is named by the GUARD that answered, never derived from the key
that ran it: a volume-up press consults both the level and, for its unmute-first
step, the mute plane, and deriving the name from the key would mark the level absent
on a device whose level is fine.
**Learned asynchronously, read synchronously.** The tap asks for a verdict on its
own thread — in production the main run loop, with no actor isolation — and cannot
block, while the guards it would need are IPC: Core Audio for volume and mute, and
an enumeration over the private client's connection for the backlight. So the fact
is learned on the apply, which already runs off the tap and already asks, and is
read at the press from the decider's lock-guarded set, next to the suspended set it
already reads there. One lock, one take per press.
**The latch release is not a detail; it is the difference between the fix and a
second copy of the bug.** The decider commits a verdict at the first down and keeps
it for the rest of the press, so a key HELD while the apply discovers the absence
would stay swallowed until the user let go — press, nothing, for the length of the
hold. That is verbatim the dead gesture per-domain suspension already releases the
latch to avoid, and holding volume-down to zero on an output with no volume control
is how a person meets it. Releasing the latch AT THE MARK was the first answer and
was refused: it leaks the pending up, and where suspension's own rationale accepts
that leak because its window is rare — a failure has to land inside one press — an
absence is discovered BY the press that judges it, so the leak would be the modal
outcome of every first tap. The latch is MIGRATED instead, at the next down, inside
the one lock take `decide` already holds: a held key is freed on its next autorepeat,
and a tap that never repeats stays swallowed in both phases, so the system sees a
whole press or none. Filtered by capability either way, so freeing the mute key never
frees a held volume key.
**The price, said plainly: the first press of an episode is mute.** Only that press
can discover the absence, because the apply is what asks. A held key costs the down
plus the few autorepeats until the apply answers. This is not "by construction" for
every capability — the default output device changes are pushed to this app already,
and a sweep at engage would cover the facts that are process constants — and both
were left out deliberately: the hang doubles share one semaphore per channel, so an
extra availability read at engage would consume the release a deadline test arms for
its key press, and doing it properly means reworking those doubles. Written here so
the next round knows it is a deferred improvement and not an impossibility.
**Invalidation is the user's next press, never a timer and never a probe.** The tap
keeps OBSERVING a key it hands back, so the press itself is the evidence, and it
also proves an active user is there to notice the recovery. The re-check runs off
the MainActor against the read deadline (the guards block), is coalesced to one in
flight per capability because autorepeat runs at the HID timer's cadence, is
read-only because the system already applied that press, and is **clear-only**: a
stale answer or a stall never re-asserts an absence, so this axis can never make the
app swallow a key on worse evidence than it had. It costs one native HUD on the way
back — the same price the pointer rule already pays. An engage/disengage flip clears
the whole set, like every other axis: a re-engagement is born healthy.
**The menu says nothing, and that is decided rather than overlooked.** A missing
control is not a defect and has no repair, so it is not a `Warning` — the retry
button would have nothing to retry. The flat "Crema replaces the system indicators"
line does become partly false for that one key, which is the same partiality that
made a suspended domain take the line away entirely; the difference is what the user
sees instead. On the dominant case, an output with no volume control, macOS draws
its "prohibited" HUD, and that explains the hardware better than any line in a menu
would. Adding a `Row` in the `brightnessNoBuiltIn` mould stays the honest option if
the field says otherwise; it was not taken because it costs four catalog keys for a
fact already on screen.
**Two known overlaps, both degrading toward the system.** Volume's availability
fuses "no default output device right now" with "this device has no volume control",
so a press landing inside an output transition is read as an absence and that key
goes to the system — one native HUD instead of one silent press, and the recovery is
the next press. The probe path already classifies the same reading as
`failedChannelAbsent` and already refuses to escalate it, so the two axes agree
about what the fact means; they differ only in what it costs. And the screen-
brightness case is a process constant: DisplayServices resolves its two symbols once
at init, so an absence there is never re-checked into existence and clamshell is not
this case at all — clamshell is handled earlier by the pointer rule, and a nil read
there is a failure, not an absence. The fourth case is kept for totality of the enum,
not because it fixes a scenario anyone can reproduce twice.

### external-brightness-is-write-only
The neighbour's channel writes an external display's brightness and will not read
it. Measured, not assumed: a `get` over the same request/response channel the app
already writes on was sent for five brightness spellings (`brightness`,
`combinedBrightness`, `hardwareBrightness`, `softwareBrightness`, `ddcBrightness`)
and every one was refused — with six metadata spellings (UUID, name, serial,
vendor, model, productName) in the same run as the SHAPE control, because a
request that answers nothing at all proves the request is wrong rather than that
brightness is ungettable. The metadata answered; brightness did not.
The consequence is not cosmetic, and it is why one rule stops at the built-in
panel. `brightness-key-follows-the-pointer` hands an external display's key back
to whoever can move that screen, and the obvious next step — Crema applying the
key there itself — needs the apply+verify cycle, which needs a `before`: stepping
is read → step → write → verify, and the read is the half that does not exist.
The one thing that would dissolve the impasse is a RELATIVE command, which needs
no `before` at all, so nine relative shapes were tried with the absolute `set` as
the control (increment/decrement, signed values, a `relative` parameter,
up/down/increase/decrease). The control answered; none of the nine did.
So: external brightness is **write-only from our border**, the drag on a bar the
neighbour drew keeps working (it carries an absolute level, which is exactly what
the channel accepts — `the-bar-never-outruns-the-screen`), and the key aimed at an
external screen stays handed back. The instruments are kept rather than described:
`scripts/probes/read-betterdisplay.swift` and
`scripts/probes/relative-betterdisplay.swift`, each with the shape control that
makes a negative result mean something. Reopening needs one of them to come back
positive against a newer BetterDisplay — a released `get`, or a relative command
the monitor is observed to actually honour, since a neighbour that accepts a
command it does not perform would be the worst thing to build on.

### adapter-stale-nowplaying-latch
A confirmed, OPEN fragility, written down because the obvious fix is measurably
wrong and the right one is gated on an experiment nobody has run.
The life of the TOP now-playing source rests entirely on the subprocess's EOF: the
promotion probe only ever examines the higher-priority CANDIDATE (`activeIndex > 0`),
so nothing audits the source that is currently active. If the MediaRemote
subscription dies quietly — a `mediaremoted` restart — while the Perl bridge stays
alive, the stream never finishes. The old track freezes on screen, the local 1 Hz
ticker keeps advancing over it (so the position lies rather than stalls, which is
worse), and the menu goes on saying the source is active, until a real EOF or a
relaunch. The trigger itself is unproven: the subscription loop lives inside the
compiled framework, and an adversarial verifier could not establish that a dead
subscription becomes EOF. Pure J7 — the truth lives on the other side of an IPC
boundary and no local read reaches it.
**The obvious fix is refuted, and that is the durable part.** A liveness watchdog
(an idle timeout during playback) is INVALID: the stream emits only on MediaRemote
CHANGES — which is why the 1 Hz ticker is local, and what the adapter's own
documentation means by working "without polling `get` continuously"; the framework's
strings are notification-driven with no periodic timer — so a long silence with
`isPlaying` true is the normal state of a long track. There is no ceiling that
separates alive from dead by cadence, and any number picked would fail a quiet album
before it caught a dead subscription.
The sound shape is an independent one-shot READ compared against the snapshot (a new
reconciler plus periodic spawns during playback), and it is **spike-gated**, in this
order: (1) reproduce the trigger on hardware — kill `mediaremoted` with the Perl
alive; (2) **the critical gate** — does a one-shot `get` re-establish a live XPC path,
or does it read the same dead cache? If it reads the same cache, probe-based detection
is worthless and the whole design dies here; (3) characterize the divergence signal so
the tolerance is not a guess. Verdict: registered, not implemented — a design that
spawns a process periodically during playback is not worth writing before step 2
answers.

### update-telemetry-not-yet
Anonymous update telemetry is not off for a privacy reason; it is off because
nobody could read it. Sparkle already ships the right piece and it is safer than it
looks: `SUEnableSystemProfiling` in the Info.plist does NOT turn sending on. It is
read in exactly one place (the update-permission prompt) and only makes the "Include
anonymous system profile" checkbox appear, with a disclosure of the exact contents;
what governs sending is `SUSendProfileInfo`, a default only the user's tick ever
writes. That satisfies this project's rule against pre-set consent defaults by
construction. The profile itself is appVersion, osVersion, model, cputype, ncpu,
cpuFreqMHz, ramMB, lang.
**The blocker is the hosting.** The appcast is served by GitHub Pages, which exposes
no access log, and the profile travels as a query string on the feed request. Turning
it on today would mean asking for data, the user consenting, and nobody ever reading
it — a cost in trust for a return of zero. It unblocks by moving the appcast to a host
with logs (or putting a logged redirect in front of it), and the trap that comes with
that move is written down here so it is not rediscovered: **the old URL has to keep
answering**, or every installation carrying the current `SUFeedURL` never receives an
update again. Until then the free metric is the release download count from GitHub's
API — zero code in the app.
**Explicitly discarded: a third-party analytics SDK.** The app uses private API and
holds the Accessibility permission; it is the exact profile of an app whose user runs
Little Snitch, and one unexpected connection costs more than the metric is worth.
Reopening requires the logged host to exist first, and the answer to be Sparkle's own
profile — never an SDK.

### the-feed-signs-itself
Two Sparkle plist keys were off, and both defaults are the wrong end of a trade this
app is on the paying side of. `SUVerifyUpdateBeforeExtraction` was absent, and
Crema ships a DMG: measured in Sparkle 2.9.4's own sources, `SUDiskImageUnarchiver`
returns NO from `mustValidateBeforeExtraction`, so the downloaded image was handed to
hdiutil BEFORE its EdDSA signature was checked — mounting bytes nobody had vouched
for, on the one path where the app runs code it did not build. `SURequireSignedFeed`
was absent too, which leaves the appcast itself unauthenticated: an attacker who
controls the served feed still cannot forge a download (the enclosure signature holds)
but can lie about which version is newest — freeze or downgrade.
Decision: both are YES, and they travel together because Sparkle enforces it —
`SPUUpdater` refuses to START the updater when the feed requirement is on without
verify-before-extraction, so shipping one without the other takes the whole update
cycle down rather than degrading.
The cost is not a release step, which is the part worth writing down: `generate_appcast`
reads `SURequireSignedFeed` out of the staged app's Info.plist and signs the feed on
its own, with the same Keychain EdDSA key, appending a `<!-- sparkle-signatures: -->`
block and prepending its own warning comment. `release.sh` regenerates into a FRESH
file every release, so the feed's signedness follows the newest archive's plist and
nothing else — which also means the day that key leaves Info.plist, the feed silently
stops being signed while every client that already shipped it rejects the appcast.
The consequence that outlives this entry: docs/appcast.xml authenticates itself from the first feed generated with the key in the packaged app onward — the committed feed of 1.4.0 predates the keys and carries no signature block, so today the promise is armed, not yet in force.
It was already "regenerated, never hand-edited"; from here a hand edit is not untidy,
it is an outage — clients carrying the key fail every check for 20 days, Sparkle's
default `SUSignedFeedFailureExpirationInterval`, before falling back to unsigned
operation for key rotation. Clients in the field that ever saw a feed (1.2.0, 1.4.0 — anything older predates SUFeedURL entirely) carry neither
key and are unaffected either way; the keys only bind the binaries that ship them.
No Apple code-signing requirement is added by this: prevalidation falls back to Apple
code signing only when EdDSA fails, and the post-extraction check Sparkle then runs is
seal validity (`SecStaticCodeCheckValidity`, no anchor requirement), which a
self-signed Crema passes.

### the-update-alert-nobody-sees
Sparkle schedules its own checks, and for a background (LSUIElement) app it shows the
resulting alert BEHIND every other running app when Crema is not frontmost — Sparkle's
own log says so, warning once that a background app schedules checks without gentle
reminders. An app with no Dock tile then has nothing that can bring that window
forward: the update was announced by a window the user never sees.
Decision: Crema declares `supportsGentleScheduledUpdateReminders` and implements
`standardUserDriverWillHandleShowingUpdate:` only — Sparkle keeps presenting its alert
(so the path never depends on our UI being right), and the menu bar gains the signpost
that leads to it: a plain disabled sentence with its button directly under it, the
same shape `menu-status-before-warnings` gives every fact that has a repair. The
button does not start a new check; `checkForUpdates()` on an already-presented update
is Sparkle's documented way of bringing that alert back into focus.
Three properties, each a case that had to be decided:
- **User-initiated checks never light the line.** The alert is already in front of the
  user, and a menu line pointing at what they are looking at is noise.
- **The line is cleared from BOTH ends** — `didReceiveUserAttention` (they reached the
  alert) and `willFinishUpdateSession` (dismissed, skipped, or failed) — so it cannot
  outlive the update it announces.
- **The mirror is a guarded write.** The model is a `@StateObject` of the App's scene,
  so every published change rebuilds the whole menu, including the status block whose
  rebuild costs a tap-chain read; writing only on a real change bounds a whole update
  session to two rebuilds.
One deviation stated rather than hidden: this is the only menu line that does not come
from `MenuStatus`. The updater exists solely in Release and `AppCore` never holds it,
so routing it through that pure type would add a case the Debug-hosted suite can never
reach; its whole gate is one mirrored Bool, which is the shape MenuStatus exists to
keep out of view bodies in the first place.
The delegate callbacks hop to the main actor with a `Task` instead of
`MainActor.assumeIsolated`, which the neighbouring system callbacks use. Sparkle's
standard user driver is `NS_SWIFT_UI_ACTOR` and asserts the main thread, but its
delegate protocol carries no annotation, and `assumed-isolation-is-measured` asks for
a measurement someone can re-run before a trap is installed — this path exists only in
Release, where the suite cannot reach it. A mirror that flips twice per session can
afford the reordering the hop risks; the sites that assume are the ones that cannot.

### teardown-seam-that-cannot-be-honoured
Two long-lived consumers grew a `stop()` that nobody called: the Coordinator's
(removed earlier) and `MediaKeyHUDRouter`'s. Both were worse than unused. The sources
they consume build `updates` once at init and reserve `finish` for their own end of
life, so a cancelled iteration is not resubscribable: whoever called `stop()` would
get a permanently media-less app, or brightness keys that never reach the HUD again,
with no error anywhere — and the Coordinator's variant additionally reported its own
teardown to the rest of the machine as "the media source died", discarding the
snapshot and hiding the surface, which `ghost-discard` reserves for a genuine source
death. Decision: an object that lives for the process does not ship a teardown seam it
cannot honour. The absence is documented on the type (with the reason, not just the
fact), so the next reader adds a lock or a resubscribe path deliberately instead of
adding back a `stop()` that compiles and lies. Reopening requires a source whose
stream can be rebuilt after cancellation.

### a-panel-leaves-the-roster-before-it-closes
Closing a presentation panel is not a leaf operation. `close()` stops its hover
monitor; the disarm reports the pending exit (deliberately — a silent reset would
leave the Coordinator's pointer mirror stale, `hover-follows-the-eye`); the
Coordinator collapses an expanded appearance; and that state write runs the
WindowManager's frame pass SYNCHRONOUSLY (`onPresentationChange`). With the entry
still in `entries` the pass applied to the panel just closed and re-armed its hover,
reinstalling a pair of NSEvent monitors that nothing disarms again once the entry does
leave — a dead panel sampling the cursor against regions on a screen that may be gone.
The re-entrancy guard in `runFramePass` does not cover it: that guard defers a pass
nested INSIDE a pass, and this one starts outside. Decision: `retirePanel(_:)` removes
the entry FIRST and closes second, so a re-entrant pass cannot see the dead panel; the
caller's trailing pass covers whatever takes its place. The general shape, third time
in this codebase: a teardown that crosses into another subsystem comes back through
the front door, so order the local bookkeeping before the crossing rather than
trusting the crossing to be quiet.
