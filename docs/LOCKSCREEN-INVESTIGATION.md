# The lock screen — what the hardware says

> The measured facts about drawing over the macOS lock shield, kept because a
> codebase without the feature cannot rederive them. The app draws nothing over
> the shield, by decision (docs/DECISIONS.md:
> the-lock-screen-was-built-and-taken-out); these facts are the evidence behind
> lock-aware suppression (`SuppressionLockController`; docs/DECISIONS.md:
> J6-latch-do-edge, unreadable-session-is-unsafe) and the starting point of any
> attempt to reopen the surface. Every measurement below was taken by the author
> on Apple Silicon under macOS 26; a macOS release is the signal to re-measure
> before leaning on any of them. The probes named here are not in the tree:
> `lockprobe` and `locktap-probe` lived outside the repository, and the four
> `scripts/probes/lockscreen-*.swift` are in git (`bb7bb73^`).

## Why suppression steps aside under lock

With the Mac locked, the session event tap keeps receiving the volume and
brightness keys, and with suppression on Crema consumes them, suppresses the
native OSD and applies the writes itself. No window of the app's composites over
the shield, so without lock-aware suppression the user gets no feedback at all.

- **The tap keeps receiving under lock** (`locktap-probe`, 2026-07-10, macOS
  26.5.2): dozens of `KEY volume/brightness owned=true` events between
  `SCREEN LOCKED` and `SCREEN UNLOCKED`, heartbeat alive. The session tap receives,
  and can consume, the media keys while the screen is locked.
- **The lock-detection stack behaves as designed** (same run):
  `com.apple.screenIsLocked`/`Unlocked` fire on the edges, the
  `CGSSessionScreenIsLocked` poll flips as the authoritative state, and
  `kCGSSessionOnConsoleKey` stays stable (it excludes fast user switching). This
  is the stack `DistributedNotificationScreenLockSource` wires.
- **The native OSD appears under lock** because OSDUIHelper runs in the
  LoginWindow session (`LimitLoadToSessionType = [LoginWindow, Aqua]`, read in its
  launchd plist). The shield is a session and policy boundary
  (loginwindow/WindowServer), not a race between window levels; Apple DTS's
  position is that third-party code does not draw over the lock, and the one
  sanctioned path, `SFAuthorizationPluginView`, is an authorization plug-in.

## No window level reaches the shield

`lockprobe` (2026-07-10, macOS 26.5.2) mirrors Crema's panel at five levels —
`mainMenu+3` (27, the panels' own level), `screenSaver` (1000),
`assistiveTechHigh` (1500), `CGShieldingWindowLevel()` (2147483628) and
`kCGMaximumWindowLevel` (2147483631). Each is visible on the desktop before
locking, which makes the run valid, and none composites over the lock screen.

## The shield is a space

`NSWindow.level` orders windows **within** a space, and the lock shield **is** a
space, at absolute level 300; no window level lifts a window out of the space it
lives in. The ladder of absolute space levels, read off `Lakr233/SkyLightWindow`
(MIT):

| level | occupant |
|---|---|
| 0 | default, where every window of the level sweep stays |
| 100 | setup assistant |
| 200 | security agent |
| **300** | **the lock shield** |
| **400** | notification centre, at the screen lock |
| 500 | boot progress |
| 600 | VoiceOver |

A private SkyLight space at 400 composites over the shield
(`lockscreen-space.swift`, 2026-08-07): one window moved into the raised space,
one ordinary window at `kCGMaximumWindowLevel` as the control, both visible before
locking, only the raised one after. The calls are `SLSMainConnectionID`,
`SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel`, `SLSShowSpaces` and
`SLSSpaceAddWindowsAndRemoveFromSpaces`, plus the public
`canBecomeVisibleWithoutLogin = true` on the window, without which AppKit does not
show it while no session is logged in. There is no PUBLIC path.

## A window in the raised space

- **Clicks reach it while locked** (`lockscreen-events.swift`, 2026-08-07): 10
  clicks logged `LOCKED`, against 5 logged `unlocked` as the control. The probe
  reads the session dictionary itself and stamps each click with the lock state,
  so a silent log is distinguishable from a broken probe.
- **A screen-sized window behaves like a small one**: both stayed visible across
  three lock/unlock cycles (same run).
- **macOS draws no media controls of its own** on the lock screen (same run).
- **The cursor is readable from a window that refuses clicks**
  (`lockscreen-mouse-routing.swift`, 2026-08-07): with a screen-sized window set to
  `ignoresMouseEvents`, while locked, 1092 global mouse-moved events, 281 local, and
  117 live readings from polling `NSEvent.mouseLocation`. A screen-sized window
  that took events over the shield could swallow the clicks meant for the password
  field, so the click-through split is a safety property.
- **Not measured: sleep, wake and hotplug.** No such edge fired during the runs.

## Where the login sits

`lockscreen-geometry.swift` draws labelled bands over the shield for the author
to read (2026-08-08, a 1512×982 panel): the login never leaves the centre column,
its top edge sits at or below 180 pt, and a rect at 220 pt reads clear. The
2026-08-07 run puts a surface 96 pt off the bottom on the avatar.

## The open question

Whether a SkyLight space BELOW level 300 composites BEHIND the shield. Nobody has
run it; `lockscreen-space.swift` takes the level as a parameter. If a lower space
shows through, the system draws the login on top of whatever sits there.
