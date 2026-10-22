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
capture for the session. (Covers *disabled* and the *invalidated* port too:
both are port state, locally readable, and the health-check reinstalls on
invalidation; the *enabled-but-deaf* death, which no local read can see, is
J7.)

### J2-display-id-stale
A system-resource identifier captured once at init (a `displayID`, a keyboard
backlight ID) goes stale when the hardware topology changes — the frozen ID
addresses a resource that no longer exists.
Decision: resolve the resource **per operation**, never freeze it at init.
Read/write re-resolve the ID each time (the screen-brightness bridge is the
reference and the keyboard bridge is held to parity — both bridges re-resolve
per operation, with the frozen-ID death pinned by each bridge's own test pair).

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
An apply failure in one suppression channel that disengages consumption for **all
three** domains and persists the preference off is an over-broad blast radius:
it survives relaunch with no signal, leaving the user's own choice silently
overwritten.
Decision: scope failure handling to the channel that failed, never globally, and
treat a transient failure as a non-persisted suspension with a menu signal — the
molds named per-domain-suspension and pref-sacred.

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
A guard that cannot read its evidence must fail, never pass. The class takes
three measured shapes, each what breaks when a guard is written the passing way.
An ad-hoc/hardened-runtime check that greps `codesign` output into FLAGS
compares, with a missing .app or an unsigned bundle, an EMPTY string against both
patterns — "no flags found" reads as "no bad flags" and the step goes green. A
test watchdog that takes xcodebuild's own exit code when no verdict line is
printed lets a run that reported nothing pass through the one rule this
repository states about test results. And under `set -e` a script aborts AT an
assignment whose command substitution fails, so a check that carries a written
explanation (release.sh has four: generate_appcast missing, no
sparkle:edSignature, sparkle:version absent, sign_update missing) dies one line
before the sentence that says what happened — the optional one becoming a mute
hard abort. The repository's guards are written the failing way: CI's signature
check ends the step on a missing .app, a refused `codesign` or no `flags=` field;
the CI watchdog and release.sh's test gate take only the verdict line, and no
verdict is a failure; release.sh splits each of its four assignments from the
check that owns the message.
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
A suspended domain is the THIRD reason this app hands a
key back, and it carries the same feedback duty the other two
(`brightness-key-follows-the-pointer`, `absent-capability-hands-the-key-back`)
already pay — one press, one indicator, whoever drew it. The handback fires the
same stand-down seam (`onHandedBackToTheSystem`): the tap keeps OBSERVING the
key it passed, so without the seam the router's key-time poll reads the value
macOS just moved and the app draws a second bar over the native indicator — on
the very press whose feedback the suspension exists to return to the system.
The press still kicks the recovery probe; suspension changes who recovers,
never who owes the feedback.

### pref-sacred
The only writer of the persisted `suppressesNativeOSD` preference is explicit
user action. No failure path — and no lock-aware suspension — ever writes it.
Rationale: the durable harm of J5 is an auto-disengage persisting the pref off,
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
feedback at all — native OSD swallowed, and no HUD of our own in its place, which
is the outcome the whole lock-aware policy exists to prevent; disengaged on a
healthy session
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
The rule above is stated for reads and breaks quietly for writes, because the
three actuators *look* async: `func setVolume(…) async throws` whose body is a
straight-line Core Audio or dlsym'd C call, with no `await` anywhere in it. Such
a function never suspends — it runs to completion on the thread that picked it
up — and since a nonisolated `async` function hops off its caller's actor onto
the global concurrent executor, that thread is a cooperative-pool thread whether
the call came from `Task.detached` or from `Task { @MainActor in … }`. So a write
path of that shape is the exact pool-starving orphan the read rule exists to
prevent, even in the file that states the rule. All three legs measured
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
Mechanical backing is refused on a measurement (2026-07-31): SwiftLint's
`async_without_await`, enabled under the strict gate, produced 31 hits — every
one a conformance whose protocol forces the `async` keyword (`isAvailable()`,
actuator commands, and their mocks), zero real findings. The rule cannot tell a
forced signature from a chosen one, and 31 scattered disables would teach readers
to ignore the marker, so it stays off, with this measurement recorded beside the
opt-in list in .swiftlint.yml. Reviewing "is this async?" stays a reading of the
body, and this entry is where the shape to look for is written.
The AVAILABILITY guards of the brightness sources fall under the same rule:
`PolledBrightnessSource.isAvailable()` is a straight-line border call behind an
`async` signature — on the keyboard channel, an enumeration of the backlight IDs
over the private client's connection, IPC that can hang. It hops through
`blockingCall`, and onto the GLOBAL pool rather than that channel's
serial queue: availability records no value, so it needs no ordering against the
readings and must not park behind a stalled read.

### child-process-deadline
Every one-shot subprocess interaction is time-bounded: waiting on a
`terminationHandler` with no deadline is waiting forever: without the deadline,
one hung child stalls the entire now-playing chain selection. The pattern is a pure, testable
race (a deadline over `SleepClock` + single-resume) plus a thin edge that on
expiry `terminate()`s and escalates to SIGKILL — the child is abandoned and
killed, never awaited.

### promotion-quiet-boundary
The now-playing chain fails over adapter→JXA on outage, and a one-way failover
makes JXA a sticky terminal state for the whole session even after the adapter
recovers. Decision: while a lower-priority source is active, a periodic
read-only probe (30 s) re-checks the higher-priority candidate and preempts it —
promoting at the next quiet boundary (a silent source is forced to a boundary so
the swap never strands a live snapshot).

**An answer that outlives its own forwarding arms nothing.** The
promotion probe asks about availability through a call that can take its time — in
production, spawning a child process under a deadline — and the answer can come back
AFTER the forwarding that created it has ended. The `cancel()` on the forwarding's
way out does not cover that: it reaches a task already past the point where
cancellation is observed. A presence guard (`activeSource != nil`) lets such an answer
arm a promotion on whatever source has been selected next — and if that source is
priority 0 (nothing above it to promote to) and still silent since selection, the
"boundary c" path STOPS it: a fresh source is killed the beat it is chosen, ghost
discard fires, one spawn/kill cycle is wasted and the re-selection backoff comes on
top.
Every selection bumps a `selectionGeneration`, each probe carries the generation
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

Everything armed on the snapshot goes with it, the appearance under a HUD
included: the revert brings back whatever appearance the layers hold
(card-hud-placement), so one kept past its snapshot would come back showing the
next. The usual sequel to a discard — a browser stealing the focus, a chain
failover, the browser filter being switched back on — is now-playing landing on a
paused app, which earns no appearance of its own; a kept one would open a card by
itself about a second after a volume key, over media the user never played. The
REPLACEMENT case is deliberately not the same — a snapshot that merely changes
identity under the HUD updates the appearance in place, as it would with no HUD
up: that is parity with the no-HUD path, not a stale appearance.

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
(the flat end is a deliberate deviation — see the curved fill below) — not the
system's *control*, whose pill thumb is exactly the misalignment this entry
answers; owning the drawing also removes the exposure behind it
(Apple restyling the stock control underneath us). The capsule sits centered in
a 16 pt hit row (the stock Slider's measured height): the drag target does not
regress and no surrounding layout moves. A knob (17.5×14 pt, the measured
native size) appears **only under the pointer**. A "no knob" deviation rests on
a transient HUD; the knob's premise is a HUD that stays while hovered, so the
hold comes with the knob to make the knob's premise real — the pointer's arrival
cancels the HUD revert timer and its exit restarts the full delay
(`Coordinator.publishPointer`), so a hovered HUD is genuinely not transient —
precisely when the affordance matters, and exactly the Control Center's own
affordance-on-demand. Only a mouse event is that arrival: the sample a surface
takes when it is armed or retargeted under a still cursor records the pointer
and holds the appearance, never the HUD, or a HUD rising under a resting cursor
stays up until the mouse moves; the first mouse event that finds the pointer
there hands it the hold (`SurfaceHoverMonitor`, `movedPointerSurfaces`). The knob signal is per display
(`SurfaceDisplayPolicy.pointerInside`): only the hovered surface reveals it,
and an active drag keeps it. Scope: the knob belongs to the capsule
(Notch/Card) and to the now-playing scrubber drawn on the same track (below);
Classic renders the pre-Tahoe bezel's 16-segment bar filled by width (its
reverse-engineered identity — measured in design-reference.md, which lives in
the git history) and stays bare.
Two rules fix the fill and the knob: (1) the fill's end is
CURVED — a capsule, not the native flat cut — a deliberate deviation by
author taste (the iOS Music/players language); the fill length floors at the
4 pt thickness so a low value reads as a circle-capped nub, never a squashed
oval across the track, and exactly 0% stays empty. (2) The knob does not clamp to
the fill boundary: a boundary-clamp mapping freezes it for the last ~half-knob
of travel at each extreme while the value and the fill keep following the
pointer — the jam seen on hardware at 0/100%. It travels the inset
track [halfKnob, length − halfKnob] linearly with the value (the native thumb
mapping); the fill boundary never escapes the knob's own body
(|boundary − center| ≤ halfKnob), so the capsule still reads as one piece.

**The now-playing scrubber is drawn on the capsule too.** The stock `Slider`,
on the reasoning that a precision gesture wants a permanent grab handle, is
refused: beside the HUD the two bars read as a mistake rather than as two
decisions — the HUD thumbless and white, the scrubber carrying an always-visible
thumb and a fill tinted with the artwork accent. The author's rule for it is
this entry's own — no tip at rest, one on hover, white.

So the drawing lives in `CapsuleTrack`, shared by both, and the reasoning
inverts rather than disappears: the grab handle is still wanted *during the
gesture*, and hover plus drag is exactly when it is there. What the scrubber
gives up is a handle at REST, which is not precision — it is clutter on a
surface that spends its life not being dragged.

One difference stays, and it is not drift. The HUD's knob follows the
per-surface pointer signal (`SurfaceDisplayPolicy.pointerInside`), because
hovering a HUD holds it open and the affordance belongs to the whole surface.
The scrubber's is LOCAL to the row: it sits inside a bigger card that hover does
not hold, so the honest question there is whether the pointer is on the BAR —
which is also what Control Center does.

### card-hud-placement
Where the Card's HUD sits is a rule of its own: the top centre it shares with the
now-playing card, where it morphs from that card, or one of seven places on the
screen's edges (`HUDPlacement`). One rule places all eight
(`CardStyle.hudFrame(at:on:)`), and the top centre IS the card's `.hud` frame — the
frame rule asks the placement rule rather than keeping a second description of
that spot. Along the top edge the HUD hangs from the card's own top anchor, below
the safe area; along the bottom and on a side it keeps `hudEdgeMargin` from
where the Dock ends. The Dock's room on each edge is the gap between the screen's
frame and its visible frame (`ScreenGeometry.dockRoom`), read at the border on
every topology pass, which `didChangeScreenParameters` starts when the Dock is
shown or hidden, moved to a side or resized (measured,
scripts/probes/dock-visible-frame.swift); a Dock moving between displays is
unmeasured. A change to the Dock's room alone rebuilds only the panel that reads
it (`PanelSurface.readsTheDock`). With the Dock hidden the bar rests that margin
from the bottom edge, and the Dock revealed on hover passes over it as over any
window. The bottom margin is the sides' own, not the native OSD's height that
Classic keeps (`ClassicMetrics.bottomMargin`): that height suits Classic's
square, and leaves a thin bar floating over the apps.
Placements are places on the glass — left and right do not swap under a
right-to-left interface.

**The place is chosen in a native pop-up, and the real HUD previews it.** Settings
offers the eight places as a labelled "Position" pop-up (`HUDPlacementPicker`), the
control every verified OSD-position setting uses (BetterDisplay, Windows 11,
PowerToys), in three groups split by dividers: the top edge, the middle of the
sides, the bottom edge. Each item wears a template icon drawn in code
(`HUDPlacementIcon`): a screen outline with the bar where the Card's own rule puts
it on the reference panel (`StylePreview.hudBar`), magnified only in size and
keeping its share of the room around it, so a corner stays a corner and a side's
bar stands upright. The icon is a hint; the truth is the HUD itself. On a choice,
the real volume HUD shows once at the new place (`AppCore.previewHUDPlacement` →
`Coordinator.previewHUD(on:)`) and reverts on the HUD's own timer, so the margin
and the bar's direction are seen rather than pictured. The level is the output's,
read at that moment (`VolumeReading`) and never written. It goes to every display
drawing Card and to no other (`PresentationLayers.hudDisplays`): those are the
displays the placement governs, and the Settings window's own display is not a
fact the core reads. Nothing is shown while the screen is locked or the session
is off the console. A reported HUD arriving over the preview — a drag on its bar
included — is drawn wherever its target puts it, like any other.

**The bar runs along the edge it sits on.** Flat along the top and bottom edges,
corners included; upright in the middle of a side (`HUDPlacement.axis`). Upright,
it is the same strip transposed (`CardMetrics.hudSize(for:)`), never a second
declared size, and it fills from the BOTTOM in every language: a level rises, it is
not read. So the track has an axis rather than a rotation (`CapsuleTrack.axis`,
threaded through `HUDLevelSlider` and `CardHUDIndicator`): rotated, the knob's
shadow would point sideways and the drag would depend on rotated coordinates; with
an axis, the shadow stays light-from-above and the drag reads the y it means.
Every axis-dependent choice is asked of the track, once: the bar's start as
coordinates (`CapsuleTrack.runsReversed` — the far end of the view's own axis,
the leading edge under right-to-left, the bottom of an upright bar) and as layout
(`startAlignment`, `startEdge`), which side of a size or a pointer is the length
(`length(of:)`, `coordinate(of:)`), and the knob's transposition (`knobFrame`).
The pointer→value mapping lives once on the track too (`CapsuleTrack.fraction`),
and both bars drawn on it, the HUD level and the scrubber, map their pointer
there. Upright, the glyph sits under the bar in a row
of the same fixed slot (`CardHUDIndicator.hudIconSlot`), centred across it; the
filled bar's glyph keeps the same inset from the bar's start, equal to the
corner radius, which clears the corner curve in both orientations because the bar
is equally thick either way (`inner-corners-are-concentric`). Classic's segmented
bar has no upright form: it runs horizontal whatever axis it is handed.

**The HUD and the now-playing appearance are two layers.** A HUD placed off the
top centre is drawn on a surface of its own while the card stays where it is, so
the Coordinator holds the two apart (`PresentationLayers`), and `state` is what a
surface drawing both shows: the HUD over the appearance. A HUD rises over the
appearance without taking it down; the appearance keeps taking events under it
exactly as it would with no HUD up, the linger it owes included, and only its tuck
waits: no linger runs while a HUD is up, wherever the HUD is drawn, so the
appearance has one lifetime whether or not something covers it, and the revert
arms the tuck again. A transition that moves both layers is one write, because the
WindowManager's frame pass runs inside it. A pointer event names the surface it
came from (`PresentationLayers.Surface`) and reaches only the layers that surface
draws: on a surface drawing the HUD alone it holds the HUD and expands nothing; on
one drawing the appearance alone it never holds the HUD. The pointer is a set of
surfaces, because two panels report their exit and entry in either order, and a
surface a dismissal leaves empty lets go of its pointer, since ordering a panel out
reports no exit. The notch's debounced hover names no surface: the notch draws
both layers on one.

**A panel per surface.** A display drawing Card with the HUD off the top centre
gets two panels, the card's reading the appearance alone and the HUD's reading the
HUD alone (`PanelSurface`); every other display keeps one panel drawing both. The
HUD's panel draws the Card's own view, so the HUD is the Card's drawing and only
where it sits is a rule of its own (`CardHUDStyle`): its fixed window hangs the HUD
from its top edge exactly onto the placement, with the overshoot headroom every
skin has. Each panel's hover names its layers, so a pointer on the HUD holds the
HUD and a pointer on the card never does. Moving the HUD between two places off the
top centre rebuilds only the HUD's panel; moving it to or from the top centre swaps
one panel for two or two for one, and a geometry change rebuilds both, since each
panel captures geometry at creation.
A click on the card's empty spot invokes nothing on any Card panel (the floating
skins have no invoke zone), so a HUD up elsewhere changes nothing there. The card
shown beside a HUD keeps the one lifetime above: it does not tuck while the HUD is
up, a HUD held under the pointer included. Letting it tuck on its own schedule
would make the Coordinator's timers depend on how each display arranges its
panels — on a display drawing both layers on one panel, the tuck would take the
appearance the revert brings back — and the rule's cost is a card that stays while
the user adjusts a level beside it.

