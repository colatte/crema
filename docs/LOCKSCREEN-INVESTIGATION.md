# HUDs on the lock screen — reopened investigation

> **STATUS: REOPENED AND PARTLY SHIPPED, 2026-08-07 — the mechanism this file
> left unexplained has been found, proven on hardware, and taken.** Everything
> below still holds as written: no window LEVEL composites over the shield, and
> there is still no PUBLIC path. What was wrong was the framing, not a fact —
> the barrier is not the level axis at all. Read "The reopening", "The second
> round" and "What shipped" at the end before acting on anything here.
>
> **What changed and what did not.** The opt-in now-playing widget (item b)
> ships on a raised SkyLight space. The **HUDs** over the lock (item a2) do
> not: that stays a product decision nobody has made, and the lock-aware
> suppression policy this file argued for is unchanged. Its justification is
> the part that changed — it was "we cannot draw there", and it is now "we have
> not chosen to draw the HUDs there".

> Investigation concluded on 2026-07-10, with both probes run by the author on
> real hardware (macOS 26.5.2, Apple Silicon). Every decisive claim below is
> **VERIFIED** — by code or by experiment. Distilled here from the author's
> working notes because it is the evidence behind a rule the app still lives by:
> suppression steps aside under lock (`SuppressionLockController`;
> docs/DECISIONS.md: J6-latch-do-edge, unreadable-session-is-unsafe).

## The symptom

With the Mac locked, the volume/brightness keys work (the hardware responds),
but Crema's HUDs do not appear — and with OSD suppression on, the user is left
with NO visual feedback at all: not the native one (Crema suppresses it), not
ours.

## Verified facts

### In the code (as it stood when the investigation opened)
- **Zero lock awareness in the app** (grep for `screenIsLocked`,
  `CGSessionCopyCurrentDictionary`, `sessionDidResignActive` = nothing).
- The tap is `.cgSessionEventTap`/`.defaultTap` on NX_SYSDEFINED; **with
  suppression on it swallows the keys in both phases and the suppressor itself
  performs the write** (read → step → write → verify), which is why volume and
  brightness still change with no HUD.
- Apply+verify had a global **auto-disengage**: a write/read-back failure or the
  2 s timeout turned suppression off **and persisted `suppressesNativeOSD =
  false`** — the risk of a silent self-disable under lock.
- Panels: level `mainMenu+3` (= 27), ordered once and never removed — far below
  the shield; invisible under lock (now playing does not leak through today).

### In the author's probes (real hardware)
- **Window probe (`lockprobe`), H0 confirmed**: a mirror of Crema's panel at
  **five levels** — mainMenu+3 (27), screenSaver (1000), assistiveTechHigh
  (1500), `CGShieldingWindowLevel()` (2147483628) and `kCGMaximumWindowLevel`
  (2147483631) — and **none** composited over the lock screen (visible on the
  desktop before locking in every run = valid test). A user-session window does
  not appear over the lock at any level on this macOS.
- **Key probe (`locktap-probe`), H1 confirmed**: dozens of
  `KEY volume/brightness owned=true` events **between** `SCREEN LOCKED` and
  `SCREEN UNLOCKED`, heartbeat alive — **the session tap goes on receiving (and
  is able to consume) the media keys while the screen is locked**.
- Bonus from the logs: lock detection behaved exactly as designed —
  `com.apple.screenIsLocked/Unlocked` notifications on the edges, a
  `CGSSessionScreenIsLocked` poll as the authoritative state, `onConsole=1`
  stable.

### The end-to-end conclusion, proven
With suppression on and the screen locked, Crema **consumes** the keys (the tap
is alive), **suppresses** the native OSD, **applies** the writes, and **cannot**
show its own HUD (no public window path over the shield). That is a real
downgrade from the native behaviour — and not fixable by any window level, which
is what "showing our HUD there" meant when this was written. A private path does
exist; see "The reopening".

## Mechanism (research)
- The lock shield is a **session/policy** boundary (loginwindow/WindowServer),
  not a race between window levels — Apple DTS: third-party code does not draw
  over the lock; the only sanctioned path is `SFAuthorizationPluginView` (an
  authorization plug-in — the wrong tool). The **native** OSD appears under lock
  because OSDUIHelper runs in the LoginWindow session
  (`LimitLoadToSessionType = [LoginWindow, Aqua]` — verified in its plist).
