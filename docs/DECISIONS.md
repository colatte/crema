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
capture for the session. (Covers *disabled*; the *invalidated* and
*enabled-but-deaf* deaths are J7.)

### J2-display-id-stale
A system-resource identifier captured once at init (a `displayID`, a keyboard
backlight ID) goes stale when the hardware topology changes — the frozen ID
addresses a resource that no longer exists.
Decision: resolve the resource **per operation**, never freeze it at init.
Read/write re-resolve the ID each time (the screen-brightness bridge is the
reference; the keyboard bridge is the latent sibling to bring to parity).

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

## Named decisions

### per-domain-suspension
An apply failure suspends **only** the channel that failed (volume /
screen-brightness / keyboard-brightness; mute rides with volume): its keys return
to the system for native feedback while the other domains stay suppressed, and a
read-only backoff probe (1→16 s, then 30 s) silently re-engages on recovery.
Rationale: a keyboard-brightness failure must never kill volume suppression —
that was the J5 blast radius. Only a durable suspension with the channel present
surfaces in the menu.

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
consumer preserved by construction) at the unlock edge and at wake, independent
of the suppression preference — the deafness kills plain brightness observation
too, so pref-off must still reinstall. Order is pinned: unlock → reinstall →
re-engage.

### settle-rereads
The lock source never lets a notification edge flip state directly: each edge
fires an authoritative `CGSession` re-read, and because the notification can
arrive before the dict reflects the change, the edge schedules settle re-reads (a
short backoff plus a periodic tail) until the settled read emits the transition
the stale read missed. Same class of safety poll as the tap health-check — the
cure for J6.

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
threads block, so an orphan there never steals capacity from live work. Async
operations use unstructured detached tasks instead. (The applied form of
J3-deadline-cooperativo.)

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

### ghost-discard
End-of-stream means unavailability, with no unrepresentable ghost left behind.
When the active media source ends — death, total outage, or promotion hand-off —
the Coordinator discards the snapshot and disarms click-invoke, never leaving
armed controls that would resurrect a dead expanded player no live source can
represent.

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
*HUD* look — a thumbless 4 pt capsule whose fill ends flat inside the clip —
not the system's *control*, whose pill thumb was exactly the misalignment
reported; owning the drawing also removes the exposure that produced the bug
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
on the notch (lateral 8 over the clickable menu bar, bottom 16 over app
content, top 0 at the pinned screen edge; comfort 6 on enter everywhere) and
uniform 10 elsewhere; every band on a movable edge absorbs the open spring's
overshoot (pinned). Calibration-in-test: any finished hover re-arms the
REACTIVE linger at 1.5 s instead of a fresh 3 s (the invoked appearance keeps
its full tail, provenance-flagged rather than value-compared — its pointer is
born on the surface from the click, so a cap would make the invoked linger
unreachable again, a production bug already pinned), and the close spring
tightened 0.45→0.35. Two
hypotheses stay deliberately unimplemented pending a hardware probe: the
multi-display pointer mirror and mouseMoved delivery to an inactive accessory.