### hud-fixed-dark-palette
Every skin commits to one fixed dark palette, its ink drawn for a dark surface in
every state and under either system appearance: Card and Classic pin `.colorScheme = .dark`
**enclosing** `vibrantSurface` (the environment reaches the AppKit-backed
material; one level lower it would darken only the ink over light glass), with
the `NSVisualEffectView` appearance also pinned as belt-and-braces — the same
commitment the notch's opaque black always made. Rationale: the hudWindow
material follows the window appearance (measured: light frosted glass under
aqua), so a system-following surface renders per-style inconsistency (Notch
dark, the rest light) and inactive-gray control chrome in a never-key panel;
and an appearance scoped per branch would flip the palette mid HUD↔now-playing
morph — one appearance per surface, always. Consequence: the artwork accent
needs a single brightness band (there is no light band). The Card's surface on
macOS 26 and later is the one exception to the DARK body, not to the palette:
its indicator's glass turns pale over a pale page while the ink stays white
(the-card-is-glass).

The material alone does not hold that commitment over a bright desktop: it takes
on what is behind it, and over a white page it turns light grey, leaving the
white ink under the 3:1 a UI element needs. So Card and Classic lay a black film
over the material (`SurfaceChrome.scrimOpacity`), set so that worst case keeps
the ink at 4.5:1 or better; over a dark desktop the material is already near
black and the film changes almost nothing. Liquid Glass was measured as the
alternative on macOS 27 and does not replace it: in a never-key panel it draws no
specular edge and is as light as the material over white, and with semantic ink
it follows the system appearance rather than the backdrop, faint over white and
black alike. The numbers live in scripts/probes/hud-surface-contrast.swift, which
a retune re-runs. The film path stays for Classic and for the Card before macOS
26; the Card on 26 and later took the glass by the author's choice, with the
rim drawn by hand and white ink kept, measured in the-card-is-glass.
Reopening gate for Classic: never-key glass drawing its edge, or semantic ink
reaching 4.5:1 over both a white and a black backdrop on that probe.