- **WidgetScreen** (indie, macOS 15+, notarized) shows widgets over the lock —
  market proof that *some* mechanism exists on 15+, but demonstrably **not a
  window level** (probe H0 on this machine). This paragraph used to end "the
  mechanism is unexplained without inspecting the binary". It is explained now,
  and no binary had to be opened: see "The reopening".
- Lock detection (the de-facto pattern: stable, non-public — fine outside the
  Mac App Store): `com.apple.screenIsLocked/Unlocked` (edges) +
  `CGSSessionScreenIsLocked` (authoritative state) + `kCGSSessionOnConsoleKey`
  (excludes fast user switching).

## Verdicts
| Item | Verdict |
|---|---|
| (a1) Suspend suppression under lock (palliative → fix) | **GO — bug priority, v1.1** |
| (a2) Crema's HUD over the lock | **NO public path** (proven on hardware) · a PRIVATE one exists and is proven too — see "The reopening"; the verdict is now a choice, not a wall |
| (b) Now-playing widget on the lock (opt-in) | **SHIPPED** — the mechanism blocker named here is gone, the second round of probes closed the behaviour questions, and the private space API was taken for this and only this. See "What shipped" |
| (c1) Replacing the SYSTEM's lock wallpaper | **NO-GO** — unaddressable; nothing here reaches loginwindow's own background |
| (c2) Our own artwork filling the lock screen | **SHIPPED** — a raised-space window of our own, which is a different claim from (c1) and was hiding inside it |
| (c3) Animated / motion covers | **NO-GO**, and not for the reason this row used to give. See "Animated artwork" |

## Stage 1 — the design (validated by the probes)
- `ScreenLockSource` behind a protocol (edges + authoritative poll + onConsole
  guard), mocked in tests — the source pattern of CLAUDE.md.
- Locked (or off the console): **suspend suppression** without touching the
  user's preference → the keys go back to the system → the native OSD appears →
  feedback restored. Unlocked: re-engage if (and only if) the preference is on.
  A user with suppression off: zero change.
- It kills a second problem on the way: the auto-disengage risk under lock
  (suspended means no apply → no failure → no silent write to the preference).
- Care needed: no flicker on unlock (re-engage after unlocked + onConsole);
  auto-disengage inert during the transition.

## Probe record
The throwaway sources and binaries lived in a scratch folder on the author's
machine, outside the repository, and can be deleted; the decisive logs are
quoted above (2026-07-10, ~10:43–10:57 local).

---

## The reopening (2026-08-07) — the axis was wrong

This file swept `NSWindow.level` across five values and concluded that no window
path exists. The sweep was sound and its result stands; the inference did not,
because **level and the shield answer to different things**:

- `NSWindow.level` orders windows **within** a space.
- The lock shield **is a space**, at absolute level 300.

No window level can lift a window out of the space it lives in. Holding the
space at the default (absolute level 0) and varying only the level cannot tell
"impossible" apart from "wrong knob" — every one of the five readings was a
window sitting in the same space as before, losing to the shield for a reason
the sweep never varied.

SkyLight exposes the other knob. The ladder of absolute space levels, read off
`Lakr233/SkyLightWindow` (MIT):

| level | occupant |
|---|---|
| 0 | default — where all five probe windows stayed |
| 100 | setup assistant |
| 200 | security agent |
| **300** | **the lock shield** |
| **400** | notification centre, at the screen lock |
| 500 | boot progress |
| 600 | VoiceOver |

The recipe is five calls plus one public property:

```swift
let connection = SLSMainConnectionID()
let space = SLSSpaceCreate(connection, 1, 0)
SLSSpaceSetAbsoluteLevel(connection, space, 400)     // above the shield's 300
SLSShowSpaces(connection, [space] as CFArray)
SLSSpaceAddWindowsAndRemoveFromSpaces(connection, space, [win.windowNumber] as CFArray, 7)
// and on the NSWindow, the public half this file also missed:
window.canBecomeVisibleWithoutLogin = true
```

**Proved on hardware, 2026-08-07** (macOS 26, Apple Silicon), by
`scripts/probes/lockscreen-space.swift`. The probe draws two markers and the
control is what makes the result mean anything: one window moved into the raised
space, one ordinary window at `kCGMaximumWindowLevel` — the best of the five this
file already tried. Both visible before locking. **After locking, only the raised
one survived.** The control vanishing beside it is the whole finding: same
machine, same OS, same moment, one variable.

### What this does and does not change

