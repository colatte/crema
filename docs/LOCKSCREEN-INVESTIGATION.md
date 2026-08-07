# HUDs on the lock screen — reopened investigation

> **STATUS: REOPENED 2026-08-07 — the mechanism this file left unexplained has
> been found and proven on hardware.** Everything below still holds as written:
> no window LEVEL composites over the shield, and there is still no PUBLIC path.
> What was wrong was the framing, not a fact — the barrier is not the level
> axis at all. See "The reopening" at the end before acting on anything here.
> The lock-aware policy the file argued for stays; its justification changes.

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
| (b) Now-playing widget on the lock (opt-in) | **OPEN** — the mechanism blocker named here is gone; what is left is whether to take a private space API for it |
| (c) Artwork as the lock's background | **NO-GO** (unaddressable layer; only static art via MediaRemote — no Canvas or animated covers) |

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
  nothing else.