### the-card-is-glass
Beside the system's own volume OSD on macOS 27, the Card read as a different
object: over a white page its film-darkened material sat at a middle grey (#6e)
where the system's glass turns pale (#d1–#d9), and its filled HUD stacked three
darks into a slab. Measured side by side over a white and a black page with
scripts/probes/native-osd-edge.swift (the system's OSD and the Card, each read off
a capture) and scripts/probes/hud-surface-contrast.swift (the Card's candidates,
in a never-key panel like the app's).
Decision: on macOS 26 and later the whole Card draws on Liquid Glass
(`cardSurface`), the slider HUD, the filled HUD and the player alike, and the
author accepts the system's trade where the system makes it.
- The vivid glass the system draws is out of reach. Every public door renders
  flat in a panel that is not key: `glassEffect` plain, `.interactive()`, inside a
  `GlassEffectContainer`, under `controlActiveState` forced to `.key` or
  `.active`; a panel overriding `isKeyWindow`; `NSGlassEffectView`, with
  `effectIsInteractive` too. Only a window that is really key draws it, and a HUD
  that took the key would take the keyboard from whoever is typing. The private
  `set_variant:` stays out. So the Card's polish is the glass's body plus a rim
  and a shadow drawn by hand to the system's measurements.
- The body is `.clear`: #d8 over white and #21 over black against the system's
  #d1–#d9 and #1a–#21, where `.regular` reads #c1, a grey slab over a pale page.
- The indicator's glass is bare: white ink over a pale page at 1.42:1
  (`SurfaceChrome.glassBareInkRatioOverWhitePage`), as the system's reads about
  1.5:1, recorded as an exception to the minimum and held to nothing. A glyph
  and a bar read by their shape.
- Text is not read by its shape. Bare, the player's title read about 1.7:1 over
  a white page and its artist less, so the player's glass is always dimmed by a
  black layer of 0.55 (`SurfaceChrome.glassDimming`): 4.94:1 over white, 19.6:1
  over black, inside the band every ink test holds against. Over a pale page the
  player is smoked glass, still blurring the page, not the system's pale body.
  Under Increase Contrast the indicator takes the same layer, the minimum the
  HIG asks that setting to deliver. A layer, not the glass's tint, which darkens
  `.clear` but lightens `.regular`. The player's glass reaches the outline
  (`glassStop`): cut short, the band showed the page through the layer, a #75
  ring round a #5a body over white. Its rim is the two light strokes at 0.6
  (`glassPlayerRimScale`), the author's taste against the outline the full rim
  drew round a body darker than the system's: over black #2d #17 down the top
  and no ring down the sides, where the full one read #53 #34 #21 and #17.
  Turning the text dark over a pale page, as
  Apple's own glass does, needs the backdrop's luminance, which a never-key
  panel's glass does not adapt to and reading the screen would need Screen
  Recording for.
- The filled HUD's remainder is the glass itself; the glyph keeps its difference
  blend. Under Increase Contrast it takes the film path's remainder again.
- The glass stops a point inside the outline, and its own edge, which it draws
  darker than its body over a pale page (#a5 against #d8 down the sides), is cut
  half a point further in (`glassInset`, `glassEdgeCut`). Flush, its blur rings
  the filled HUD's light corner (#b7 against a #f9 fill).
- The rim is three strokes, each a vertical ramp held dark through the middle
  of the height (`glassRim`): the widest carries the body's tone across the band
  the cut glass leaves, the narrower two are the light. Over black the Card's
  edge reads #66 #44 #2b down the top, #1e midway down the sides and #47 #55 at
  the bottom, against the system's #66 #3f #28, about #1b and #48 #55. A ring of
  even brightness reads as a drawn outline, which is why the light stays off the
  sides.
- A soft shadow matches the one under the system's OSD over a pale page.
Classic keeps the film path by identity: it is the pre-Tahoe bezel, dark and
translucent. Systems before macOS 26 have no glass and keep it too. The Settings
tiles draw every floating surface dark, the film path's look: a tile is a
pictogram of where and what shape, and glass at that size reads as a milky blot
with a bright ring beside two dark shapes.
Reopening gate: a public way to draw never-key glass active, the system's OSD
leaving glass, or a run of either probe moving the numbers above.
### ink-meets-the-minimum
Two inks were calibrated by eye and called legible: the accent's brightness
band (a saturated blue at its floor drew 2.1:1 on the Notch's black) and the
filled HUD's grey glyph (0.5 white comes out near 3:1 on both the fill and the
remainder it rides over). Decision: ink on the surfaces is held to the
Accessibility HIG's 4.5:1 for text and icons up to 17 pt, computed with WCAG
2.2's formulas (`WCAGContrast`) against the background it actually lands on,
and pinned as a worst case in tests rather than a tuning. The accent keeps its
band as character and is lifted, brightness first and then saturation toward
white, only as far as the darkest surface needs; the filled HUD's glyph is
white under a difference blend, inverting whatever the bar lays beneath it,
because no single ink reads on both of its backgrounds. Over a bright desktop
the floating surface guarantees white ink and nothing darker
(hud-fixed-dark-palette), so no tone meets the minimum there by default; Increase
Contrast resolves the accent against that lightest surface, which leaves it
near white, and pushes the filled bar's fill and remainder apart — the higher
contrast scheme the HIG asks that setting to provide where the default does not.
The Card indicator's bare glass is the recorded exception (the-card-is-glass):
white ink over a pale page below the minimum, as the system's own OSD draws it,
and lifted to the minimum under Increase Contrast. The player's glass is always
dimmed to the minimum: text gets no exception.

### scrub-grace
A scrubber whose drag does not own the gesture fights its own stream: every
drag delta fires a real seek (one subprocess per pixel), the 1 Hz ticker keeps
counting from the pre-seek anchor and pulls the thumb back until the
player's echo lands, and PositionReconciliation eats deliberate
sub-tolerance backward seeks as anchor jitter (J4 — the brightness drag's
cousin). Decision: the drag owns the gesture — a view-local
draft shows under the finger, ONE seek fires on release, and a tap seeks
immediately. (The row draws its own `CapsuleTrack` and a tap is simply a drag
with no movement, so `onEnded` carries it and there is no callback order to be
independent of — see hud-capsule-track.) On release the user's value takes
authority: optimistic position write (S7-safe, position-only), the source
re-anchors its ticker (`noteSeek`, a no-op default for sources with no
local extrapolation), and a grace window holds stale echoes off until the
stream itself flows at ≈ the target. Both the display override and the
source hint are bounded by honest exits — confirmation, track change, a
failed command (`noteSeekFailed` restores the pre-seek line), and a
timeout/anchor budget — so neither can ever be left stuck.

### shared-skin-skeleton
A private copy of the non-visual skeleton in each of the three skin views
(~120 identical lines: the layout enum, the empty-freeze rule, per-state
sizes, content derivation and intent passthroughs) lets a fix like the
empty-boundary freeze land on two skins and miss the Notch — and lets the
mirrored test suites diverge the same way (one suite missing two pins its
siblings carry). Decision: the skeleton lives once in
SurfaceStyleCore (`SurfaceLayoutKind` + `SurfaceLayout` + `SurfaceStyleBody`);
each view keeps only its visual body, the provenance @State the freeze
contract binds to, and one-line statics that pin the per-skin Metrics
parameter (which the per-view tests still exercise). A private LayoutKind per
skin is refused; SurfaceAnimation.geometryAnimation keeps its boolean interface
for its own reason: the motion gate reads exactly two provenance facts, never
the enum.

The provenance is one `SurfaceProvenance` value in SurfaceStyleCore, carrying the
advance rule — `previous` follows every kind (an appearance is not a morph),
`lastVisible` skips `.empty` so the fade-out sits on the rect it is leaving — and
the motion gates that read it (`geometryAnimation`, `contentAnimation`) live in
`SurfaceStyleBody`, which requires the provenance and the Reduce Motion
environment read as members. Byte-identical copies are the whole exposure: a
geometry gate held three times and a content crossfade held twice let a provenance
fix land on two skins and miss the third — the exact failure this entry
exists for. What stays per view: the visual body, the
@State storage SwiftUI has to own, and the one-line statics that fix the Metrics
parameter (`surfaceSize`, `effectiveLayoutKind`, the Card's radius, the Notch's
shape), which the per-view tests still exercise.

The exposure this entry names has a second half that is easy to miss — the
PROSE. Swift cannot hoist a stored property or a property
wrapper through a protocol, so every conforming view must redeclare
`coordinator`, `displayPolicy`, its environment reads and the provenance
`@State`; those declarations repeat by construction and are not residue. A
per-view paraphrase is residue — five lines of the provenance rule, three
byte-identical lines of the Reduce Motion gate — because both rules live once
(in `SurfaceProvenance` and in `SurfaceStyleBody`'s member docs) and each view
ALSO documents them concretely at its own `.animation` call site. Three copies
drift into three different claims about the same rule — the hidden surface
"freezes to", "freezes its drop AND its shape flare to", and a third that calls
the surface a block — one of them wrong, with the code the only way to tell
which. So each view points at the rule in one line.
The lesson generalises past this file: a shared rule restated beside every
implementation is the same divergence risk as copied code, minus the compiler.

### hover-follows-the-eye
Hover and clicks derive from the same rendered truth, on every skin. A
state-blind hover exit region — the union of the compact and expanded frames
+24 pt, never retargeted — leaves, with the notch compact or showing a HUD, a
233×100 pt invisible sticky band below the visible surface (measured live) —
and because the monitor reports only transitions, a cursor RESTING there emits
no exit, so no dismissal timer runs: the surface (and a held HUD) stays
forever. So regions retarget on every panel apply and size
report (exit = enter plus a per-edge band) — the apply-time retarget errs
TIGHT, rule frame ∩ last rendered, because the reported size predates the
state change (either stale rect alone re-creates a closed bug: the previous
silhouette holds the stuck band, the bare ceiling re-arms the card's dead
air) — the monitor's event mask includes the mouse-ups (the release re-syncs a
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
unreachable, a production bug pinned by test), and the close spring
tightened 0.45→0.35. Two
hypotheses stay deliberately unimplemented pending a hardware probe: the
multi-display pointer record and mouseMoved delivery to an inactive accessory.

The CLICKABLE region shares the apply-time rule. Taking the frozen silhouette
bare would route a hidden→HUD apply's clicks across the dead margin of the last
visible surface for about a frame — captured and swallowed where the contract
promises pass-through. At apply time
both hover and clicks err tight (silhouette ∩ the state's rule frame); a
fresh size report still retargets both to the rendered truth. Pinned in
`NSPanelPresentationPanelTests`.

A last contract of the monitor itself, invisible without a suite of its own:
disarming reports a PENDING exit. The Coordinator mirrors the pointer from these
reports, so a display that stops being armed with the cursor on it must say so once
— a silent reset leaves the mirror holding a pointer that is on no surface, and the
timers keyed on it never fire again — while a display that never held the pointer
must stay quiet, or the mirror learns a transition that never happened. Re-arming
re-samples where the cursor is NOW (the event monitors exist only while armed),
which is why the disarm clears the inside flag as it reports it. The monitor's
cursor read is a constructor parameter defaulting to NSEvent.mouseLocation for
exactly this: with the real pointer as the only input, a mutation deleting the
pending exit passes the whole suite. The border is otherwise untouched — the NSEvent
monitors stay real (SurfaceHoverMonitorTests).

### signed-without-hardened-runtime
Superseded for the app's own executable by `self-signed-runtime-without-library-validation`: the self-signed app carries the runtime with library validation off. What follows is the record of why validation cannot stay on.
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
plainly readable from `codesign -d`. That CI check fails closed as well: a
missing .app, a `codesign` that refuses (what an unsigned bundle answers), or output
carrying no `flags=` field each end the step with their own message instead of
passing on an empty match — measured, both an absent path and an unsigned bundle
leave the flags string empty, and a check that passes on that goes green, which is
a guard reporting "nothing read" as "nothing wrong"
(docs/DECISIONS.md: J8-a-guard-that-cannot-read). And the project pins
`ENABLE_HARDENED_RUNTIME = NO` in both configurations — YES makes Xcode's own
Product → Archive produce the unlaunchable app, which release.sh escapes only by
archiving unsigned. The key stays explicit: `= NO` is the
exact remedy the CI gate's error names.
The smoke exists because the crash reaches a release build: the v1.2 E2E caught
it before publish. The static gate exists because it reproduces straight from the
project settings (2026-07-29: `flags=0x10002(adhoc,runtime)`,
`TeamIdentifier=not set`, dyld: "mapping process and mapped file (non-platform)
have different Team IDs", SIGABRT).

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
well as on the cooperative pool by the router and the poll. So the reading runs
on the channel's own serial queue (read-deadline-pool-rule; the volume sibling
follows the same lesson) and the window stays on the caller's thread
as `armKeyWindow()`. Splitting them is not tidiness: the window has to carry the
key's own instant rather than whenever the read returns. And because a
key-driven reading emits on any change whether the window is open or not, a
reading in flight is not protected by ordering — so `standDown()`
speaks for the readings the key already asked for, and one that comes back
spoken for degrades to a plain reading (see betterdisplay-osd-source: without
that, a neighbour reporting the same press gets our hardware-scale bar drawn on
top of its own). The launch baseline read is the deliberate exception, once per
process on the constructing thread, because that thread is already blocked far
harder building the backend.

### login-item-intent
The launch-at-login registration lives beyond the Background Task Management
boundary, and macOS revokes it when the bundle's code identity changes —
observed on hardware; Apple does not document the rule — a rebuild, a
reinstall, and, in one stroke for every installed user, a
move to Developer ID. Observed on hardware, the loss is a boot where the app
simply never launches, the system logs nothing at all, and a ghost record lingers
until System Settings prunes it. With the system status as the ONLY source of truth,
the user's choice vanishes silently — the toggle reads off and no one is any
wiser. Decision: persist the user's INTENT (and the build it was made under),
never to act on it, only to notice the loss. The build is what tells the two
authors of "gone" apart — a registration lost across a build change was revoked
by macOS (warn, and offer one click); one lost under the same build was removed
by the user in System Settings (forget the intent, say nothing). Auto-repair is
deliberately rejected: the invalidation is a security signal ("this binary is
not the one you approved"), and re-registering behind the user would contradict
the app's own rule of never adding a login item uninvited. Measured and ruled
out: the DMG's quarantine attribute does not block registration.

Two corollaries, and the reason the write is split from the read. First, the
intent is recorded only by an attempt that
did NOT fail: the build stamp is the discriminator, so stamping a failed enable
with the current build makes the next reading say "gone under the same build" and
file the user's own request away as their own removal — a failed one-click
repair of a revoked registration would erase its own warning, and the app would go
back to not launching with nothing left to say. A failed disable keeps the intent for the
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
placebo here, and another broken instance reinstalled three times without
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
contending — ships alongside it, see `betterdisplay-osd-source`.

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
bar on nor send a drag back to. (Dropping other displays is refused on three
grounds: `hud-target-is-a-role` splits a flattened `DisplayUUID?` into three
roles, so nil never stands in for the built-in; `hud-belongs-to-its-display`
confines a named bar to its own screen; and the way back below gives the drag
somewhere to go.) No preference gates any of this: with
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
any change whether the window is open or not — so ordering alone is not enough
once the read leaves the caller's thread. One press, one bar, whoever
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
stopped at. Those two together set a trap, seen on hardware: the correcting
echo has to carry what the actuator WROTE, never what the caller asked for. The
call that drives the write stays inside the drain loop putting newer values on
the wire while its own argument goes stale, so echoing the argument re-draws the
bar at a level the finger already left — a fast drag flicks backwards for an
instant before the next frame pulls it forward again. Coalescing is what makes
the two numbers differ, so any actuator that coalesces owes its caller the
written value as its return; the argument is only what was asked. And a refusal
is not fatal: the neighbour's command channel is a
SEPARATE setting from its OSD one, so "reports but refuses commands" is a real
configuration — a failed command falls back to the system actuator in the same
drag (a smaller lie than a dead control), stops being asked until the neighbour's
next report proves it is answering again, and never retries mid-gesture.

External displays hinge on a presentation rule, not an actuation one:
`hud-belongs-to-its-display` is what lets their bar be drawn at all.

The menu says which of the two is happening, because the user cannot see the tap
chain: a **confirmation** once BetterDisplay has actually reported, and an
**actionable** line — turn on its OSD notification integration — while it holds
the keys and has never reported. Presence of the app is never treated as evidence
that the integration is on; only a delivered payload is, and that claim is
dropped when the app terminates. The neighbour is matched by bundle ID, never by
the localized name shown to the user.

**The claim is observable.** Evidence-not-presence has a corollary about
WHEN the claim is read. The Settings line reporting it is a body SwiftUI has already
built, and the person reading that line is usually the one about to switch the
neighbour's integration on in the other app — so a claim that only refreshes on the
next open answers "no" to someone who just made it true. `hasReported` is therefore
observable and the line flips with the window open. BetterDisplay quitting with its
integration off is the ordinary case and must rebuild nothing; the @Observable setter
already skips an equal write (`shouldNotifyObservers`), and the write is guarded in
both directions anyway, to keep that intent at the call site. It stays a
plain forwarding read on the way up (`AppCore.betterDisplayIsReporting` is a computed
property over the source): caching it into a stored field anywhere on that path puts
the staleness back.

**The neighbour is heard the way the lock edges are, and the stand-down works
from either side of the race.** First, both registrations on the neighbour's
names (the OSD payload and the command channel's answer) avoid the block-based
cover, whose suspension behaviour defaults to Coalesce — held and collapsed by
the server while the centre is suspended, which AppKit does whenever the app is
not active, and an LSUIElement accessory essentially never is
(`NSDistributedNotificationCenter.h`). The lock edges use selector registration
with `.deliverImmediately` for exactly this, and so does the neighbour: a request
sent `deliverImmediately: true` into an answer registration that can be held is
an asymmetry of our own — a held answer is indistinguishable from silence at the
deadline. Both register through `DistributedPayloadRelay` with
`.deliverImmediately`, so the integration does not depend on how the neighbour
chooses to post. Second, "stand the local key source down when the neighbour
reports" cannot assume an order between the report and the local sample: they
arrive on different executors. A
stand-down that finds no reading in flight BANKS the announcement, and the
next sample inside the key window consumes it (armed then disarmed under one
lock) — stamped rather than counted, because an announcement with no key of ours
behind it is the ordinary case, and an immortal credit would silence an
unrelated later key. Pinned in `BetterDisplayOSDSourceTests`, both orderings.

### the-neighbour-indicator-is-borrowed
BetterDisplay draws its own brightness, volume and mute indicator, and Crema draws
one from BetterDisplay's dispatch, so with both on every press BetterDisplay
handles shows two. Telling the user to switch BetterDisplay's off cures the double
and breaks the other half: with Crema not running nothing draws at all, and the
switch stays off in a window the user may never open again.
Decision: while suppression would be engaged — opted in and the screen unlocked,
the decision `SuppressionLockController` makes — Crema turns BetterDisplay's
dispatch on and its basic indicator off over the request channel, and hands back
exactly what it changed when it stops: the switch off, the lock, the quit
(`NeighbourOSDHandoff`). It is the procedure BetterDisplay's Guide gives a
receiving app ("Third-party app integration", "Coordinate feedback settings
through requests", read 2026-10-18): read and save `osdShowBasic`, `osdShowCustom`
and `osdIntegrationNotification`, enable dispatch, disable the overlays replaced,
restore the saved values on shutdown, and "Do not blindly turn all settings on or
off."
- `osdShowCustom` stays the user's: it carries shortcuts Crema draws nothing for.
- A switch already as needed is neither written nor owed, and one the user flips
  back while Crema holds it is theirs: the hand-back writes only a switch that
  still reads as Crema left it. Every write is read back, since an accepted
  request is not a landed value (the Guide says so too).
- The original reaches Crema's preferences BEFORE the write leaves, because
  BetterDisplay persists the write. Measured with
  `scripts/probes/osd-settings-betterdisplay.swift` 2026-10-18 on BetterDisplay
  5.1.1: `get` and `set` answer in 1–7 ms, and a `set` of `osdShowBasic` lands in
  its preferences on disk. A Crema killed while holding finds the debt at its next
  launch and pays it (measured: `kill -9`, then a launch with the switch off
  restored the indicator).
- The quit is held with `applicationShouldTerminate` → `.terminateLater`
  (`CremaAppDelegate`), under which AppKit runs the main run loop in
  `NSModalPanelRunLoopMode` until the reply. The neighbour's answers arrive in that
  mode — measured the same day: an `osascript` quit returned in 0.15 s, and the
  process logged the hand-back, read back, before it ended.
  Invalidating signal: a quit whose log says "did not answer a read of …" while
  BetterDisplay is running.
- Silence ends the pass and keeps the debt; the next edge retries: Crema's launch,
  BetterDisplay's `.launched` (posted once it can answer, which its workspace launch
  is not), a lock change, the switch. No timer, which would keep asking a neighbour
  that is not there.
- With the screen locked the indicator goes back, as suppression is suspended:
  nothing of Crema's draws over the shield, and BetterDisplay's "Traditional OSD"
  style is the system's own indicator. Cost: two writes to BetterDisplay's
  preferences per lock cycle.
- The menu's "turn on Dispatch OSD notifications" yields once the handoff has read
  dispatch back on, since that advice is already followed.

Accepted cost: BetterDisplay's basic indicator also carries the volume of monitor
speakers it drives over DDC, which Core Audio cannot see and Crema does not draw.
The manual instruction carried the same cost; it reopens with external-display
volume (PLAN.md, Phase 2). And a Crema deleted after a crash, before the launch
that pays the debt, leaves BetterDisplay's indicator off with nobody drawing in
its place: the switch is BetterDisplay's and persists by its design, and the
request channel offers no change scoped to the caller's life. An orderly quit,
the usual way an app is closed before it is deleted, restores everything. Reopens
if BetterDisplay offers a setting scoped to the requesting app's life, or a user
is reported left without the indicator this way.
Discarded: writing BetterDisplay's preferences database directly (the Guide: the
running app and macOS cache it); a fire-and-forget restore in `willTerminate`,
which can neither read back nor tell the user's own flip from Crema's.

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

**A queued level carries its screen.** The coalescing outlives the call
that resolved the display — one drive drains the frames that arrived after it — so
a queue holding a bare number sends a frame queued for one screen out under the
DRIVING call's display id. The neighbour is told to dim a display nobody is
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
external's id, and the driving call must not echo it. A display-blind
"last written" accessor is refused: a "last written" with no screen attached is
the same blindness under a friendlier name; the flick lives in the comment over
the return value.

**The echo is not evidence, and an orphaned frame travels with the
error.** A coalescing writer can break the "every level put on screen will be
honoured" promise in three ways, and each is closed.
First, with the drain's exit check and the in-flight reset in separate
critical sections, a frame slipping between them is queued, echoed as
success, and drained by nobody — so the decision to stop draining and the release
of the in-flight flag share ONE critical section, and no frame can sit queued
without a driver and without an error. Second, a coalesced call echoes its value
as a bare success BEFORE anything reaches the wire, and a Coordinator recording
that echo as a confirmed write lets a failed gesture roll the bar back to a
level no display ever went to. The echo stays (contract 1: publish before the
write, or the bar freezes under the finger) but is marked for what it is
(`BrightnessWriteEcho.coalesced` against `.written`), and only a level that
actually reached the wire becomes rollback evidence. Third, when the channel
throws, a newest queued frame that dies silently leaves the fallback writing the
DRIVING call's stale argument — the level a finger passed through, not the one it
stopped at. So the failure extracts that frame under the same lock that
releases the drain and carries it out (`BrightnessWriteFailure.orphan`, value
and display together), and the Coordinator's fallback writes THAT level on the
display it was aimed at; if the fallback also refuses, the bar is marked
unconfirmed and settles on the last real evidence. This is how the failure path
honours the promise the happy path made. Pinned in
`BetterDisplayScreenBrightnessControllerTests` (the exit race, the orphan in the
error) and `CoordinatorNeighbourBrightnessTests` (the fallback writes the
orphan; a coalesced echo alone never decides the settle).

**The echo is not evidence on the way back either.** A guard held only at the
write site leaks one hop later. The app's own echo
is delivered to the bar by yielding it into the neighbour's HUD stream (that
source never reports what third parties set), and it comes back into
`handleHUDUpdate` on the same path as a spontaneous reading — where, unmarked, it
is recorded as one: `confirmedScreenBrightness` takes the coalesced 0.9, and a
coalesced echo still in the pipe when a failure lands revives
`externalBrightnessReachable`, so the next frame hits the neighbour's deadline
again. So a `SystemHUD` carries its provenance (`.reading` or `.echo`): the
Coordinator marks everything it hands to `onBrightnessApplied` for the neighbour
as an echo, and only a reading becomes evidence or recovers a channel — an echo
moves the bar and nothing else. Pinned by the loop test
(`aCoalescedEchoStaysNoEvidenceAfterTheRoundTripThroughTheHUDStream`): the
seam-and-recorder pair with the loop actually closed
through `AppCore.wireBrightnessEcho` and a real neighbour source.

### hud-belongs-to-its-display
The app has ONE state, drawn by every display's panels, so unscoped every panel draws every HUD.
Harmless while nothing names a display — and wrong the moment something does: a
brightness bar for the external monitor, drawn on the laptop, is a control for a
screen the user is not looking at, and its drag would dim the neighbour in
silence. Rule: a HUD that NAMES a display is shown only on that display; every
other panel draws what lies under it, the now-playing appearance or nothing, as
the Card's own panel does while its HUD sits on a panel apart. Hover stays
disarmed on such a panel: the pointer record names surfaces, not displays, so a
pointer on that appearance would hold the HUD another display shows. A HUD that NO screen owns keeps
appearing everywhere, deliberately: volume belongs to the output device and the
keyboard backlight to the one keyboard, so scoping either would move feedback
nobody asked to move. The exemption covers those two channels and nothing wider:
a bare `display: DisplayUUID?` would overload `nil` between "nothing owns this"
and "the built-in owns this" and stretch it over the built-in brightness by
mistake, so `hud-target-is-a-role` splits the field into three and the local
brightness bar names the built-in panel as a role.
A HUD naming a
display that is no longer attached shows nowhere, which is what an unplug between
the report and the frame pass should look like. The decision lives in
`WindowManager.hudIsShown`, beside `effectiveState` and its "show now playing
here" preference in the per-display pass, and reaches the view as
`SurfaceDisplayPolicy.showsHUD`, which `PresentationLayers.state(on:showsHUD:)`
reads for frame and view alike, so presentation scoping
never leaks into the Coordinator: the app's state stays whole and a drag on the
panel that shows the bar still acts on the display the bar names.

### global-style-default
The Settings picker footer says "Changes every display at once", and a writer that
loops over the displays attached at that instant, writing one key per display
UUID (`style.<uuid>`), breaks the promise: a monitor plugged in afterwards has no
key, so it falls to the shipped default — Notch, resolved to Card on a slitless
screen — and the picker offers no way out: it acts on CHANGE, so re-picking the
value already shown is a no-op.
Decision: the picker DECLARES one global style (`declaredStyle`), which is the
fallback of `style(for:)`; per-display keys stay as OVERRIDES on top, and the
declaration drops them, because an override left behind would hold its display on
the style the user just replaced, and a display not attached right now has no UI
to clear it (the sweep, below). Two details are load bearing: the global key is NOT under the `style.`
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

**The per-display picker.** Settings gives every connected display a row of its
own — a style popup whose first item returns that display to the declaration,
and the "show now playing here" toggle. Four rules hold it.

Inheriting IS the absence of the key. The reset REMOVES the override
(`clearStyle`) instead of writing today's declaration into it: a copy would look
identical this afternoon and then shadow the next declaration forever, which is
the bug the declaration exists to fix. Clearing a display that already
inherits writes nothing at all — not the key, not the declaration.

A display in front of the user has a row to clear its override, so the sweep
stands on the other half of its reason: an override belongs
to a display UUID, and a display not attached right now is one no per-display
control can reach — `clearStyle(for:)` needs a row, and a row needs a display. So
declaring for all displays drops every override, and the consequence is visible:
that footer NAMES the sweep (the deictic wording below), and says it only when a
per-display style actually exists, since a warning about nothing teaches the
reader to skip footers.

The row asks the SAME resolver the panels render by (override else declaration,
`Preferences.style(overrideRawValue:declaredRawValue:)`) rather than reading its
own key alone — a second copy of that rule is how a row comes to name a style its
screen does not draw.

Two mechanics are load bearing. A display's NAME is not an identity: two identical
monitors report the same `localizedName`, so a row is LABELLED by the name and
KEYED by the UUID (and the built-in panel is labelled in the app's own vocabulary
instead of AppKit's). And the panel rebuild predicate never takes the whole
description (the predicate itself: docs/CONTRACTS.md, W4) — a display renamed
under a live panel keeps that panel and its hover regions, since neither derives
from the name; rebuilding on the description would tear a live surface down for
a string.

**Both scopes are asked in one pane.** Style asked in two tabs (one declaring
it, another overriding it) reads in the field as two settings instead of one
asked at two scopes. So General leads with the declaration as a "Style" section
(its one row reads "All displays") and puts the per-display list as an "Each display" section immediately under
it — the pane a person opens first is the pane where style is asked at both of
its scopes, and the sweep its footer warns about is visible in the same pane as
the thing swept. Where it is asked is address, not rule: the same
`declaredStyle` key, `setStyleEverywhere`, sweep and resolver. The menu bar's
Style submenu is the global shortcut, and the welcome tour keeps its own copy of
the declaration.

The per-display style is a POPUP of names whose first item is "Follow all
displays", not a row of thumbnails, and there is no separate "Use the
all-displays style" button: inheriting is one of the options instead of a button
beside them (the write is `clearStyle` — inheriting IS the absence of the key).
Three pieces of provenance choose that shape, recorded so taste does not undo
it: the platform asks this kind
of choice with an inline pop-up button in the row (System Settings' Sound pane is
full of them, and the HIG's pop-up button guidance is written for exactly that
position) and reserves pictures for the choice a pane is ABOUT; a list of rows is
offered only where there is more than one thing to arrange, which is what System
Settings' own Displays pane does with Arrange; and a dropdown is the quieter
control — the long-standing usability finding against it (it hides its options;
Nielsen Norman Group's line on dropdowns has not moved in twenty years) is a cost
where the choice is primary and exactly the right demotion where it is not. The
declaration keeps the pictures; the override gets names.

The reset is STRUCTURAL rather than conventional. `write(for: nil)` is
`.clear` unconditionally — never `.override(declaration)`, not even when the
declaration names the style this display already carries, which is precisely the
case where writing it back looks identical this afternoon and then shadows the
next declaration forever (pinned by
`DisplayStyleOptionsTests.pickingInheritClearsTheKeyEvenWhenTheDeclarationNamesTheSameStyle`).

One asymmetry inside the list is deliberate: inheriting is always ENABLED, even
on a screen that cannot draw the declaration it falls to, while a style that
screen cannot draw is offered disabled. A display can END UP on a style its panel
does not honour, by inheriting one; it may never be PUT there here. Refusing to
inherit would be refusing the one answer that exists for every screen whatever it
draws.

And the list is gated by `DisplayStyleOptions.listIsOffered` — a rule of its
own, because the question is not a count of screens but "is there an answer per
display that the section above cannot give?". The answer is yes for every
non-empty roster: the row is the app's ONLY switch for the now-playing surface,
and the switch's default is a function of the display
(`rendered-style-gates-settings` says why that strands a lone display of either
kind). An empty roster answers false
rather than subscripting.

The sweep footer is deictic — "This also replaces the per-display styles
below" — and it may point down, because whenever there is a display to carry an
override there is a list under the footer to show it: wherever that sentence is
drawn, the section it names is drawn under it — an implication, not a
coincidence, and pinned as one
(`DisplayStyleListOfferTests.anOverrideAnywhereGuaranteesTheListThatShowsIt`).
The welcome tour makes the same declaration with no list beneath it, and
therefore carries its own wording (`tour.step.style.replacesPerDisplay`) rather
than sharing a string that would have to lose the pointer to be true in both
windows.

Each row is headed by what that display DRAWS: a thumbnail
(`StylePreview.shapes(for:on:)`, which resolves before drawing — see
`rendered-style-gates-settings`) and a caption in words
(`DisplayStyleOptions.caption`), "Using Card, since this display has no notch" where the style in
force does not fit the panel. The popup names the CHOICE and the row says what is
on screen beside it, never in a note correcting the control; that is why the
inherit item names no style — naming the declaration puts "Notch" over a screen
drawing Card. The thumbnail is 60 pt wide, the tiles' picture with the same point
floors, and its condition is the pane's height: a two-monitor General tab stays
unscrolled.

**The Card's indicator sits beside the style, as pictures.** With style asked in
General, the indicator belongs next to the displays drawing the style it is an
indicator FOR, not in an Indicators tab as its "thematic home".
It has a Section of its own after the display rows (`CardIndicatorSection`), and
its footer names those displays in the rows' own words
(`WindowManager.displays(rendering:)`): under the declaration's tiles, a mixed
setup puts it beneath a selected Notch with nothing saying which display it
serves. It is drawn as two
mini-tiles instead of a popup of two nouns — "Line" and "Filled" name bodies the
reader has not seen, and the whole difference between them is visual, which is the
argument the style tiles above are already made of. The tiles render the REAL HUD
body (`CardHUDIndicator`, shared with `CardView`), frozen at
one reading and at the SAME reading in both: a hand-drawn likeness would be a
second description of the indicator, and two levels would let the eye read the
difference between the bodies as a difference in loudness.

No cross-tab footer: "Applies to the Card style, which is chosen in the General
tab" pays only for distance — a control and the picker governing it a tab apart,
with a sentence as the only thing carrying a reader between them — and in the
picker's own pane there is none to pay for. Same rule as the sweep footer in the
other direction: a footer that restates its neighbour teaches the reader to skip
footers. Adjacency says it again, which is what adjacency is for.

The choice itself is the same `hudIndicatorStyleKey` the panels read and the
same `setHUDIndicatorStyle` applying it live, held by the pane that draws the
tiles. The gate's shape is the row's existence, not its enabledness
(`rendered-style-gates-settings`).

**The picker's seed reads the declaration key, never the leading display's
answer.** Seeding the all-displays tiles (and the tour's) with the leading
display's RESOLVED style lets that display's own override show up selected in the
control that speaks for every screen — the tiles claim a declaration nobody made,
one row above the row already reporting the override as that display's own,
while the menu's Style submenu, bound to the raw key, says the truth. Rule: every
surface of ONE declaration reads the ONE key (`Preferences.declaredStyle`); the
reader is named `declaredStyle()`, never a "current" that geometry or overrides
could bend. The authority order has one reader, the upgrade adoption above.

### rendered-style-gates-settings
A Settings gate on the DECLARATION — the Card-only indicator picker under
`.disabled(style != .card)`, where `style` is what the all-displays picker
holds — misreads the screen. What a display
draws is that declaration put through one fallback — the notch skin needs a
physical slit, so notch renders as card wherever `safeTop <= 0` — and the shipped
default declares notch. So on every Mac without a notch (mini, Studio, iMac, older
Air) and on any external-only or clamshell setup, the app draws the Card HUD on
every display in the DEFAULT state while such a gate grays the one control over
that HUD's appearance, the only escape being to pick "Card" explicitly: the style
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
declaration reader keeps its own name (`declaredStyle()` — what the picker seeds
from; `global-style-default` records why the seed never reads a resolved
"current" style), so the two questions stay impossible to confuse at the
call site.

**The third reader is the picture.** `StylePreview.shapes(for:on:)`
resolves before it draws, so a tile asked about a named display shows what that
display would really put on screen: the Notch tile on a slitless panel draws the
card — floating, no slit, not opaque — instead of promising hardware the Mac does
not have. A notch promised in a thumbnail is the same lie it would be on the
panel. It also means the notch rule's own `safeTop > 0` guard is never reached
through this path, which is exactly the shape this entry asks for: one mapping,
every reader asking IT. The per-display popup reads that same resolver as a
yes/no — `DisplayStyleOptions.isEnabled` is `Style.isHonoured(on:)`, which is
`resolved(on:) == self` — so a style cannot be offered enabled on a screen that
would silently swap it out. `StylePreview.shapes(for:on:)` is what each
per-display row draws, with that row's own screen, so the resolve-before-drawing
rule reaches Settings through it.
Drawing per display yields one measured number worth keeping: a slitless
display's menu bar is 24 pt, against the 32 pt safe area a notched panel reports
(that panel's real bar is 37). The preview needs a bar for the surfaces to have a
top edge to sit under, and a slitless screen reports no safe area at all, so that
24 is declared rather than derived — without the floor, the tile for every Mac
without a notch loses the top edge where the whole difference between these skins
lives.

**The same gate, the opposite chrome — the indicator row is ABSENT where nothing
renders Card.** The predicate is the one above: `AppCore.rendersAnywhere(.card)`,
an ANY over the panel roster, re-read immediately after the declaration is
written. Its "no" is absence, not a disabled row. Visible-and-disabled — the
macOS dependent-setting pattern — pays for DISTANCE: when the control that could
turn the gate true is a tab away, a row that simply vanishes leaves nothing to
reason about, and a greyed row named for what it governs plus a footer pointing
at the other tab is the cheapest honest report. The
row sits in the same pane as that declaration, after the display rows whose
thumbnails show what each display draws (`global-style-default`), so the answer to
"why is there no indicator row?" is drawn above the space where it would be, and a
pick that starts a display drawing Card makes the row appear at once — live, off
the mirror this pane re-reads after every style write.
Visible-but-disabled buys nothing once that distance is gone; it spends a row on a
control nobody can use.

The residual is the seed-once deal of S4 (the tradeoff
`one-screen-reading-per-edge` names when it explains why the per-display list does
NOT take it): the mirror is seeded when the pane is built and re-read after every
style write in the pane and every roster change, so a style picked from the menu
bar's Style submenu with the window open leaves the row on the previous answer
until Settings is reopened. The list next to it is reactive because its rows ARE
displays; this row is not a display, so it keeps the cheaper deal.

**The per-display list is offered for every roster that is not empty.** A
narrower gate — two displays, or a sole external, or an override somewhere — on
the reasoning that a lone built-in panel's row would only repeat the declaration
above it, sees the style popup and misses the switch beside it: the row is the
app's ONLY control for the now-playing surface, born from
`defaultShowsNowPlaying(isInternal:)`, which is literally `isInternal`. Such a
gate covers the sole external (born OFF, nothing else turns it on) and not its
mirror — a sole internal panel, the most common Mac there is, born ON with
nothing in the app able to turn it off. Both
directions strand the user without a row, so the only roster that answers no is
the empty one, which is a real state (Settings open across the last display
going away), not a corner to trap on (`DisplayStyleOptions.listIsOffered`, pinned
in `DisplayStyleOptionsTests`).

### sample-dont-integrate
A UI ticker that adds a fixed step per tick is a clock that runs slow. Timers are
not real time — they fire late under load, App Nap, battery coalescing — so a
1 Hz tick doing `position += 1` per delivered tick permanently loses every late or
dropped tick's playback time from the bar.
Measured: with music playing, the adapter emitted ONE payload in 20 s (players
register elapsed+timestamp on state changes and never re-report during steady
playback), so nothing re-anchors the display and the error accumulates for the
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
bar follows whatever clock it reads, so reading the wall clock lets an NTP step
correction or a manual time change move the bar with it — backward, undoing
playback already shown, and forward, throwing it to the duration clamp until the
next payload (which this adapter only sends on a state change). Every anchor is
stamped with our own reading of that stopwatch when it is installed; the payload's
own timestamp is folded into the position before then, so the wall clock is not
part of the tick's arithmetic at all.
A FLOOR at the position already shown is the refused alternative, recorded
because its reasoning is what makes the current answer legible rather than
lucky. It can only stop the backward half of a wall-clock step, and it needs a
`rate > 0` exception so a rewind scan can still walk the bar back. Any floor has
to get two things right: floor the SHOWN line and never a high-water mark (a
remembered maximum strands the bar above the truth after a legitimate backward
re-anchor — an accepted payload, a seek, a failed seek's rollback), and keep the
origin fixed instead of re-anchoring on the backward edge, because moving the
origin is exactly what makes a tick accumulate again and lets a noisy clock
ratchet the bar forward. The monotonic stopwatch is smaller and covers both
directions: read a clock that cannot lie. The `max(0, …)` in the source is a
clamp, not that mechanism, and its comment says so.

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
`hardwareBrightness`. And a relative write is the documented `offset` parameter
(BetterDisplay wiki, "Integration features, CLI", a page the vendor marks legacy,
read Oct 2026; it also documents the feature-as-parameter-key syntax) —
`{"set", {"brightness":"-5%","offset":""}}` → `result=true` — not a sign on the
value, which is read as an absolute (a probe sending `+0.0625` set the monitor to
6.3% and looked like it had been accepted as a delta).

This entry rules over an earlier reading that claimed the opposite. Asked through
`identifier` — the metadata door — five measured spellings of brightness are all
refused, and reading that as "the neighbour can be written but never read" costs
more than a wrong sentence in an anchor, a public roadmap item or a code comment:
it retires a feature. "Brightness keys follow the screen you
are working on" looks impossible on that reading, because stepping needs a
`before`. There is one, so the apply-verify cycle can run against an external
display like any other; building it is the open work.
Decision: an integration's own documentation is a primary source and gets read
BEFORE a refusal becomes a limitation. Five failures in one category are evidence
about that category, never about the platform — and a vendor wiki is one search
away. When a measurement says a neighbouring app cannot do something
its docs describe, the null hypothesis is that we are asking wrong.

### automation-is-fallback-only
A permission the app requires and never names strands the user. The now-playing
chain is adapter → JXA → off, and the JXA elbow spawns `osascript` against
Spotify/Music, which needs Automation (Apple Events) consent — with nothing in the
app reading that state, mentioning it, or offering a way to it, and a Permissions
tab covering Accessibility only, a user whose adapter has died reads
"Accessibility: Granted", sees "Now Playing unavailable", and has nowhere to go.
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
"unavailable" warning, which carries the trail to this tab and names the same
concept ("backup reader") the tab does. Second, cost: the read is a blocking round
trip to the consent daemon per player, so it is polled only from the Permissions
tab's lifecycle edges — and the observable it writes is read ONLY by that row, never
the menu, whose body also reads `CGGetEventTapList` (which zeroes the min/max
latency counters of every tap in the system), so a state changing on a 2 s poll
would re-run that read on someone else's dime. Scoping to a tab is as strong as
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
question gets its parent's grant back. If that attribution ever changes, the row
reports a state unrelated to the fallback's real luck.

**The badge column belongs to the permission the app requires.** The tone rule
above — a fact in the neutral style, never the warning orange — binds the symbol
as much as the words, and a symbol beside the optional row says it wrong in
both directions: a REFUSAL of the optional permission draws a harsher mark (a
cross) than the REQUIRED permission's warning triangle, and the resting state of
a Mac with no music app open draws a question mark against a machine where nothing
is wrong. So the optional row states its fact in words and carries no glyph at
all, the way the other optional integration reports "Receiving" one tab
over. Without the glyph nothing ranks the two sections, so the ranking lives
in a word — the section headers say Required and Optional — which survives a
screenshot, greyscale, and colour blindness, none of which an orange-versus-grey
ranking does. The one badge in the window sits on the required permission,
always above a button that fixes it. And where a symbol does stay, the colour
lives on the SYMBOL and never on the word: tinting a whole Label puts the line
people open the tab to read at roughly 2.2:1 on a light grouped row, which passes
a review done only in the dark appearance, where it looks fine.

**A guard checked before an await says nothing about the world after
it.** "The read stands down while the dialog is up", enforced only at the entry of
`refresh()`, does not hold, because the blocking read hops off the actor: a pass
already in flight when the user clicks is past that guard, and it resumes into a
last-writer-wins merge carrying the answer it took before the decision existed —
putting `undecided` back over the grant the user just gave. Re-checking `isAsking`
on the way back does not close it either, because the ask clears the flag before
recording its own answer, so the resumption sees a quiet monitor. The rule is a
generation counter bumped when an
ask BEGINS — every read already in flight was taken of a world where nobody had
decided — and compared when the read returns; a read from before an ask is dropped,
and the poll re-reads within its interval. Pinned by
`aReadAlreadyInFlightWhenTheDialogIsAnsweredCannotUndoTheGrant`, which parks a read
across an ask that starts and finishes.

### menu-status-before-warnings
The menu bar extra is a native menu (`MenuBarExtra`, menu style): the HIG asks a
menu bar extra for "a menu — not a popover" unless the function is too complex for
a menu, and this one carries a switch, a choice, a few facts and the app's
commands. Its order and gating are decided in one pure place, `MenuStatus`, and
pinned by tests rather than resting on the shape of a view body.

**The shape is sections, in a fixed order**, each ABSENT rather than empty when it
has nothing to say — an empty section still draws its separator, over nothing:
- **Indicators**, titled with the Indicators tab's own name: the replacement
  switch, then the `Style` submenu. Always present. The feature is opt-in and ships
  OFF, so without the switch a fresh install's menu never names the headline
  feature; and a real `Toggle` is the one place a checkmark belongs, the way Wi-Fi,
  Bluetooth and Sound lead with theirs. The declared style is the checked item of
  an inline Picker in the submenu, which says it AND lets the user change it there.
- **Warnings**, untitled — each one names itself, and a heading over them would be
  a second alarm.
- **Now Playing**, titled with the Now Playing tab's name, only while a track is
  named.
- The app's own commands — Settings and updates, then Quit — untitled, like every
  app's commands at the foot of a menu. They stay outside `MenuStatus`: nothing
  gates them, and the update items exist only in Release, so a case for them there
  is one the Debug-hosted suite can never reach.
Separators come from the sections, never from a `Divider`: beside a section's own
separator a `Divider` doubles it. Section titles reach AppKit's
`NSMenuItem.sectionHeader(title:)` (macOS 14) through a SwiftUI `Section`
(measured on macOS 27: `scripts/probes/menu-sections-and-subtitles.swift`).

**A fact is the subtitle of the control it qualifies.** A fact on a line of its own
reads as a disabled item — grey in a menu means unavailable — and sits apart from
the control it explains. So every `Row` has a `Host`: what the replacement covers
goes under the switch, the style fallback under the Style submenu, at most one per
host. The rows' own rules:
- **A row is a fact, never a wish.** It is gated on the feature being in effect: the
  brightness rows speak only while Crema is the one applying the key — preference
  AND suppressor AND permission AND no suspended domain, the `cremaApplies` gate —
  and where Crema does not apply, the row says nothing rather than aiming a line at
  someone else's work.
- **A fact another surface already states is not news here.** What the user reads
  on a control (General's "Open Crema at login" checkbox) or in a sentence Settings
  states unconditionally (the pointer scope under the Indicators tab's switch) gets
  no row: a permanent note on a healthy Mac teaches the reader that these lines are
  decoration. On a healthy Mac `rows` is empty — the common shape.
- **The style note reports what the displays DRAW.** On any Mac without a slit the
  shipped default declares Notch while every panel draws Card; a checkmark states
  the declaration and cannot say that nothing honours it
  (`rendered-style-gates-settings`).
- **The neighbour reporting is status, not a warning**: it is the arrangement the
  app asked the user to make. The brightness target is status too
  (`brightness-key-target-in-the-menu`), and `.builtInAmongOthers` maps to NO row —
  telling a Mac that HAS a built-in display that Crema cannot control screen
  brightness is false, not merely redundant.

**A warning with a repair IS the repair.** The button is the item and the fact is
its subtitle, so no sentence sits apart from the button that answers it; a warning
with no repair is a disabled item whose subtitle is what it costs. The menu builds
every warning from `Warning.item` — an exhaustive mapping to a repair or a fact —
so a repair cannot end up under a fact it does not fix. `.nowPlayingUnavailable`
walks to the Permissions tab (`.openPermissionsTab`): not a repair, since nothing
in this app revives a dead media source, and its line states the requirement — the
backup reader needs Automation — never a verdict. **Warnings are ordered by
urgency, and the order is the contract**: Accessibility first (without it no media
key arrives at all, and the chain reading cannot even see us), launch-at-login
last (it is about the next launch, not this session).

**Subtitles where the platform shows them.** A second `Text` in an item's label
reaches `NSMenuItem.subtitle` (macOS 14.4) — measured for a toggle, a button, a
submenu and a disabled item on macOS 27 (same probe). Apple's documentation for that
property shows the subtitle from macOS 15 and not on 14 for an attributed title, so
on 14 the note is a line of its own (`MenuItemNote`): the same words, a line
longer, a repair's fact before its button.

**No glyphs, in either direction.** "⚠️" carries the meaning the line has to carry
anyway, VoiceOver reads it mid-sentence as noise, and stacked it makes a menu
unreadable. "✓" is worse than decorative: a checkmark in an NSMenu means a CHECKED
item, so a title starting with one reads as a toggle that is on. SF Symbols via
`Label` are out too: a menu-item icon stands for an OBJECT, and a symbol that
silently fails to render leaves the line unmarked anyway.

**Every line has a width ceiling.** An NSMenu is exactly as wide as its widest
item: one 116-character line opens it at roughly 1500 pt (measured in the field).
Every menu line — a title, a subtitle, a fallback line — stays within 72
characters, and `MenuLineWidthTests` holds that against the compiled string tables.
Nothing is centred, and chrome is never truncated: a hole filled from a CLOSED set
is measured at its widest member, never at the empty string — the suspension note
with all three domains named is 70 characters in English and 63 in Portuguese. A
hole filled with EXTERNAL content has no worst case to measure. The track's line is
cut at the ceiling with an ellipsis (`NowPlayingMenuSection.fitted`, held by
`MenuLineWidthTests.aPublishedTitleIsCutAtTheCeiling`); a neighbour app's name
stays data rather than chrome.

**The media section exists only while there is media.** Its gate is the line that
names it (`NowPlayingMenuLine` other than `.nothing`), so neither a title nor a
transport can be built over nothing; a command the player REFUSED greys its item in
place, so the section does not flinch as availability moves (the rule
`TransportControls` follows). That gate stays in `NowPlayingMenuSection`'s body
instead of rising into `MenuStatus`: the type is built in `CremaMenu`'s body, whose
every rebuild pull-reads the event-tap chain, and the media state is rewritten once
a second (`menu-reads-mirrors`). What `MenuStatus` does gate is the chain: with no
source reporting there is no media section at all, on the SAME value
`.nowPlayingUnavailable` comes from, so a transport never sits under the line
saying nothing is reporting.

**Cost.** The status reading touches two things outside the process, and one of
them — `CGGetEventTapList`, behind `mediaKeyChainNotice()` — resets the min/max
latency counters of every tap in the system, neighbouring apps' included. A view
body is rebuilt whenever SwiftUI invalidates it, which is NOT the same as the user
opening the menu, so more inputs mean more rebuilds and, unbounded, more of those
reads. `MediaKeyChainNotice.Cache` bounds them with a one-second **coalescing
window**: a burst of rebuilds costs one reading, and the answer is never more than
a window old. A window and not a set of invalidation edges, though the edges exist
— CoreGraphics posts `kCGNotifyEventTapAdded` and `kCGNotifyEventTapRemoved`
through notify(3) (`CGEventTypes.h`): the cost is in the READ, not in the trigger,
so the reading stays rare and tied to someone actually looking, and subscribing to
the edges would make a neighbour's toggle reset every other app's counters while
nobody has the menu open. The window bounds staleness at one window, and a stale
line here is an ACCUSATION against a named neighbour — the direction
`media-key-chain-contention` says to err away from. Reopening gate: if the read ever
stops being destructive, the edges are named. The neighbour's delivered payload is
a different kind of input, a free local flag that can flip with no notification,
so it is part of the memo KEY rather than of its age. What the window does not buy:
freshness within the window, and any claim about `loginItem.status`, which crosses
into Background Task Management once per rebuild — one reading, through
`menuStatus`, never a second.

### brightness-key-target-in-the-menu
Correct behavior nobody can see reads as a bug: with an external monitor as the
main display, the brightness key dims the laptop panel the user is not looking at.
Crema's screen brightness drives the built-in panel because that is what it is
taught to drive, and nothing shows it unless a surface says so. (The reason is not
a limit of the integration — "the neighbour readable only for writing" is a probe
asking through the metadata door; see `neighbour-features-are-not-identifiers`.)
Decision: the menu names the target, as the note under the replacement switch, and only where
the row is both true and informative. Three states, from the display census: a lone
built-in panel says nothing (there is no other screen to confuse it with); a
built-in panel alongside another display gets the naming sentence (where it is
said: below); no built-in panel in
use — clamshell, or a Mac that has none — gets a row about what Crema cannot do,
because the brightness write degrades to false there instead of reaching for
whatever display happens to be main.
Four constraints shape it.
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
display-topology edge is rejected: it would add an invalidation
source to a body whose every rebuild costs a `CGGetEventTapList`. The census is the
cheap kind — `CGGetActiveDisplayList`, local and side-effect free — so reading it
where the menu is built adds zero expensive reads, is as fresh as the build, and
needs no edge to stay correct. The census is consulted only after the gate, so a
silenced menu asks the system nothing.
No warning glyph on either row. An arrangement is not a fault, and a ⚠️ on correct
behavior trains the user past the lines that do ask for action.
The row's SENTENCE describes an AIM instead of a limit, because the keys follow
the pointer (`brightness-key-follows-the-pointer`); the three states, the census
they come from and every gate above hold. The line stops short of saying what
happens on the other display —
this row appears only where no neighbour is ahead or reporting, which is exactly
where nobody may be managing that display, so "left to the system" is the last true
word available.

**Three states, two of them silent.** The sentence for a built-in panel among
others is not a menu row — not because the sentence is wrong, but because the
Indicators tab states it UNCONDITIONALLY, under the switch that turns the
replacement on, so the menu would carry a gated copy of an ungated
sentence (`menu-status-before-warnings`). `.noBuiltInDisplay`
keeps its row: it is the one arrangement no other surface in the app names.
`.quiet` says nothing, and every gate above holds — the `cremaApplies` gate, the
three causes of silence, the ACTIVE-display census the line is read from and the
pull-read (never a mirror) it is taken by. The census is consulted only
after the gate, so a silenced menu asks the system nothing.

### menu-reads-mirrors
A menu that names the track reads MIRRORS of title and artist, never the live
snapshot.
`Coordinator.nowPlaying` is rewritten once per second by the position tick — which
is exactly why the tick stays out of `state` (docs/STATE-FLOW.md, "The position
tick") — and Observation invalidates per PROPERTY, not per value: any read of that
property, `nowPlaying?.title` included, subscribes the reader to a 1 Hz rebuild.
The reader here is a `MenuBarExtra` content body, which SwiftUI re-evaluates
whenever it likes and not when the user opens the menu, and the block beside it
pull-reads the event-tap chain (`AppCore.mediaKeyChainNotice()`, whose every call
resets the min/max latencies of every tap on the machine, third-party taps
included). So the naive line does not cost a menu line: it costs a system-wide
diagnostic probe once per second, forever, invisible from inside the app.
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
(`controlsEnabled`, `skipControlsEnabled` — the same two the surface binds to)
and adds only "is there media at all", which the surface never needs because it
exists only when media does. One decision, two renderers: a menu that decided
availability for itself would drift from the surface the first time a source
accepted play/pause and rejected a skip. That one added predicate decides
EXISTENCE and is the line itself: the media section exists exactly when
`NowPlayingMenuLine` names media, so neither a title nor a transport is built over
nothing — a separate `title != nil` test is how a transport ends up under a line
naming nothing. It stays in `NowPlayingMenuSection`'s own body, where observation of
the mirrors is tracked, so a track change repaints that section without touching
the body that pull-reads the tap chain; raised into `MenuStatus` it would give that
body a 1 Hz dependency, the cost this entry exists to refuse. What `MenuStatus`
gates instead is the chain: no media section while no source reports, off the SAME
value `.nowPlayingUnavailable` comes from (`menu-status-before-warnings`).
Corollary for anything else the menu wants to show: the question is never "is this
value cheap to read" but "how often is the property I subscribe to written". A
per-second property is a per-second menu.
One precision to part (1), because the guard is easy to justify with the opposite
of what the runtime does. "Invalidates per property, not per
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
A brightness key that always acts on the built-in panel, whatever the user is
looking at, is — with a monitor as the main display — a key which dims the laptop
while the person reads the monitor (reported from the field), even though it is
correct for the bridge: `DisplayServicesBridge` resolves the BUILT-IN display for
every read and write, deliberately, because the framework governs no other panel.
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
Passing it back is also what makes the neighbour arrangement whole: with
suppression on, swallowing it would take the very key BetterDisplay is waiting
for, and the monitor would stop responding at all. The neighbour receives
it, applies it on its own display and reports the level back, which Crema draws on
that display (`hud-belongs-to-its-display`).
**A handed-back key stands the local bar down.** The tap keeps OBSERVING the key it
declines, so `MediaKeyHUDRouter` arms the brightness poll, the poll reads the panel
macOS just moved, and the app would draw a second bar over the system's own
indicator — every press, in the exact arrangement this rule targets. So the
suppressor fires `onHandedBackToTheSystem` and AppCore spends the source's key
window with `standDown()`, the same seam the neighbour's report already uses. One
press, one indicator, whoever drew it. The seam is named for the consequence and
not for this rule, because there is another reason to hand a key back — a
control the route does not have (`absent-capability-hands-the-key-back`) — and it
wants the identical standing-down. The suppressor still DERIVES the handback from
its own state rather than carrying a reason down from the tap: an autorepeat that
passes on the latch, after the pointer has already crossed back, must stand down
too, and a carried reason would say it is ours.
Five properties of the rule, each one a case that cost a decision.
**No fallback to the built-in panel**: that fallback IS the bug. Clamshell needs no
branch of its own — with no built-in among the bounds the rule never answers
`.builtIn` — and a pointer nobody can place answers nothing rather than picking a
screen. A quiet consequence: in clamshell Crema never swallows a brightness key
it cannot apply, so the escalation that ends in "Crema couldn't apply the
change" — five failed applies against a panel that is not there — cannot start.
**A single display answers itself, pointer or no pointer**: with one screen
attached the pointer disambiguates nothing, so a failed reading must not disable
the keys on the Mac that has exactly one panel. Not a disguised fallback — in
clamshell the single display is the external one and is answered as such.
**One coordinate space, chosen so there is no conversion to get wrong.** The
pointer is read with `CGEvent(source: nil)?.location` and the bounds with
`CGDisplayBounds`: both are CoreGraphics' global display space, origin at the
top-left of the main display, y growing DOWN. Bounds from the AppKit panel roster
would need y flipped inside the rule; the flip's sign is the
difference between the display above and the display below, and it is a line of
arithmetic that exists only because the wrong list was chosen. Bounds are half-open
on both axes, the way CoreGraphics tiles them, so a seam belongs to exactly one
display and the answer never depends on list order — and the load-bearing seam,
with a monitor placed ABOVE the laptop, is the laptop's menu bar sitting on the
laptop's own `minY`, which the laptop owns for free.
**The list is the ACTIVE display list, not the panel roster** — the same list the
brightness write resolves its target from and the menu reads its census from, for
the reason `brightness-key-target-in-the-menu` gives: the roster drops
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
tap can strand it.) The same latch keeps a swallowed press swallowed: both
directions are one rule.
What is NOT here: applying on the external display, and any identity for it. The
write half exists (`BetterDisplayScreenBrightnessController`, used by drags), but a
stepped key also needs a LEVEL to step from and verify against, and the app has
no seam for reading the neighbour's brightness: the one built for it never gained
a caller and is not in the tree. What the probing measured stays in
`neighbour-features-are-not-identifiers` — identifier is the metadata door only; a
feature is asked for by its own name as a valueless key — and whoever rebuilds the
seam recovers its shape from the git history. Until it has a caller,
`.anotherDisplay` carries no UUID — a field nobody reads is a field that goes stale, and adding it back is
one stored property.
What this does NOT fix, stated plainly so nobody reads more into it: with no
neighbour behind us, the key handed back goes to macOS, which dims the built-in
panel anyway and shows its own indicator. Crema stops being the one that dims the
wrong screen; it cannot stop the system from doing so. That is the same contract
`per-domain-suspension` already accepts, and it is why the menu row promises an aim
and never an outcome on the other display.

### hud-target-is-a-role
A `SystemHUD.display` that is one `DisplayUUID?` carries two different facts, and
the seam shows in the field: with a monitor attached and the pointer on the laptop, a
brightness key moves the laptop's panel correctly and draws the bar on BOTH
screens, while the neighbour's path — which names a display — correctly draws only
on the monitor. A type documenting `nil` as "the internal display" while the
presentation layer reads the same `nil` as "nobody said which screen, so draw
everywhere" holds two load-bearing sentences that contradict each other.

Why that is a defect and not untidiness: the extra bar is not spare
feedback, it is a live CONTROL. Every panel is handed the `.hud` state and draws a
slider, and a drag on the monitor's copy writes the BUILT-IN panel — so the second
bar is a control for a screen the user is not looking at that dims a different
one in silence, word for word the harm `hud-belongs-to-its-display` exists to
prevent, in the direction easiest to leave unchecked. The app is also committed
to the premise: by `brightness-key-follows-the-pointer` it BETS that the pointer
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
double bar, and with the key already swallowed. `WindowManager` instead asks the
roster which of ITS panels is internal (`isInternal`, taken in the same snapshot
that created the panel), so role and panel cannot drift apart. It also costs
nothing on the hot path: resolving a UUID at emit time would put a display
enumeration inside the serial queue that already serializes this channel's
blocking reads.

The built-in role falls OPEN, not shut. With no internal panel in the roster a
`.builtIn` HUD shows on every display — the unscoped behaviour — instead of none. That
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
bar would throw instead of writing.

Known gaps, stated rather than sold as fixed. A mirror set is a coin flip: the one
`NSScreen` AppKit reports may or may not be the internal one, and when it is not,
the bar falls open to every display plus a log line. And a payload from the
neighbour that names no display is dropped: drawn everywhere, a drag on it would
resolve to the built-in panel, a guess `betterdisplay-osd-source` rules against
("drop rather than guess"), and anyone in the session can post one. The trigger
that reopens this decision: the day the app can read a SECOND Apple-controlled
panel, `.builtIn` stops naming exactly one screen and the producer has to name the
display it read.

### assumed-isolation-is-measured
The rule first, because it outlives the case: an assumption that cannot be caught
may rest on an archived guarantee only if it ALSO rests on a measurement someone
can re-run, and the comment names both — archive status included. A citation that
hides its own age reads as authority it no longer has.
Ten `MainActor.assumeIsolated` calls sit on system callbacks, each a fatalError if
its callback ever arrives off the main thread, and they do not all rest on the same
footing. Six are NotificationCenter block observers registered with `queue: .main`
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
The second footing is a measurement, not the code. Measured on macOS 26.5.2 /
Swift 6.3.3, posting from a background thread: all five mechanisms (local monitor,
GLOBAL monitor, NotificationCenter, DistributedNotificationCenter, NSWorkspace
center) deliver on the main thread — which is the predicate the runtime checks, so
the assumption holds by construction. The global monitor is the one no live
document covers at all, and this measurement is the first to cover it — beside
the archived guide's sentence, not in place of it.

### absent-capability-hands-the-key-back
With suppression on, a key consumed for a control that does not exist produces
nothing at all. Not our bar — the apply is a no-op, and an `applyVerified` with no
branch for a no-op gives no HUD poke and no echo — and not the native OSD either,
because the tap has already eaten the press. An HDMI output with no volume control,
a device with volume and no mute plane, a Mac whose keyboard backlight has not
enumerated yet: press, silence. On screen brightness with the private symbols
unresolved it is worse than silence, since every brightness key is swallowed
forever and the panel simply stops responding, with one `logger.notice` as the
only trace. That breaks the rule
`brightness-key-follows-the-pointer` states: **a consumed key owes feedback**, and
swallowing while drawing nothing is the alternative that rule already kills.
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
is how a person meets it. Releasing the latch AT THE MARK is refused: it leaks
the pending up, and where suspension's own rationale accepts
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
are left out deliberately: the hang doubles share one semaphore per channel, so an
extra availability read at engage would consume the release a deadline test arms for
its key press, and doing it properly means reworking those doubles. Written here so
it reads as a deferred improvement and not an impossibility.
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
makes a suspended domain take the line away entirely; the difference is what the user
sees instead. On the dominant case, an output with no volume control, macOS draws
its "prohibited" HUD, and that explains the hardware better than any line in a menu
would. Adding a `Row` in the `brightnessNoBuiltIn` mould stays the honest option if
the field says otherwise; it is not taken because it costs four catalog keys for a
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
External displays belong to BetterDisplay. Crema writes no DDC of its own and
reaches an external display's brightness only through the neighbour's
request/response channel: the bar the neighbour drew is dragged through it (an
absolute level, which the channel accepts — `the-bar-never-outruns-the-screen`),
and the key aimed at an external screen is handed back whole
(`brightness-key-follows-the-pointer`). That border, not the anchor's name, is
what the contract cites this entry for.
The "write-only" reading in the name is superseded by
`neighbour-features-are-not-identifiers`. Through `identifier`, the metadata
door, five brightness spellings (`brightness`, `combinedBrightness`,
`hardwareBrightness`, `softwareBrightness`, `ddcBrightness`) are refused while
six metadata spellings answer as the shape control; asked by its own key, the
feature answers. `scripts/probes/read-betterdisplay.swift` asks through both
doors and gives its verdict on the key alone;
`scripts/probes/relative-betterdisplay.swift` tries nine relative
shapes with the sign on the value, which the neighbour reads as an absolute,
against the absolute `set` as control. Both refusals are about the door, not
the platform: a feature is read with its name as the parameter key, and a
relative write is the documented `offset` parameter.
Confirmed with `read-betterdisplay.swift` 2026-10-14 on BetterDisplay 5.1.1
against the built-in display: `get` with `"identifier":"brightness"` →
`result=false`; with `"brightness":""` → `result=true`, payload 0.671
(`combinedBrightness` 0.671, `hardwareBrightness` 0.561, `softwareBrightness`
1.0; `ddcBrightness` refused, as a built-in panel has no DDC); every metadata
spelling answered. The external-display read
(displayID 2 → 0.063) is the one recorded under
`neighbour-features-are-not-identifiers`.
So a `before` exists, and a brightness key Crema applies to an external display
is unbuilt work, not a measured impossibility: the apply+verify cycle over the
neighbour's channel, with the deadline it already has. Until it is built the key
stays handed back.

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
it on with that host means asking for data, the user consenting, and nobody ever
reading it — a cost in trust for a return of zero. It unblocks by moving the appcast to a host
with logs (or putting a logged redirect in front of it), and the trap that comes with
that move is written down here so it is not rediscovered: **the old URL has to keep
answering**, or every installation carrying the current `SUFeedURL` never receives an
update again. Without the logged host, the free metric is the release download
count from GitHub's API — zero code in the app.
**Explicitly discarded: a third-party analytics SDK.** The app uses private API and
holds the Accessibility permission; it is the exact profile of an app whose user runs
Little Snitch, and one unexpected connection costs more than the metric is worth.
Reopening requires the logged host to exist first, and the answer to be Sparkle's own
profile — never an SDK.

### the-feed-signs-itself
Two Sparkle plist keys default off, and both defaults are the wrong end of a trade
this app is on the paying side of. Without `SUVerifyUpdateBeforeExtraction`, and
with Crema shipping a DMG — measured in Sparkle 2.9.4's own sources,
`SUDiskImageUnarchiver` returns NO from `mustValidateBeforeExtraction` — the
downloaded image is handed to hdiutil BEFORE its EdDSA signature is checked:
mounting bytes nobody has vouched for, on the one path where the app runs code it
did not build. Without `SURequireSignedFeed` the appcast itself is
unauthenticated: an attacker who
controls the served feed still cannot forge a download (the enclosure signature holds)
but can lie about which version is newest and freeze clients where they are; a
downgrade Sparkle refuses on its own (2.9.4's installer rejects an older version).
Signing closes the lie, not a replay: a feed signed in its day can be served again
later and freezes clients at that version (docs/KNOWN-GAPS.md).
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
The consequence: docs/appcast.xml authenticates itself, and every feed from 1.5.0 on carries the signature block (1.2.0 and 1.4.0 ship without the keys and carry none).
So "regenerated, never hand-edited" is not tidiness: a hand edit is an outage — clients carrying the key fail every check for 20 days, Sparkle's
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
forward: the update is announced by a window the user never sees.
Decision: Crema declares `supportsGentleScheduledUpdateReminders` and implements
`standardUserDriverWillHandleShowingUpdate:` only — Sparkle keeps presenting its alert
(so the path never depends on our UI being right), and the menu bar carries the signpost
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
A `stop()` that nobody calls on a long-lived consumer — the Coordinator,
`MediaKeyHUDRouter` — is worse than unused. The sources
they consume build `updates` once at init and reserve `finish` for their own end of
life, so a cancelled iteration is not resubscribable: whoever calls `stop()`
gets a permanently media-less app, or brightness keys that never reach the HUD again,
with no error anywhere — and on the Coordinator the teardown additionally reports
itself to the rest of the machine as "the media source died", discarding the
snapshot and hiding the surface, which `ghost-discard` reserves for a genuine source
death. Decision: an object that lives for the process does not ship a teardown seam it
cannot honour. The absence is documented on the type (with the reason, not just the
fact), so the next reader adds a lock or a resubscribe path deliberately instead of
adding a `stop()` that compiles and lies. Reopening requires a source whose
stream can be rebuilt after cancellation.

### a-panel-leaves-the-roster-before-it-closes
Closing a presentation panel is not a leaf operation. `close()` stops its hover
monitor; the disarm reports the pending exit (deliberately — a silent reset would
leave the Coordinator's pointer record stale, `hover-follows-the-eye`); the
Coordinator collapses an expanded appearance; and that state write runs the
WindowManager's frame pass SYNCHRONOUSLY (`onPresentationChange`). With the entry
still in `entries` the pass applies to the panel just closed and re-arms its hover,
reinstalling a pair of NSEvent monitors that nothing disarms again once the entry does
leave — a dead panel sampling the cursor against regions on a screen that may be gone.
The re-entrancy guard in `runFramePass` does not cover it: that guard defers a pass
nested INSIDE a pass, and this one starts outside. Decision: a panel leaves the
roster FIRST and closes second — `retirePanels(_:)` drops a gone display's entry,
`reconcile(_:)` rewrites a kept display's entry without the panels that leave — so a
re-entrant pass cannot see the dead panel; the
caller's trailing pass covers whatever takes its place. The general shape, met three
times in this codebase: a teardown that crosses into another subsystem comes back through
the front door, so order the local bookkeeping before the crossing rather than
trusting the crossing to be quiet.

### one-screen-reading-per-edge
At every display edge the app reads the display border ONCE and hands the SAME
list to both sides that have to agree about it: the panel roster and the
per-display list in Settings. The seam (`AppCore.applyScreenRoster`) takes the
already-read descriptions as a parameter instead of calling
`ScreenTranslation.describeAll()` inside itself, and that parameter is what makes
the single reading STRUCTURAL rather than a habit the next caller can break. Two
independent readings can disagree — a display that left between them — and then
the tab offers a row for a display no panel carries while a panel draws for a
display no row can reach: the Settings tab becomes a control over a screen the
panels do not see. Two lists disagreeing about which screen is which is the class
`hud-target-is-a-role` rules on, where a true sentence ends up describing the
opposite behaviour. Order inside the seam is panels first, roster second: the
roster is what a view reads, and publishing it earlier would offer a row whose
writers reach a display the manager has not reconciled yet.

The roster is REACTIVE, deliberately unlike its neighbour in Settings. The General
tab seeds its mirrors once and re-reads only when its own picker writes — a
pinned-latent tradeoff that costs a stale value there and is accepted. A list
whose rows ARE the displays cannot take that deal: a row outliving its monitor is
a control over a screen the user cannot see, and a display plugged in with the
window open would have no row at all until Settings is closed and reopened. The
write is guarded like every other read mirror, because an unchanged topology is
the common case rather than the rare one — `didChangeScreenParameters` fires for a
resolution change, a rearrangement or a display waking, and only some of those
move this list.

The menu bar does NOT read the roster. Its status block pull-reads the event-tap
chain, and each of those readings resets the min/max latency counters of every tap
on the machine (`media-key-chain-contention`), so a roster the menu observed would
turn every display change into a system-wide probe — the same reason the
automation monitor stays out of that body (`automation-is-fallback-only`).

### selected-and-disabled-is-a-state
A per-display style picker gets asked about screens that cannot draw the style the
user declared: notch, on a panel with no slit. That choice is SELECTED AND
DISABLED, which is not a contradiction but the honest report of "you declared this
and this screen does not draw it". The per-display control draws no tile (it is
a popup, below); the rule for a tile, if one is ever drawn for this pair: the
selection ring keeps full strength — it states the choice, which is still true —
and only the picture recedes (0.4), because the picture is the part that is not
happening on this display; a faded ring would blur the second statement into the
first. And the picture under such a tile is the fallback that display REALLY
draws (`rendered-style-gates-settings`), which is what makes the pair readable at
all: the tile says what was chosen and shows what is drawn, at the same time.

Two accessibility facts are measured here, and both generalize.
SwiftUI's `AccessibilityTraits` has no member for "not enabled" — the set is
`isButton` / `isSelected` / `isHeader` and their kin — so unavailability in SwiftUI
is spoken through `.disabled(_:)` and through no other channel.
`allowsHitTesting(false)` is the tempting alternative and is the wrong one: it
leaves a tile that still announces as a live button and does nothing when
activated, the one failure a person using VoiceOver cannot see. And the disabled
trait by itself reads as "dimmed" with no reason attached, so such a tile's hint
says WHY in place of the position sentence the enabled tiles narrate. `.isSelected`
survives the disabling for the same reason the ring does.

**The state holds whatever the chrome.** The per-display control is a popup of
names, not a row of thumbnails, so "selected and disabled" is a CHECKED MENU ITEM
that cannot be picked — the same honest report of "you chose this and this screen
does not draw it", stated with a checkmark instead of a ring. A menu item has no
hint channel and no picture to dim, so the popup carries neither.
`DisplayStyleOptions.selection` is read from the user's own key and never filtered
through `isHonoured`, which is what makes the pair representable at all: a legacy
"notch" key on a slitless panel reports `.notch` selected while its item reports
`isEnabled == false`. The DISABLING CHANNEL is measured rather than stylistic (the
measurement: `the-chrome-is-not-the-guarantee`), so the chrome is a custom `Menu`
of Toggles, where `.disabled` is honoured and therefore reaches VoiceOver through
the only channel SwiftUI has for unavailability. Both accessibility facts above
hold for the popup and generalize. And what keeps an unhonoured pick out of the
STORE is never the chrome (`the-chrome-is-not-the-guarantee`).

### the-tour-configures-instead-of-pointing
The welcome tour is five steps that SHOW the app on the real screen and CONFIGURE
it, not pictures of it: what Crema is, the Accessibility permission, the style
every display draws, a key test with the switch that replaces the system
indicators, and opening at login. What else Settings holds (the Card
indicator's place and look, a style per display) is left to Settings, where it
is drawn: told in a sentence before anyone has seen the indicator, it reads as
a list of names (HIG, Onboarding: postpone nonessential setup). Every control in it
is the control the Settings window carries — the same persisted key, applied
live through the same AppCore call — so nothing in the tour is a second source
of truth and nothing it does needs undoing: what was picked there is what
Settings shows afterwards.

Five rules hold it, and each one names a way this window could go wrong.

The flag is committed BEFORE the window is shown (`hasSeenWelcomeTour`, written
inside `presentWelcomeTourIfFirstLaunch` ahead of the presentation). A crash or
a force quit in the middle of the tour must not re-arm it: a window that
returns after every bad launch is worse than one that was missed once. The way
back is the menu's Welcome Tour item, which the HIG asks of a tour a person
skipped (Onboarding), and it starts over from the first step.

The gate asks about no permission. A gate on the Accessibility grant skips
anyone who already has it — which is every upgrading install — and an install
that carries the grant is not one that was walked through anything; it is
usually the one whose first launch went worst. So the tour is shown once per
install, to everybody.

No step may hold anyone back. The permission decides what the step OFFERS (the
grant as the step's prominent button while it is missing, picked up live by the
polling monitor, which brings the window back to the front), never where the
road goes: the footer's way on reads Continue Without Access until then. Crema
runs without that permission, so a step that could only be left by granting
would trap someone who declines inside a window whose whole point is that it
can be left. The rule lives in `WelcomeTourFlow` — pure, stringless, both ends
total — which is why it is pinned by tests instead of by a view body.

The real screen answers, and the sample is no player's. The welcome and the
style steps hold the player up (`Coordinator.showcase(sample:)`): the playing
track when there is one, otherwise a sample named as such, held with no tuck
until the step is left or the window closes, however it closes. Where no
display shows the player — a Mac without a built-in panel, where it is born off
— those steps say so and offer the per-display switch for the primary display
(`WelcomeTourFlow.displayToOfferThePlayer`) instead of describing a player
nobody can see. The sample
disables the transport in the skins AND the Coordinator refuses every command
while it shows (`the-chrome-is-not-the-guarantee`): a command would reach
whatever player macOS last knew, which is not what the sample shows. The key
test asks for a volume key because Core Audio reports volume with or without
the grant, so the one step that teaches by doing never waits on the
permission.

The window is one fixed size for every step, and the last step says where the
app lives in words, with an arrow at the real icon, instead of offering a
Settings button. The size, because the steps hold different amounts and a
window that resized between them would jump under the pointer at the moment a
button is being clicked. The words, because `openSettings` is an environment
action of the Settings scene: from a window built outside that scene it is a
no-op, so a button there would be one that does nothing. The arrow finds the
icon as the one window of this process at the status-bar level, read by public
properties alone; macOS builds that window a moment after launch, so the arrow
asks a few times and, finding none on a screen, does not show.

### the-chrome-is-not-the-guarantee
The per-display style control has to refuse a style the screen cannot draw. The
obvious shape, a `Picker` in `.menu` style with `.disabled` on the option, does
not work: measured on macOS 26.5.2
(`scripts/probes/picker-option-disabled.swift`), a `.menu` Picker DISCARDS
`.disabled` on its options — the marked item read back `isEnabled == true` while
an `NSPopUpButton` in the same window, carrying a natively disabled item, read
`false`. That control is what makes the negative mean something: the probe's
introspection can see disablement, so the Picker's option genuinely is not
disabled rather than merely unreadable from outside.
So the popup is a custom `Menu` of one item per option, where `.disabled` is
honoured, and its label is the effective style. But the chrome is not where the
guarantee lives: `DisplayStyleOptions.write(for:)` answers `.refused` for a style
this geometry does not honour, `.clear` for inherit and `.override` otherwise, so
a pick that reaches the store despite the greying still writes nothing.
This is an entry rather than a comment because it generalizes: when a control
must not be able to do X, the ban belongs in the pure type the control calls, and
the greying out is only what keeps X out of reach. Which of the two a given
framework is giving you is a question a probe answers and a doc does not.

### surface-border-2026
ONE uniform white hairline on the floating surfaces (Card and Classic) is a single
stroke asked to do two jobs and doing neither. Over a bright desktop it
disappears, which is exactly where a translucent surface most needs an edge. And
a uniform bright line lies about the light: it claims a highlight arriving
equally from every direction, including from underneath, which nothing on a
screen lit from above ever has.
Decision: the boundary is the surface's own darkness, and the one stroke is the
light. The film over the material (`SurfaceChrome.scrim`,
`hud-fixed-dark-palette`) keeps the surface dark over any desktop, so it stands
out from a bright one with no line drawn round it. An inner specular, brightest
at the top edge and spent within the upper third, supplies the lit-from-above
highlight the material does not draw itself. There is no dark rim: with the film
in place it adds nothing to a dark surface, and around the filled HUD's light
sweep it reads as a drawn outline over a white page. The anchor carries a year
because the specular's shape is the one the 2026 platform redesign settled on —
provenance, recorded so nobody re-derives it, never the authority. This is the
edge of Classic and of the Card before macOS 26; the Card's glass carries its own
rim, read off the system's OSD (the-card-is-glass).

Three mechanics are load bearing.

The specular is a `strokeBorder`, not a `stroke`, which is why `vibrantSurface`
takes `some InsettableShape`: `strokeBorder` insets by half the line width, so
the highlight stays INSIDE the surface instead of bleeding a bright edge outward.

The outline is antialiased once. The content and the film are composited before
the clip (`compositingGroup`), and the material, an AppKit view masked apart from
the SwiftUI layer above it, stops `SurfaceChrome.materialInset` (half a point)
inside the outline. Clipped layer by layer, the dark beneath shows through the
edge pixels of a light fill: a grey fringe round the filled HUD over a bright
desktop, which scripts/probes/hud-surface-contrast.swift (mode `edge`) measures
against the shipped surface's clean edge.

The numbers live in one place (`SurfaceChrome`) because the Settings tiles draw
this same edge in miniature, and two literals drift. A tile draws ONE flat
hairline where the surface ramps — at 108 pt an edge that fades reads as no edge —
and it takes that value from the ramp's brightest point (`tileStrokeTopOpacity`,
derived, never a literal), at the specular's own width. A forked number would
paint an edge the app does not have, in the one place a person compares the
skins: the second description is the one that rots.

The Notch does not participate, and that is not an omission. That skin is opaque
black because it camouflages with the hardware cutout it covers — the same
commitment `hud-fixed-dark-palette` records — so an edge there would draw the very
outline the skin exists to hide. Its Settings tile strokes nothing either, off the
same fact (`surfaceIsOpaque`), so the picture and the surface agree about the
absence too.

What must survive a retune is the SHAPE — a dark surface, lit at the top, inside
— not any single number. Reopening gate: the edge rests on the film because this
material draws no edge of its own. The day a never-key, nonactivating panel can
take one that does, it is re-examined rather than kept beside it — Liquid Glass is
the standing candidate and the standing blocker (`hud-fixed-dark-palette` carries
the macOS 27 measurement). The other gate is the Notch: if that skin ever floats
instead of camouflaging, it takes the specular with it.

### inner-corners-are-concentric
Apple publishes no OSD dimensions; it publishes shape rules. WWDC25 session 356
names three shapes: a fixed radius, a capsule (half the height), and a concentric
shape, which "calculate[s] its radius by subtracting padding from the parent's".
A rounded shape nested near a surface's corner with any other radius reads as
off, the gap around the corner pinching or bulging.
Decision: the Card HUD and every cover nested in a surface corner take their
radius from one of these rules, derived in code rather than declared. The Card
HUD is a fixed shape whose radius is a third of its height
(`CardMetrics.hudSystemCornerRadius`), the corner of the author's reference
indicator, a filled level bar near 5.8:1, which `CardMetrics.hudSystemSize` reproduces. A cover nested in a surface corner is concentric: the parent's radius minus the
tighter of its two insets (`CardMetrics.compactArtworkRadius`,
`expandedArtworkRadius`, `NotchMetrics.compactArtworkRadius`). With unequal insets
no radius is exactly concentric; subtracting the tighter one keeps the inner
arc's centre level with the outer one's on that side, so the gap runs from one
inset to the other with no pinch. A shape whose inset reaches past the parent's
radius is not nested and keeps its own radius: Classic's covers (centred, 45 pt
and more from the side under an 18 pt radius), its segments, the Notch's expanded
cover (below the slit, far from the top corners). The filled HUD's glyph is inset
by the radius itself, so the corner never reaches it. `CardMetricsShapeTests`
pins these as relations, never as literals.

### tile-backdrop-is-the-real-desktop
A drawn desk under the style tiles — a flat, dim gradient, fixed rather than
theme-following — has two reasons for it: the subject is the black shape and a
busy wallpaper would compete with the one thing these pictures exist to compare,
and the app's surfaces are always dark (`hud-fixed-dark-palette`), so a tile that
went bright under a pale desktop would describe a skin the app never draws. Both
reasons are true. What they argue for is not: a tile is a picture of A PLACE —
each one says "the surface looks like this, up there on your screen" — and a
screen wearing a wallpaper nobody has ever seen is a picture of somebody else's
Mac.
Decision: the backdrop is the user's own desktop picture under a dark wash
(`TileBackdrop`, 28%), and the WASH is what keeps both reasons rather than
trading them away. At that opacity a wallpaper stays background instead of
becoming the subject, and the palest desk stays dark enough for the surface
standing on it to be honest. The gradient stays as the fallback, for
a desk that cannot be read — no picture reported, or a dynamic/aerial desktop
ImageIO will not open. A hole where the screen should be is a worse picture than a
drawn one.

Three mechanics.

The reading is a source behind a protocol like every other border contact
(`DesktopPictureSource`), and only a URL crosses it — NSScreen, NSWorkspace and
the decoded bitmap all stay on the system side. That is what makes the caching
above it a unit test instead of a trip to the window server. `nil` is an answer
and not an error: there may be no screen to ask, and macOS names no file for some
desktops.

ONE screen is asked (`NSScreen.main`, else the first connected), deliberately. The
picture is SCENERY, not a claim about a particular display: a tile shows a style
declared for every screen, so asking each display for its own wallpaper would
answer a question nobody asked and force a per-tile choice that means nothing.
The per-display rows' thumbnails (`DisplayStyleRow`) do name a display, and stand
on the same desk: what they claim about that screen is the shape, resolved on its
geometry (`StylePreview.shapes(for:on:)`), and the desk under it stays scenery.
Reopening gate: the day the desk itself is to be a claim about a particular
screen, the source takes the display as an argument.

The decode is bounded and cached BY URL, failure included (`WallpaperTileStore`).
A wallpaper is several megapixels and a tile is 108 pt of it, so the picture is
paid once per file as a ~220 px thumbnail (`CGImageSourceCreateThumbnailAtIndex`,
an eager bounded decode, where `NSImage(contentsOf:)` hands back a lazy full-size
image whose real cost lands on the first draw, on the main thread, inside the
Settings window). A read that FAILED is remembered exactly like one that
succeeded, because a view body runs whenever SwiftUI decides to and an unreadable
desktop would otherwise be re-opened on every one of them. The border is asked
every time — the answer is what is worth caching, never the question — so a
wallpaper the user just changed is a different URL and is seen. And `nil` never
returns the last image: a picture of a desk the app can no longer confirm is a
picture of nothing.

The residual is the seed-once deal the Settings mirrors already take (S4): the
panes read the store when they are built, so a wallpaper changed with the window
open shows up the next time it opens.

### the-lock-screen-is-a-space

~~Superseded: the app has no lock-screen widget and no private window API (the-lock-screen-was-built-and-taken-out). What holds, proven on hardware and kept in docs/LOCKSCREEN-INVESTIGATION.md: no window level reaches the shield, the shield is a space at absolute level 300, a private SkyLight space at 400 composites over it, and clicks reach a window there. The panels refuse SkyLight at any level: they draw several times a day over the user's work, a public level does the job, and a WindowServer wedge there breaks the app's core function for everyone. Full entry in git (c67c9f1 and earlier).~~

### the-cover-comes-from-the-archive-not-the-store

~~Superseded: there is no cover lookup, and the app makes no artwork request (the-click-was-the-last-thing-holding-the-lookup-up). The reasoning that chose the lookup's source over the iTunes Search API, whose terms tie album art to promoting a purchase, is in git (c67c9f1 and earlier).~~

### animated-artwork-is-withheld-not-missing

~~Superseded: no surface the app carries asks for motion artwork. The three walls recorded against it for any third party (the data withheld by Apple, a provider-only API, a bridge that carries one static image) and the cover lookup's invariants are in git (c67c9f1 and earlier).~~

### the-lock-surface-is-a-card

~~Superseded: the surface this decision shaped does not exist (the-lock-screen-was-built-and-taken-out). The chain of costs that ended its backdrop (the Mach band at the fade, the clock the backdrop obliged, the safety cost of covering the login) is in git (c67c9f1 and earlier); the open question of a space below level 300 stands in the-lock-screen-was-built-and-taken-out.~~

### the-click-was-the-last-thing-holding-the-lookup-up
A corollary of the-lock-surface-is-a-card rather than a new decision, recorded
separately because the chain it describes is the kind nobody reconstructs. The
surface, its expanded state and the cover lookup are not in the tree
(the-lock-screen-was-built-and-taken-out); what stays is the lesson.

Costs on a lock surface compound rather than sit side by side. **A 300 pt tile
CENTRED** has its bottom edge at `(H - 300) / 2` — a function of a display height
the surface never reads. On the author's 982 pt panel that is 341 and everything
clears, which is exactly how a measurement gets written down as if it described
the design. Below 900 pt the tile crosses the clearance floor (`clearBandFloor`,
gone with the surface); below 660 pt it lands on the login. A 13-inch Air at its most-zoomed scaled setting is 1024x640. Not one
of eleven proposed designs noticed, and the ruler that "proved 341..641 clear"
proves it for one panel.

Decision, for the lock surface: **one state.** No click, no tile, no morph and no
tap gesture; the card rests on a bottom inset (`bottomInset`, gone with the
surface) and its placement is not a function of any height.

**And the click was load-bearing for something two directories away.** The
high-resolution cover lookup — `ArtworkLookup`, `CoverArtArchiveLookup`,
`RequestPacer`, `LockArtworkResolver`, an opt-in preference, a Settings row and
four test suites — existed only to keep a 300 pt tile from showing a soft 400 px
image; nothing else in the app used it, and none of it is in the tree. Against a
50 pt thumbnail it would fetch 1200 px over the network, paced against
MusicBrainz's 1 req/s, to feed 100 px. Its absence is not tidiness: keeping it
would be a network request tied to what somebody is listening to, carried by an
app whose SPEC promises no accounts and no analytics, in exchange for nothing
visible. `ArtworkDecoding.lockScreenMaxSide` is gone with it — a decode bound four
times the largest remaining slot is cost nobody reads.

**Orphans leave in the same diff rather than wait for a caller**, young ones
included. `SurfaceAnimation.morph(expanding:reduceMotion:)`, written for this
exact toggle, is not in the tree; the rule it expressed (the destination picks
the spring) survives in `geometryAnimation` and in its comment. `MockArtworkLookup`
is gone with its protocol.

**What this does NOT settle**, and the distinction matters because the two are
easy to merge: no lock surface expands, and none shows a large cover. The first
is a placement decision with arithmetic behind it. The second is a consequence of
the first, and it is the one a future attempt might want back — with an anchored
geometry rather than a centred one, and with the lookup's cost re-argued from
scratch, never restored on precedent.

### the-card-takes-the-material-it-was-refusing

~~Superseded: there is no material parameter (the-lock-screen-was-built-and-taken-out); the Increase Contrast promotion in `TrackTextStack` and the expired-comment lesson ship and are recorded at their sites. Full entry in git (46212da and earlier).~~

### the-card-was-thin-because-it-was-small

~~Superseded: the card this entry enlarged does not exist (the-lock-screen-was-built-and-taken-out). Full entry — the sibling measurements and the refusal to grow the shared scrubber — in git (46212da and earlier).~~

### the-lock-card-is-light-and-lives-on-a-module

~~Superseded: there is no lock card, light palette or concentric size arithmetic (the-lock-screen-was-built-and-taken-out); the module discipline survives as `Sources/`' layout, and the full entry is in git (46212da and earlier).~~

### the-lock-screen-was-built-and-taken-out
Crema draws nothing on the lock screen, and the app has **no private window API
at all**. A lock-screen surface is an explored path, built and proven on
hardware, and its absence is a decision rather than a gap somebody should fill.
The reason is the author's and concerns return, not correctness: the surface
drew, the clicks routed and the geometry was measured, and the design still
converged on a card that reads as thin. "Não está compensando" is a complete
argument for stopping, and it does not require the work to have been wrong.

With nothing drawn over the shield, lock-aware suppression is what leaves the
keys their native feedback: OSD suppression never stays engaged while the screen
is locked (`SuppressionLockController`).

**The shared files carry nothing for it.** `TrackTextStack` has one type ramp,
with no scale for a surface read at two or three metres; `SurfaceChrome` has no
light palette, and `vibrantSurface` no material or palette parameter. An API with
no caller is removed in the diff that orphans it.

**What remains.** `docs/LOCKSCREEN-INVESTIGATION.md` holds the hardware facts,
which a codebase without the feature cannot rederive: no window LEVEL reaches the
shield; the shield is a SPACE at absolute level 300; a private SkyLight space at
400 composites over it; clicks reach a window there; a screen-sized window
behaves; the login's top edge sits at or below 180 pt on a 1512×982 panel. The
anchors that record design findings stay too (the concentric radius rule, the
Mach band diagnosis, the measured contrast arithmetic), because none of them is
about the lock screen. The surface, its window, the SkyLight bridge behind
`RaisedSpace`, the second reader on the lock source, the preference, the probes
and their test suites are in git (`bb7bb73^`).

**What a future attempt owes before writing any code**: whether a SkyLight space
BELOW level 300 composites BEHIND the shield. Nothing needs the artwork above the
login, only behind it; if a lower space shows through, the system draws the login
on top, and the clearance band, the clock a backdrop obliges, the accessibility
vetoes and the panel-height arithmetic retire at once. `lockscreen-space.swift`,
in git only (`bb7bb73^`), takes the level as a parameter and was never run at 250.

**The reopening gate is a scope, not a measurement.** The surface has to be
beautiful, legible at three metres, safe over a credential field and correct on
every panel size, all at once, on a display the app does not own. Anyone
proposing it again says which of those four they are dropping.

### the-slit-is-found-from-its-edges
One rule finds the cutout, from its edges — `frame.minX + auxLeft`,
`frame.width − auxLeft − auxRight` — and every reader asks it (the decision
below). The discarded path is **a second rule for the same cutout**: the surface's
`topAnchored` laying the rule width around the display's centre,
`geometry.frame.midX`, while the click-invoke zone and the Settings picture built
the slit from its edges. A centre-derived copy agrees with the edges only while
`auxLeft == auxRight`, and diverges by `(auxRight − auxLeft) / 2` when they do
not.

They do not. The 14" panel this app is built on measures **663 pt left of the
slit and 664 right** — the app's own reference geometry says so
(`StylePreview.notchedReference`, and `StylePreviewTests` calls that
asymmetry "the hardware's, not ours to round away"). So the display's centre is
756 and the cutout's is 755.5, and a centre-built surface claims x ∈ [663.5, 848.5]
against a cutout ending at 848: **half a point of antialiased edge sitting on live
menu-bar pixels**, on the default scale mode, on the author's own machine. That
is precisely what `NotchMetrics.lateralInset`'s calibration forbids — its whole
argument is that the edges land flush on pixel boundaries so the height morph has
no fringe to re-rasterize, and it is written never to overhang even at rest.

Decision: **one rule, `NotchStyle.slit(on:)`, and it is built from the two edges
the API hands over.** The centre is derived from the rect, never the rect from a
centre — a centre is an inference that the hardware is symmetric, and nothing in
`NSScreen` promises that. Every reader asks that one function: the frame rule
(which centres the surface in the slit's own midX), the click-invoke zone (which
IS its rect), `StylePreview` (which pictures it), and `Style.resolved(on:)`. The
zone matters most: the panel takes the mouse inside it, so a zone reaching a
pixel the surface disowns captures clicks over live menu bar.

**The same rule answers "is there a notch at all", and `safeTop` alone does not.**
`NSScreen.h` documents both auxiliary rects as *"empty if there are no additional
unobscured areas"*, so a top safe area with `auxLeft == auxRight == 0` describes a
display whose obscured strip spans the full width — not a cutout. Read as one, the
slit becomes the whole screen: a display-wide black surface welded to the top edge,
and an invoke zone over the entire menu bar, captured by the panel and then handed
to `Coordinator.invoke`, which refuses most clicks (it acts only from `.hidden`
with something playing). Every menu-bar click in that state is swallowed and does
nothing. So the criterion is that the slit be **narrower than the display**,
and a geometry that fails it resolves notch→card like any slitless panel.

**Where the criterion stops, deliberately.** One empty auxiliary rect and one
populated would pass — a slit flush against a screen edge. No Mac reports that,
the header's sentence is about both rects together, and inventing a rule for
hardware nobody ships is the centre-inference's own mistake. If such a panel ever
appears, the rule is re-derived from a measurement of it, not guessed here.

**The window that carries the surface lands on whole points.** AppKit places a
window's origin on whole points, and the edges the API hands over are not
promised to keep a slit's centre and width compatible with that: on macOS 27.0.1
this same 14" panel reports 663.5 pt on each side, a whole-point centre with an
odd slit width, so the Notch's window starts on a half point and is placed half a
point left, its surface with it, onto live menu bar. Every fixed window is
therefore widened, never moved, to a whole-point origin about the same centre,
its pinned edge kept (`CGRect.placeableAsWindow`); `NSPanelPresentationPanelTests`
checks the placed window and the surface's centre on that geometry.

### main-takes-docs-outside-a-release
`main` is the release branch — every merge into it is a release, and it is what
`release.sh` builds from. But it is also the **Pages root**: the landing page and
everything under `docs/` are served from `main`, not from `dev`. So the two roles
disagree whenever documentation changes without code: the site keeps showing the
previous release's material until the next version ships, however long that is:
docs that land only on `dev` — a whole showcase reshot on a new desktop, say —
stay invisible to every visitor until a release.

Decision: **`main` accepts a documentation-only merge outside a release, and the
test is the diff, not the intent.** If the merge touches nothing but the
repository's prose — `docs/` and its assets, the root documents `README.md`,
`CONTRIBUTING.md`, `AGENTS.md`, `CLAUDE.md`, `SPEC.md`, `PLAN.md`, and the
issue forms and pull-request template under `.github/` (`ISSUE_TEMPLATE/`,
`pull_request_template.md` — prose GitHub serves from the default branch, so a
form parked on `dev` leaves the issue page bare exactly the way the site went
stale) — it carries
no code into what the next release stamps, and the release ritual has nothing to do: no version bump, no
build number, no release notes, no appcast, no signature. The published site
stops being hostage to the release cadence.

**What the exception does not cover.** Anything under `Crema/`, `CremaTests/`,
`scripts/`, the project file, or the rest of `.github/` (the workflows and
`dependabot.yml` are operational, not prose) — one such file in the diff and it is a release,
with the whole ritual, or it waits. `release-notes/` and `docs/appcast.xml` are
release artifacts despite their paths: the appcast is signed and regenerated by
`release.sh` (the-feed-signs-itself), so it never travels on a docs merge. The
route stands — the work lands on `dev` through a PR first, and `main`
takes it from `dev`; what this entry removes is the wait, not a step.

The route is also what the remote enforces. A
documentation-only merge reaches `main` through a pull request like any other —
there is no direct push for anyone, the owner included
(the-branch-rules-bind-the-admin-too).

### the-branch-rules-bind-the-admin-too
CONTRIBUTING.md says "nothing lands on `dev` directly", and classic branch
protection with `enforce_admins` off agrees for everyone but administrators —
in a one-administrator project, everyone but the one person who pushes.
Observed (2026-09-12): two local merges pushed straight to `dev` go through with
a "Bypassed rule violations" notice where a contributor would see a rejection,
and a release's appcast commit pushed straight to `main` goes through the same
way. A rule that binds only people who never push here is silent for the one
who does.

Decision: **the protection binds administrators, on `main` and on `dev`**, with
conversation resolution required on both and the branch kept up to date before
merging; squash and rebase are switched off at the repository level so the only
merge is a merge commit. The full state, and the idempotent block that
reapplies it, is docs/GITHUB.md.

What it cost, faced rather than inherited:

- **The release ritual has no direct push.** The appcast commit travels on a
  `release/X.Y.Z` branch through a pull request that `Build & test` gates
  (docs/RELEASE-GUIDE.md §5.4) — four minutes of a suite the release machine
  already ran. The rule that the commit "never parks on a branch" keeps its
  reason: the branch
  lives for one sitting and is deleted if the Release does not go out, because
  the trap it guards against — a feed advertising a version whose Release does
  not exist — is armed by a commit *waiting*, not by a commit *travelling*.
- **`main` comes back into `dev` through a pull request too** (`main` → `dev`),
  never a local merge pushed by hand — the same push the rule rejects.
- **Dependabot targets `dev`**, both ecosystems: the default target is the
  default branch, and a bot cannot land on `main` between releases.

What was deliberately NOT taken from the neighbouring repository that has the
stricter shape (`colatte/brio`: eight required checks, a changed-files gate,
`strict` off on `dev` to save runners): one `Build & test` job stays one job —
it runs lint, format, catalog and suite in four minutes, and splitting it buys
runner-minutes, not signal; `strict` stays on for the same reason; and no review
count is required, because a one-person project cannot require a second person.
Reopening gate for each: a second maintainer, or a suite that outgrows one
runner.

### the-composition-root-draws-a-turn-later
`CremaApp` owns the composition root as `@State private var core = AppCore()`, and
SwiftUI evaluates that initial value inside its scene update: the crash report puts
`AppCore.init` under `AppGraph.sceneList`, called from
`applicationWillFinishLaunching`. An init that builds a panel right there runs the
panel's first `setFrame(display: true)`, which lays out its `NSHostingView` — a
view-graph update nested inside the scene update. Linked against the macOS 27 SDK, AttributeGraph
refuses the nesting and aborts ("precondition failure: setting value during update",
SIGABRT) before the first test or the first frame; the same path linked against the
26.5 SDK runs on macOS 27.0.1 without complaint (the installed 1.6.1). Measured with
Xcode 27.0 on macOS 27.0.1: two suite runs, two aborts in `NSPanelPresentationPanel.init`;
silencing the skins' size report, or deferring it one turn, still aborts; deferring
the first panel roster one main-actor turn runs 1078 tests in 141 suites green.
Decision: `AppCore.init` builds and shows no window synchronously. The first panel
roster and the welcome tour's window wait one `Task { @MainActor }`; the tour's gate
still writes `hasSeenWelcomeTour` inline, before any window, as its own rule requires.
The turn is invisible on screen and costs nothing the roster did not already pay.
Path not taken: moving the root out of `@State` (an app delegate owning it) would also
leave the update, but it changes who owns the root's lifetime to fix one ordering.
A CI image on Xcode 26.3, linked against SDK 26, cannot see this class.
Reopening gate: none for the deferral itself — an SDK that tolerates the nesting
does not make it safe to move inline. Any new window the init would show inherits
the same turn.

### self-signed-runtime-without-library-validation
Turning the runtime off on the self-signed path stops a crash
(`signed-without-hardened-runtime`), and it has a price: without the
runtime, dyld honours `DYLD_*` variables (`man dyld`: they are ignored only for
binaries protected by System Integrity Protection; Apple's Hardened Runtime page:
it prevents "code injection, dynamically linked library (DLL) hijacking"), so any
process of the same user could launch Crema with `DYLD_INSERT_LIBRARIES` and run
code inside the process that holds the Accessibility grant.
Measured with Xcode 27.0 on macOS 27.0.1, one Release build signed three ways with
the real self-signed identity and launched for 6 s with `DYLD_PRINT_LIBRARIES=1`
(a variable that only makes dyld print what it loads): the no-runtime shape
stayed alive, mapped Sparkle and printed 1239 dyld lines; the runtime alone aborted
(exit 134, "different Team IDs" loading `@rpath/Sparkle.framework`), reproducing the
recorded crash; the runtime with `com.apple.security.cs.disable-library-validation`
stayed alive, mapped Sparkle and printed nothing.
Decision: on the self-signed path the app's own executable is signed with
`--options runtime` and `Crema-SelfSigned.entitlements`, which carries that one
exception. The Developer ID path is unchanged (a real Team ID satisfies validation).
The nested code (Sparkle's framework and helpers, the vendored adapter) is
re-signed with Crema's identity on every identity path, and without the runtime
on the self-signed one: it holds no grant. A helper without the runtime honours
`DYLD_*` variables; that residual is recorded under docs/KNOWN-GAPS.md's
"Files inside Crema.app" entry.
What it does not close: turning validation off lets the process load a library of
any signer from its own bundle, so whoever can replace files inside `Crema.app`
still runs code in it, the same class docs/KNOWN-GAPS.md records for the adapter.
Never add `allow-dyld-environment-variables`: it reopens what the runtime closes.
The designated requirement does not read the runtime flag, so the Accessibility
grant should survive the update; not measured on an updated install.
Reopening gate: a Developer ID account, which makes validation pass with a real
Team ID and lets the exception go.

### the-output-glyph-names-only-what-it-knows
The volume HUD draws the kind of device the sound goes to, and two facts bound
what it may claim. A device's name is localized and renamable — the built-in
speakers read "Alto-falantes (MacBook Pro)" on a pt-BR system, and a Bluetooth
device answers to whatever the user typed — so a name is evidence only where
nothing better exists. And CoreGlyphs' `symbol_restrictions.strings` reserves
`airpods`, `airpods.pro` and `airpods.max` for Apple's AirPods, AirPods Pro and
AirPods Max, and `beats.headphones` for Beats headphones: a product glyph on the
wrong device misuses the mark, not only the picture.
Decision: the transport (`kAudioDevicePropertyTransportType`,
AudioHardwareBase.h) decides first. On the built-in device the selected output
data source decides (IOAudioTypes.h: `'hdpn'` is the headphone jack; `'ispk'`,
or no data-source control, the speakers; any other selection, unknown) and the
name never does. On Bluetooth, classic or LE, the name decides by a
case-insensitive match, most specific first — "AirPods Max", "AirPods Pro",
"AirPods" — then Beats' headphone lines, "Beats Solo" and "Beats Studio" without
"Buds": the brand's earbuds and speakers carry marks of their own, reserved like
the headphones'. Any other Bluetooth device is plain `headphones`, the glyph that
claims no product. AirPlay draws `airplayaudio`; HDMI and DisplayPort
draw `display`, a screen that does not call a monitor a television. USB,
Thunderbolt, aggregates and virtual devices keep the speaker family: USB carries
headsets, DACs and a display's speakers on one transport, and an aggregate's main
sub-device is its clock (AudioHardware.h: "the AudioDevice that is currently
serving as the time base"), not where the sound goes. The device glyph replaces
the speaker at every level, since the bar already shows the level; mute keeps
`speaker.slash.fill`. The macOS 14 spellings `airpodspro`, `airpodsmax` and
`airplayaudio` are the ones emitted; macOS 15 and later resolve them as aliases
(`name_aliases.strings`). A device or data-source change re-reads the route in
silence and pops nothing by itself; the next volume event draws it. A volume
notification the switch itself causes is a level event and does pop, and one that
lands before the data-source notification draws the previous glyph.
Paths not taken: `kAudioDevicePropertyModelUID` could name a model without the
name, but its format on Bluetooth is unmeasured; `scripts/probes/output-device-route.swift`
harvests it. The output stream's terminal type (`kAudioStreamPropertyTerminalType`)
reads 0x301 on the built-in speakers, the USB Audio Class speaker code rather
than the header's `'spkr'`, so it does not speak the vocabulary its header
documents (measured with that probe, 2026-10-15, macOS 27.0.1, Mac16,8).
Unmeasured: whether the jack on Apple Silicon is a data source of the built-in
device or a device of its own (a device of its own with no data-source control
draws the speaker); AirPlay, HDMI and DisplayPort transports on real devices; the
order of the data-source and volume notifications when a jack is plugged in.
Reopening gate: a harvested ModelUID table for Bluetooth, or a measured jack on
Apple Silicon.

### the-bar-answers-the-press
The iPhone's volume indicator answers the hand in two ways the level alone does
not: pressed against the end it points to, the bar is pulled past that end and
springs back, and while it is in use it is thicker than when it settles to show
the level. The author asked for both. Apple's own glass describes the same
behaviour, "Liquid Glass responds to interaction by instantly flexing", and
"elements can even lift up into Liquid Glass temporarily, such as when you
interact with a component. This lets the resting state stay visually quiet,
while it comes to life on touch" (WWDC25 "Meet Liquid Glass", session 219).
Decision:
- A press past the end is known only where the key is applied: the suppressor's
  pre-read finds the level already at the end the key points to
  (`onPushedPastEnd`). The reading that follows reports the end, and so does the
  reading after the press that reached it; the boundary refresh emits on both. So
  the press travels on its own path to the Coordinator (`hudPushedPastEnd`), which
  holds `hudPush` for `defaultHUDPushHold` (0.15 s) and refreshes it on every
  repeat, so a held key holds the bar out.
- In use is any HUD published or a drag under way (`hudIsEngaged`); it settles
  `defaultHUDEngagedHold` (0.6 s) after the last, inside the 1.5 s revert, so
  every HUD shows its thin bar before it goes. Both timers run on their own
  injected clock (`motionClock`): they shape motion, never what is presented, and
  on the presentation clock they would be stepped by every test that advances
  "the next parked timer".
- Where a bar has a track, the track answers: the capsule (Card slider, Notch)
  grows from 4 to 6 pt and is pulled 6 pt past the pressed end, inside the row's
  padding and the gap to the glyph. Where the surface is the bar, the surface
  answers: the filled Card grows 4 pt across and is pulled 8 pt along, the pulled
  end alone moving. Classic's segments answer neither; the pre-Tahoe bezel never
  moved.
- The window never moves (hover-follows-the-eye), so every growth fits the room
  it keeps: sideways and below, the open spring's headroom. The upright HUD's top
  end has none, the window hanging from its top edge, so that window keeps 8 pt
  above (`CardMetrics.hudTopHeadroom`), read by the window rule, the click region
  and the view.
- Reduce Motion turns both off: the system's glass "disables any elastic
  properties for the material" under it (same session).
- Motion: the pull is fast and nearly dead, the release under-damped (the
  wobble is the elastic), the settle without overshoot. The growth rides the
  level's spring because it lands in the transaction of the first level change
  after a settle, and one transaction carries one animation.
The sizes and springs are the author's taste against the iPhone, not measured;
a hardware session that finds them too faint or too busy changes the numbers,
not the shape. Paths not taken: inferring the press from a repeated reading at
the end, which fires on the press that reaches it; a keyframe animation per
press, which restarts from rest on each repeat and stutters under a held key; a
scale transform on the filled surface, which stretches its glyph.