- **"No PUBLIC path" survives intact.** SkyLight is private, dlopen'd, and this
  file's care with that word is the reason the sentence did not have to be
  retracted. The Apple DTS position quoted above is unchanged.
- **The private-API objection is weaker here than it looks.** This app already
  resolves DisplayServices and CoreBrightness exactly this way — dlopen, dlsym,
  every symbol checked, nil ⇒ the capability reports unavailable and degrades.
  A sixth private framework is not a new category of risk for this codebase; it
  is the category the codebase is built on. All five symbols were confirmed
  present on macOS 26 before the probe ran.
- **The lock-aware suppression policy stays** (`SuppressionLockController`), and
  every mechanical claim behind it stays: the tap keeps receiving keys under
  lock, the writes still land, the native OSD is still what the user gets. What
  changes is the JUSTIFICATION. It was "we cannot draw there". It is now "we
  have not chosen to draw there" — a product decision about spending a private
  space API on a security surface, which nobody has made yet. Anyone re-reading
  the old wording would have concluded the question was settled; it is not.
- **Not proven, and not to be assumed:** that HUDs over the lock are a good
  idea; that this survives a macOS update; that a raised space behaves for
  hover, click routing or multi-display the way the app's panels do today. The
  probe answers one question — whether pixels reach the lock screen — and
  nothing else. (Two of these were closed by the second probe, below. The macOS
  update remains open by nature.)

---

## The second round (2026-08-07) — do events reach, and does a big one behave

The paragraph above named three unknowns and the widget's design rested on two
of them: its expanded state exists only if a click lands, and expanding covers
the display, which a 460×120 marker never tested.
`scripts/probes/lockscreen-events.swift` settled both, with the same control
discipline — it reads the session dictionary itself and stamps every click with
the lock state at the moment it arrived, so a silent log is distinguishable from
a broken probe.

**Measured by the author on hardware** (macOS 26, Apple Silicon):

- **5 clicks logged `unlocked`** — the control. Clicks reach this window at all.
- **10 clicks logged `LOCKED`** — events reach a raised-space window over the
  shield. The expanded state is viable.
- **Both windows stayed visible across three lock/unlock cycles**, so a
  screen-sized window in the raised space behaves like the small one.
- **macOS drew no media controls of its own** on the lock screen. This is not a
  second player competing with the system's.
- **Not answered: sleep, wake and hotplug.** No such edge fired during the run,
  so the log carries no evidence either way. Left open deliberately rather than
  guessed at, and covered by action instead of by a read — see below.

A FOURTH probe, `lockscreen-geometry.swift`, answered where the surface may sit.
The card had been placed 96 pt off the bottom from a mock, with a comment
claiming that cleared the avatar and the password field; on hardware the
opposite was true, because Sonoma moved the login UI DOWN. The ruler draws
labelled bands and candidate rects over the shield and the author reads it.
**Measured 2026-08-07:** the login never leaves the centre column (the
horizontal invariant every version has kept), a card at 96 pt lands on the
avatar, and a 300 pt square centred on the display touches nothing. That is why
the collapsed card now rests at 300 pt and the expanded state is a 300 pt tile
centred rather than a cover stacked over a card (docs/DECISIONS.md:
the-lock-screen-is-a-space).

**Re-run 2026-08-08**, because that first run answered three of its own five
questions and the silence read as an answer. It now records the display size
(1512×982), puts the login's top at or below 180 pt, and reads candidate B clear
at 220 — so 300 clears the login by at least 120 pt rather than by a margin
nobody had measured. Two claims died with it. The stack was rejected here for
"its bottom edge lands back on the login": on the real panel it centres to
259…723 and clears the login by 79 pt, so the true reason is the other end — 723
leaves the 641 ceiling the ruler proved — plus the interaction one, that a hero
above a card is a large picture ignoring every click aimed at it. And a "72% of
the height" that had reached CLAUDE.md turned out to be 1 − 250/900 off a test
fixture, not a reading.

The backdrop no longer erases the login. It clears the band below
`clearBandFloor` and ramps back to opaque above it, and because that layer covers
the system's clock, the surface draws its own — in the expanded state only, since
that is the only state that covers anything. Not a second player competing with
macOS: it exists exactly where, and only where, Crema hid the original.

