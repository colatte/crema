# HUDs on the lock screen — closed investigation

> **STATUS: CLOSED — NO-GO proven.** No window level composites over the lock
> shield (two probes on real hardware); the correct exit is the lock-aware
> policy that hands the keys back to the system while the screen is locked.
> Closed since it was opened.

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
downgrade from the native behaviour — and unfixable by "showing our HUD there".

## Mechanism (research)
- The lock shield is a **session/policy** boundary (loginwindow/WindowServer),
  not a race between window levels — Apple DTS: third-party code does not draw
  over the lock; the only sanctioned path is `SFAuthorizationPluginView` (an
  authorization plug-in — the wrong tool). The **native** OSD appears under lock
  because OSDUIHelper runs in the LoginWindow session
  (`LimitLoadToSessionType = [LoginWindow, Aqua]` — verified in its plist).
- **WidgetScreen** (indie, macOS 15+, notarized) shows widgets over the lock —
  market proof that *some* mechanism exists on 15+, but demonstrably **not a
  window level** (probe H0 on this machine). The mechanism is unexplained
  without inspecting the binary; it is a curiosity for the future, not a plan.
- Lock detection (the de-facto pattern: stable, non-public — fine outside the
  Mac App Store): `com.apple.screenIsLocked/Unlocked` (edges) +
  `CGSSessionScreenIsLocked` (authoritative state) + `kCGSSessionOnConsoleKey`
  (excludes fast user switching).

## Verdicts
| Item | Verdict |
|---|---|
| (a1) Suspend suppression under lock (palliative → fix) | **GO — bug priority, v1.1** |
| (a2) Crema's HUD over the lock | **NO-GO** (no public path; proven on hardware) |
| (b) Now-playing widget on the lock (opt-in) | **NO-GO / parked** (same mechanism blocker) |
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
