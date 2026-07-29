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
consumer preserved by construction) at every physical edge that can have
re-routed delivery — the four triggers: display wake (`screensDidWake`), system
wake (`didWake`), the unlock/return edge, and a display-topology change
(`didChangeScreenParameters`, the hotplug with no sleep that fires neither wake
nor lock) — independent of the suppression preference: the deafness kills plain
brightness observation too, so pref-off must still reinstall. Order is pinned:
unlock → reinstall → re-engage.

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

### signed-without-hardened-runtime
Self-signed distribution must NOT enable the hardened runtime. `--options
runtime` turns on dyld library validation, which demands a real matching Team
ID between the process and every non-platform library it maps — a self-signed
certificate has none, so the app crashes at launch loading Sparkle.framework
("mapping process and mapped file (non-platform) have different Team IDs"),
even with every component signed by the same identity. This is the J7 lesson
on another frontier: load policy lives on dyld's side of the boundary, and
`codesign --verify --deep --strict` passes the exact bundle that cannot launch
(it checks integrity, not load policy) — no local verification can see it.
Covered by action at the edge instead: release.sh sets the runtime flag only on
the Developer ID path, the consistency check compares authority + Team across
the nested Mach-Os, and the launch smoke boots the installed app from the
final dmg and requires it to survive 5 s. Shipped broken exactly once — the
v1.2 E2E caught the crash before publish, which is why the smoke exists.

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
tick recomputes `position + age × rate`, clamped to the duration, with a
non-negative age so a backward wall-clock jump freezes instead of rewinding. A
late tick lands on the truth, a dropped tick costs nothing, and two ticks in the
same instant count once. This is the contract of the data model, not an
invention: MediaRemote publishes elapsed WITH a timestamp and a rate, and the
adapter's own help says to compute the current time from that pair rather than
poll. Re-anchoring happens only where a payload's line is ACCEPTED by the
reconciliation — when it holds the previous value, the old anchor stays, or the
elapsed time under it would be discarded. The JXA fallback needs none of this:
it re-polls the player's real position every 2 s.