A third probe, `lockscreen-mouse-routing.swift`, was needed once the surface
shipped, and its question is the mirror of the second one's: not "do clicks
reach a window that wants them" but "can a window that deliberately REFUSES them
still learn where the cursor is". A screen-sized clear window captures every
click on the display, so the panel has to stay click-through and open only over
the card — which requires tracking the cursor while capturing nothing. Apple
documents that a global event monitor "would not be able to detect Command-Tab
or a system alert", and the lock screen is loginwindow's UI, so this was a real
doubt. **Measured 2026-08-07: it does not generalize.** While locked, with a
window in exactly that configuration: 1092 global mouse-moved events, 281 local,
and 117 live readings from `NSEvent.mouseLocation` polling — all three
mechanisms alive, the third being a standing fallback if delivery ever stops.

The probe splits into two windows on purpose, and the split is a safety property
rather than a convenience: the screen-sized one sets `ignoresMouseEvents`, so it
can never swallow a click meant for the password field. A screen-sized window
that ate events over the lock shield would be a probe that locks you out of your
Mac.

---

## What shipped

Item (b), opt-in and born off (`showsLockScreenWidget`). The pieces:

| | |
|---|---|
| `Crema/Sources/SkyLight/SkyLightSpace.swift` | The private edge, behind `RaisedSpace` like every other system contact — dlopen, dlsym, **every one of the five symbols checked**; any nil ⇒ `isAvailable == false` and the feature is simply not offered |
| `Crema/Windows/LockScreenPanel.swift` | One screen-sized borderless panel, `canBecomeVisibleWithoutLogin = true` |
| `Crema/Windows/LockScreenPresenter.swift` | Owns the window's whole lifetime; the policy is the pure `LockWidgetPresence.shouldPresent(enabled:locked:spaceAvailable:)` |
| `Crema/Styles/LockWidgetView.swift` | The surface: collapsed card, expanded cover, both states |

Three decisions worth not re-deriving:

- **It reads the raw `locked` bit, never `!isSuppressionSafe`.** That predicate
  collapses locked with off-console, and drawing this user's listening onto
  another account's lock screen after a fast user switch is a worse mistake than
  not drawing at all. The pair survives in `ScreenLockSessionTranslation.decode`.
- **A second reader of the lock needs a mirror, not a second `for await`.**
  `ScreenLockSource.updates` is a single-consumer `AsyncStream` the suppression
  controller already owns; a second loop would silently split the values. The
  house template is `LowPowerModeMirror`, and `LockScreenMirror` follows it —
  reported **before** the reconciler, deliberately, because the reconciler
  deduplicates on `safe` and would swallow a lock→lock-with-different-console
  edge this mirror needs to see.
- **The sleep/wake unknown is covered by action, not by a read.** Whether a
  raised space survives a display sleep is state living in the WindowServer, and
  the J7 lesson in this codebase is that such state cannot be audited from
  inside the process — a local read answers "fine" either way. So the panel
  re-adopts its space unconditionally on all four edges the media-key tap
  already reinstalls on (`docs/DECISIONS.md: preventive-reinstall`,
  `J7-estado-do-outro-lado`). `adopt` is idempotent; acting costs one cheap
  call, trusting a local read costs a surface that silently stopped appearing.

## Animated artwork

Row (c) used to read "only static art via MediaRemote — no Canvas or animated
covers", stated as a limitation of the bridge. That is one of three walls, and
not the load-bearing one. Any of them alone is fatal, so this does not reopen
when a new bridge appears:

- **Apple withholds the data from every third party.** `editorialVideo`, where
  motion artwork lives, is not exposed to third-party apps through the Apple
  Music API — developer token or not. For albums, the only extended attribute a
  third party can load is `artistUrl`.
- **`MPMediaItemAnimatedArtwork` is a provider API.** It is how a music app
  hands animation *to* the system. Crema observes whatever is playing and never
  receives it. It is also iOS-only.
- **The bridge has no such key.** The vendored adapter emits 45 fields and
  exactly one image: `artworkData` + `artworkMimeType`. No artwork identifier,
  no URL, no animated variant — and `MRMediaRemoteGetNowPlayingInfo` takes no
  options dictionary, so there is no size to negotiate and the dimensions
  received are not even reported. Apple Music's motion art never crosses the
  MediaRemote boundary.

The consequence for what shipped: the expanded state's slow drift on the blurred
backdrop is the honest form of the idea on this platform, not a consolation
prize for a missing feature. And the same paragraph explains the **cover
lookup** (`ArtworkLookup`, opt-in, off by default): the size is not negotiable
at the MediaRemote boundary either, so a larger cover has to come from somewhere
else entirely.
