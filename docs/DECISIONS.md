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
`codesign --verify --deep --strict` passes the exact bundle that cannot launch,
because it checks integrity and not load policy.
Covered at three edges. release.sh sets the runtime flag only on the Developer ID
path, compares authority + Team across the nested Mach-Os, and boots the
installed app from the final dmg requiring it to survive 5 s. CI rejects the
pairing statically: `adhoc` and `runtime` together in the code directory is
enough to condemn a build, and unlike the load failure itself that pairing is
plainly readable from `codesign -d`. And the project no longer sets
`ENABLE_HARDENED_RUNTIME`, which is what made Xcode's own Product → Archive
produce the unlaunchable app while release.sh escaped by archiving unsigned.
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
own brightness curve while Crema draws the bar. What ships is the inbound half,
for the built-in display. The contract below was measured on the wire against
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
source exists. **Other displays are dropped**: `display == nil` is the domain's
word for the built-in screen and the brightness actuator refuses every other
target, so an external-display HUD would arrive with a slider that throws on the
first drag — Crema draws a bar only where it can also move it, and the rest waits
for the outbound half (ROADMAP.md). No preference gates any of this: with
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
stopped at. And a refusal is not fatal: the neighbour's command channel is a
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

### hud-belongs-to-its-display
The app has ONE state and one panel per screen, so every panel drew every HUD.
Harmless while nothing named a display — and wrong the moment something did: a
brightness bar for the external monitor, drawn on the laptop, is a control for a
screen the user is not looking at, and its drag would dim the neighbour in
silence. Rule: a HUD that NAMES a display (`display != nil`) is shown only on
that display; every other panel treats the state as `.hidden`, which also disarms
hover there, so an empty region never reacts to the pointer. A HUD naming NO
display keeps appearing everywhere, deliberately: `nil` is overloaded — volume
belongs to no display at all and the built-in brightness reads the same — so
scoping it would move feedback nobody asked to move, and the asymmetry is the
honest reading of an ambiguous field rather than an oversight. A HUD naming a
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
tick recomputes `position + age × rate`, clamped to the duration, aged with a
non-negative age and — while the rate is forward — floored at the position
already shown. Both floors are needed, and the non-negative age was once
mistaken for covering both: `now` is the WALL clock, which an NTP step
correction or a manual time change moves, and bounding the age only stops a
future-dated anchor from sampling below its OWN position — a clock stepping BACK
still rewound the bar by all the age it had accumulated (anchor 10 s, ticked to
40 s, clock back 30 s, sampled 10 s), which on a source that re-anchors only on
state changes is most of a track. The floor is the shown line, never a
high-water mark: every anchor write rewrites that line too, so a legitimate
backward re-anchor — a payload the reconciliation accepts, a seek, a failed
seek's rollback — lowers the floor with it, where a remembered maximum would
strand the bar above the truth for the rest of the track. The origin is kept
rather than re-anchored on the backward edge, and the reason is this decision
itself: a single backward step would actually be corrected exactly by moving the
origin, but moving it makes the tick accumulate again, so a noisy clock ratchets
the bar forward — sampling from a fixed origin is what makes every tick
self-correcting. The residual is accepted: after a one-way step back the bar
sits behind by the step size until the next payload, the same error the rewind
left, minus the visible jump. A negative rate (a rewind scan) is exempt from the
floor: there the bar moves back honestly, aged with the same sign the payload
math uses, and the non-negative age is what keeps a backward clock from
advancing it. A late tick lands on the truth, a dropped tick costs nothing, and
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
part of the tick's arithmetic at all. A monotonic FLOOR was tried first and
removed: it could only stop the backward half, and it needed a `rate > 0`
exception so a rewind scan could still walk the bar back. One clock that cannot
lie replaces both.

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
  in effect: the suppression row needs the preference AND a suppressor in the graph
  AND the permission, and a domain suspended by a failed apply takes the claim away
  entirely (the warning is the news then).
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
