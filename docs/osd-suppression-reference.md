# Reference — native OSD suppression

> Research document on suppressing the native volume/brightness/keyboard
> HUD. **No technique here requires disabling SIP, touching /System or
> asking for permissions beyond the Accessibility grant Crema already
> uses.** Research performed 2026-07 (macOS 26 "Tahoe" 26.5.2 current,
> local verification on an MBP 14" M4 Pro); sources cited per claim.
> Constraints: no SIP off, reversible and opt-in, no dangerous
> permissions, distributable.

## 0. Licenses of the cited projects — read before opening any repo

Same rule as design-reference §0: Crema is written from scratch and **never
copies, transcribes or adapts third-party code** — not from the copyleft
projects, not from the permissive ones. What gets used from this document is
**principles, facts and values** described in prose.

| Project                                                                                                            | License (SPDX)                | Type          | Permitted use in Crema                                                      |
| ------------------------------------------------------------------------------------------------------------------ | ----------------------------- | ------------- | --------------------------------------------------------------------------- |
| [SlimHUD](https://github.com/AlexPerathoner/SlimHUD)                                                               | **GPL-3.0**                   | ⚠️ Copyleft   | Principles/facts only — **never code**                                      |
| [Atoll](https://github.com/Ebullioscopic/Atoll)                                                                    | **GPL-3.0**                   | ⚠️ Copyleft   | Principles/facts only — **never code**                                      |
| [MewNotch](https://github.com/monuk7735/mew-notch)                                                                 | **GPL-3.0**                   | ⚠️ Copyleft   | Principles/facts only — **never code**                                      |
| [boring.notch](https://github.com/TheBoredTeam/boring.notch)                                                       | **GPL-3.0**                   | ⚠️ Copyleft   | Principles/facts only — **never code**                                      |
| [volumeHUD](https://github.com/dannystewart/volumeHUD)                                                             | MIT                           | Permissive    | **Best reading reference** (Tahoe-native; policy: no copying)               |
| [MonitorControl](https://github.com/MonitorControl/MonitorControl)                                                 | MIT                           | Permissive    | Reading reference (key consumption, repeat, Option+Shift)                   |
| [MediaKeyTap](https://github.com/nhurden/MediaKeyTap) (+ [MC fork](https://github.com/MonitorControl/MediaKeyTap)) | MIT                           | Permissive    | Legally usable even as a dependency; Crema already has its own tap          |
| [FreeDisplay](https://github.com/huberdf/FreeDisplay)                                                              | MIT                           | Permissive    | Reading reference (keyboard-brightness keys via tap)                        |
| [Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements)                                               | Unlicense                     | Permissive    | Mechanism (DriverKit) out of Crema's scope; context only                    |
| [Lunar](https://github.com/alin23/Lunar)                                                                           | MIT in the repo, freemium app | ⚠️ Ambiguous  | Treat as source-available; do not reuse without confirming the component    |
| [NewBezelServices](https://github.com/MLforAll/NewBezelServices)                                                   | no declared license           | ⚠️ Reserved   | Architecture facts only (the OSDUIHelper XPC); no code                      |
| [cleanHUD](https://github.com/w0lfschild/cleanHUD)                                                                 | no license (all rights res.)  | ⚠️ Reserved   | Nothing — no releases since 2020 and requires SIP off                       |
| [MacForge](https://github.com/MacEnhance/MacForge)                                                                 | MIT                           | Permissive    | Out of scope — requires SIP + Library Validation off; no recent releases    |
| MediaMate ([FAQ](https://wouter01.github.io/MediaMate/faq))                                                        | proprietary (Gumroad)         | Proprietary   | Observable behaviour only (claims "no tampering with SIP"; closed mechanism) |
| BetterDisplay ([repo](https://github.com/waydabber/BetterDisplay))                                                 | proprietary (repo issues-only) | Proprietary  | Issues/wiki only                                                            |
| Hudlum ([Many Tricks](https://manytricks.com))                                                                     | proprietary (freeware)        | Proprietary   | Public pages only; mechanism undocumented                                   |

## 1. How the native OSD works

### 1.1 The classic pipeline (pre-Tahoe)

- The volume/brightness/keyboard HUD is drawn by **OSDUIHelper.app**
  (`/System/Library/CoreServices/`), which listens on the Mach service
  `com.apple.OSDUIHelper` via `NSXPCListener` and implements the private
  protocol `OSDUIHelperProtocol` — central method
  `showImage:onDisplayID:priority:msecUntilFade:withText:` (the `OSDImage`
  enum, values 1–28). The client-side wrapper is the private **OSD.framework**
  (`OSDManager`). Canonical reverse engineering:
  [ffried.codes, "The internals of the macOS HUD"](https://ffried.codes/2018/01/20/the-internals-of-the-macos-hud/)
  (2018 — the rendering details **no longer** hold on Tahoe, see §1.2).
- **The launchd domain decides the privilege**: OSDUIHelper is a **per-user
  LaunchAgent in the gui domain** (`/System/Library/LaunchAgents/com.apple.OSDUIHelper.plist`:
  `LimitLoadToSessionType [LoginWindow, Aqua]`, `MachServices`,
  `EnablePressuredExit true`), **demand-launched** — it does not come up at
  boot; it is born on the first HUD request. Because it runs as the logged-in
  user, an ordinary process can `launchctl kickstart` it and send it signals
  **without sudo, without TCC, without SIP** (`kill(2)` allows signalling
  processes of the same user; verified locally on 26.5.2).
- Who **sends** the OSD request is not publicly documented;
  [NewBezelServices](https://github.com/MLforAll/NewBezelServices) documents
  that the system routes the events to the Mach service — whoever holds the
  name receives them.
- macOS 14.4's restriction on `launchctl kickstart -k`
  ([kevinmcox.com](https://www.kevinmcox.com/2024/03/changes-to-launchctl-kickstart-in-macos-14-4/))
  hits ~153 **system** daemons; the per-user gui agent is not affected
  (kickstart on `gui/UID/com.apple.OSDUIHelper` returned 0 on 26.5.2).

### 1.2 What changed in macOS 26 (Tahoe) — the fact that reorders everything

- Tahoe replaced the 25-year-old centred bezel with a **Control Center-style
  popover in the top-right corner** — the change that spawned the 2025–26 wave
  of apps (volumeHUD, Hudlum, Notchy).
- **The new renderer is ControlCenter, not OSDUIHelper.** Evidence
  (local forensics, 26.5.2 build 25F84): the ControlCenter binary contains
  `ControlCenterApp/SystemBannerService+OSD.swift` and the full set of
  `OSDUIHelperProtocol` selectors (including the classic bezel's
  `filledChiclets:totalChiclets:locked:` variant) — that is, ControlCenter
  implements the OSD protocol itself. Ecosystem corroboration:
  [Atoll PR #48](https://github.com/Ebullioscopic/Atoll/pull/48)
  ("Works without the OSDUIHelper Disabler… also works on macOS Tahoe") and
  [volumeHUD](https://github.com/dannystewart/volumeHUD), built FOR Tahoe,
  which suppresses by interception alone and never even mentions OSDUIHelper.
- **Forensics correction (2026-07-20, hardware, uid 501).** This section
  originally read that OSDUIHelper would sit **idle** on Tahoe (`state = not
  running` in normal use) — which on its own would make SlimHUD's freeze a
  no-op. The July 2026 forensics refines the fact **and** proves the
  conclusion by another route: OSDUIHelper is a **demand-launched** agent — it
  may be "not running" because nobody has invoked it, but when invoked it
  comes up **alive, active and 100% freezable/reversible** (kickstart →
  `state = running`, `endpoint active = 1`; SIGSTOP/SIGCONT and
  SIGKILL+respawn confirmed). The decisive question — *does freezing it
  suppress Tahoe's per-key popover?* — was then tested directly: with the
  helper **alive and frozen** (SIGSTOP), the per-key OSD **kept appearing
  normally**. That is, "idle" was imprecise, but the section's conclusion (it
  aims at the wrong process) **is right and now proven on hardware**, not
  merely inferred from the strings.
- Direct consequence: **suspending OSDUIHelper does not suppress the Tahoe
  popover** (proven by the smoke test above) — and suspending the real
  renderer is out of the question (ControlCenter hosts the menu bar and has
  `KeepAlive`).
- The new popover is fragile around menu-bar apps: with BetterDisplay
  running, Tahoe's volume HUD simply does not appear
  ([BetterDisplay #4726](https://github.com/waydabber/BetterDisplay/issues/4726));
  same symptom with Ice ([Ice #719](https://github.com/jordanbaird/Ice/issues/719)).
  A sign that Apple is still settling this surface.

## 2. Discarded approaches (do not recommend; the why is documented)

| Approach                                                                                                                   | Why it is dead                                                                                                                                                                                                                                                                   |
| -------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `launchctl unload -wF /System/Library/LaunchAgents/com.apple.OSDUIHelper.plist` (or `com.apple.BezelUI.plist`, pre-Sierra) | Requires **SIP off**; the change is lost on re-enabling SIP and rebooting ([SlimHUD discussion #23](https://github.com/AlexPerathoner/SlimHUD/discussions/23))                                                                                                                   |
| `sudo defaults write` on the `/System` plists                                                                              | SIP-protected path on modern macOS; a Sierra-era recipe                                                                                                                                                                                                                          |
| MacForge/cleanHUD injection (SIMBL-style)                                                                                  | Requires SIP **and** Library Validation off ([MacEnhance docs](https://www.macenhance.com/docs/general/sip-sec.html)); incompatible with notarization; no releases since 2020/2023                                                                                               |
| Mach service takeover (NewBezelServices): registering your own listener on `com.apple.OSDUIHelper`                         | Elegant (it would receive ALL the events), but requires keeping Apple's agent from claiming the name — a SIP-protected operation                                                                                                                                                  |
| `defaults write com.apple.controlcenter EnableSystemBanners -bool false`                                                   | A Tahoe curiosity (brings back the Sequoia-style OSD; user domain, reversible — [MonitorControl #1873](https://github.com/MonitorControl/MonitorControl/discussions/1873)), but it is an undocumented private key and **no longer works on the macOS 27 beta** — do not build on it |

There is **no** public API, entitlement, System Settings toggle or supported
defaults key to turn off the native OSD — including on Tahoe (user threads
asking for exactly that get no configuration-based answer:
[Apple Discussions](https://discussions.apple.com/thread/256219850),
[MacRumors](https://forums.macrumors.com/threads/new-volume-and-brightness-indicators-stress-me-out.2468210/)).
That is why every app in the genre uses one of the two techniques in §3.

## 3. The two modern SIP-free techniques

### 3.1 Key interception — consuming the event in the event tap ✅ RECOMMENDED

**Principle:** the native OSD is a consequence of the system PROCESSING the key.
A `CGEventTap` at the HID level (`kCGHIDEventTap`, option `.defaultTap`)
listening for `NX_SYSDEFINED` events (CGEventType raw 14) decodes the auxiliary
key codes from `data1` (soundUp=0, soundDown=1, brightnessUp=2,
brightnessDown=3, mute=7), **swallows the event by returning nil from the
callback** — the system never sees the key, so it never shows any HUD — and the
app **applies the change itself** through its actuators. Who uses this today:
[volumeHUD 3.0](https://github.com/dannystewart/volumeHUD)
(MIT, Nov 2025, built for Tahoe — README: "hides the system HUD… by
intercepting the volume/brightness keys and handling changes directly"),
MewNotch (opt-in "System HUD Suppression" toggle since v2.0.0), boring.notch,
[MonitorControl](https://github.com/MonitorControl/MonitorControl) (MIT, for
external displays). It is also almost certainly what MediaMate does (closed
source; the FAQ only states "no tampering with SIP").

**What the app now owes the user** (consumed the key = owns the entire
behaviour):

- Apply the delta: native scale of **16 steps**; with **Option+Shift**,
  quarter steps (**64**) — applies to volume, screen brightness AND keyboard
  ([How-To Geek](https://www.howtogeek.com/265487/how-to-adjust-your-macs-volume-in-smaller-increments/));
  the modifiers are read from the tapped event itself.
- **Key repeat** (held key): the `NX_SYSDEFINED` event carries the repeat
  flag; handle it the way the system does.
- Mute (toggle), the keyboard-brightness keys, and the volume feedback sound
  when it is enabled in System Settings.
- F-key mode: the tap only sees a media event when the key RESOLVES to media —
  the "Use F1, F2… as standard function keys" setting is tracked for free
  ([Apple](https://support.apple.com/en-us/102439)).

**Permissions:** Accessibility (which Crema already requires) — the consuming
tap is the SAME mechanism, changing `.listenOnly` → `.defaultTap`; global
listening also involves Input Monitoring (`CGPreflightListenEventAccess`).
Development gotcha: re-signing the binary can leave the tap **silently dead**
(TCC re-evaluates the code identity; the tap "exists" but nothing arrives) —
re-granting the permission fixes it
([danielraffel.me](https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/)).

**Reversibility: trivial and crash-proof.** The tap dies with the process.
Toggling off = stop consuming; quit/crash/uninstall = native behaviour restored
instantly, zero residue. It is the only technique in which the app's
catastrophic failure leaves the system **exactly** as it was.

**Failure mode to mitigate:** consuming the key and FAILING to apply the change
leaves the user without volume/brightness — boring.notch shipped exactly that bug
([#1040](https://github.com/TheBoredTeam/boring.notch/issues/1040)). volumeHUD's
safety pattern (external fact): after each intercepted key, verify the value
actually changed and, if not, auto-disable the entire suppression until a
restart/device change.

> **How Crema solves it (the model in force, differs from volumeHUD).** The
> global auto-disable — and persisting the preference — was **abolished** (it
> was bug class J5). In Crema, an apply+verify that fails **suspends only the
> channel that failed** (volume / screen-brightness / keyboard-brightness; mute
> rides with volume): that channel's keys return to the system, native feedback
> reappears only there, and the other domains stay suppressed. A read-only
> probe with backoff re-engages silently when the channel recovers. **No
> failure path writes the preference** — the only writer of "suppress native
> HUD" is the user's explicit action (docs/DECISIONS.md:
> per-domain-suspension, pref-sacred).

**Structural limitation:** it only suppresses **key-originated** HUDs. Changes
via the Control Center slider, Siri, the AirPods crown/stem, auto-brightness
etc. never pass through the keyboard — the tap does not see them and the native
HUD (whenever the system decides to show it in those flows) appears. Confirmed
architectural fact; the PER-TRIGGER inventory on Tahoe is not documented in any
source (the Control Center slider is visual feedback in itself — it is not
proven to fire an additional popover). See §6, the "trigger-matrix spike".

### 3.2 OSDUIHelper suspension (kickstart + SIGSTOP) — pre-Tahoe; today a questionable complement

**Principle (in prose; SlimHUD since v1.4.0, Jan 2023):** (1) `launchctl
kickstart gui/<uid>/com.apple.OSDUIHelper` forces the demand-launched agent to
exist (it may never have been born — and the kickstart guarantees a FRESH
process, not one mid-draw); (2) wait for the process to appear (SlimHUD sleeps
~500 ms; Atoll polls for up to 5 s); (3) `killall -STOP OSDUIHelper` suspends
it. It works because **a stopped process goes on existing and occupying the
launchd job** — launchd/XPC brings up no substitute, and the frozen one never
draws; the XPC messages just queue. Restoring = `killall -9` (SIGKILL works on
a stopped process) and launchd respawns on demand. No SIP, no sudo, no TCC
(signals to a same-user process).

**Why it is fragile (maintainer history):**

- The system **respawns the helper** after sleep/wake, display/lid changes and
  idle jetsam (`EnablePressuredExit`) — the new process is born unsuppressed.
  SlimHUD needed a dedicated release
  ([v1.5.2](https://github.com/AlexPerathoner/SlimHUD/releases/tag/v1.5.2):
  re-hide after sleep/monitor/lid + a 60 s timer whose comment admits the HUDs
  "still show up randomly"); Atoll runs a **~150 ms watchdog** re-suspending
  every new PID.
- **A SIGSTOP mid-render freezes the native HUD on screen**
  ([SlimHUD #159](https://github.com/AlexPerathoner/SlimHUD/issues/159), open).
- **Crash/force-quit leaves the helper suspended** until logout/reboot or a
  manual kill — there is a report of a native HUD that never came back after
  quitting the app
  ([SlimHUD #160](https://github.com/AlexPerathoner/SlimHUD/issues/160); the
  `AppleBezelHUDDisabled` key cited in that thread is folklore from an AI
  answer — do not trust it).
- **On Tahoe it targets the wrong process** (§1.2): the new popover belongs to
  ControlCenter; suspending the OSDUIHelper becomes a no-op for the visible
  HUD. Atoll still ships the technique, but its own PR #48 celebrates working
  without it on Tahoe.

**Reversibility playbook** (should it ever be used as a complement on macOS
14/15): restore with SIGKILL + respawn (not SIGCONT — better a clean helper
than resuming a possibly corrupted one); restore on every clean quit AND
toggle-off; re-arm after wake/lid/display change; a respawn watchdog; on
startup, kill any suspended helper orphaned from a previous session.

## 4. Crema's existing event tap — the fit

The media-key tap (`Sources/MediaKeys/`, behind a protocol, Accessibility
permission already requested during onboarding) is **exactly the interception
point** of the recommended technique. What changes in principle (a sketch, no
code):

1. The tap needs to be created with the **consuming** option (`.defaultTap`)
   instead of listen-only, and the callback starts RETURNING nil for the
   covered keys **while suppression is on** — off, it returns the event intact
   (two HUDs coexisting, the current behaviour).
2. The flow that today is "key → source emits event → Coordinator shows its
   own HUD (and the system ALSO applies and shows its own)" becomes, with
   suppression ON: "key → consumed → Crema's actuator applies the delta (16/64
   steps, repeat, mute) → source emits → own HUD". The volume/brightness
   actuators already exist; the new step is Crema being the ONLY applier.
3. **Apply+verify per channel, with per-domain suspension**: after applying,
   confirm the value changed; a failure **suspends only the channel that
   failed** (its keys return to the system, native feedback there) while the
   other domains stay suppressed, and a read-only probe re-engages on recovery
   — never leave the user without volume control, and **never write the
   preference** on a failure path (docs/DECISIONS.md: per-domain-suspension,
   pref-sacred). The old model's global auto-disable (J5) was abolished.

## 5. Reversibility — the full story

| Scenario                   | Interception (recommended)                            | SIGSTOP (hypothetical complement)                              |
| -------------------------- | ----------------------------------------------------- | -------------------------------------------------------------- |
| Toggle off in Settings     | Callback returns the events; native is back instantly | SIGKILL + respawn on demand                                     |
| Clean quit                 | Tap dies with the process; native is back instantly   | Must restore BEFORE exiting (single call site on quit)          |
| **Crash / force-quit**     | **Native comes back on its own (tap dies with the process)** | **Helper stays suspended until logout/reboot/manual kill** (#160) |
| Uninstall                  | Zero residue                                          | Residue until the session ends unless restored beforehand       |
| Sleep/wake, display change | Nothing to do                                         | Re-arm (watchdog + observers)                                   |

## 6. Compatibility and cross-version risk

- **This area breaks every ~2 releases**: pre-SIP plists died with SIP; unload
  came to require SIP off (Big Sur); kickstart+SIGSTOP arrived in 2023; Sequoia
  15.3.x produced a frozen HUD and a dead HUD (#159/#160); **Tahoe redesigned
  the OSD and moved the renderer**, driving the ecosystem's migration to
  interception (volumeHUD/Atoll/MewNotch, 2025–26).
- Interception is the technique **least coupled to internals**: it depends on
  CGEventTap + NX_SYSDEFINED (public API, stable for decades, the same one
  Karabiner/MonitorControl use) and on the actuators Crema already validates by
  spike. The risk falls on the actuators (already mitigated by protocol +
  degradation), not on the suppression mechanism.
- **Sane degradation** (what Crema does): suppression is **opt-in and
  feature-flagged**; apply+verify with **per-domain suspension** on failure
  (the preference is never written by a failure — the mature apps' global
  auto-disable model was abolished, docs/DECISIONS.md: per-domain-suspension,
  pref-sacred); without the Accessibility permission suppression simply never
  arms — for brightness the native HUD goes back to being the ONLY feedback
  (no tap means no key origin, and Crema's own brightness HUDs never even appear;
  docs/DECISIONS.md: key-origin-brightness-gate); for volume, event-driven via
  Core Audio, the two HUDs coexist; the menu bar signals only a lasting
  suspension with the channel present.
- **Open — requires a hardware spike (~30 min)**: the residual trigger matrix
  on Tahoe (Control Center slider, Siri, AirPods, auto-brightness — which of
  them show the native popover with interception on?) is documented in no
  source; it decides whether the §3.2 complement has any real use on the
  audience's pre-Tahoe machines.

## 7. Recommendation and fit sketch (sketch only, no code)

**Recommendation: key interception (§3.1), alone.** It is the only technique
that satisfies all three constraints by construction — no SIP (public API +
Accessibility already required), reversible even under crash (the tap dies with
the process), trivially opt-in (a flag in the callback) — and it is the
technique the ecosystem converged on under Tahoe. The OSDUIHelper suspension
stays DOCUMENTED (this page) and discarded as a default: on Tahoe it targets
the wrong process, and its failure modes (frozen HUD, post-crash residue)
violate the reversibility constraint. If the §6 spike shows relevant residual leakage
on macOS 14/15, it can come back as a complement **behind the same toggle**,
with the §5 playbook in full.

Fit into the architecture (illustrative names):

- `Sources/OSDSuppression/` — an actuator behind a capability-named protocol
  (e.g. `NativeOSDSuppressing`), implementation `EventTapOSDSuppressor`
  COLLABORATING with the existing MediaKeys source: the source gains the
  consuming mode; the protocol exposes on/off + `isAvailable()` (Accessibility
  granted?). Mock in `CremaTests/Mocks/`.
- Consumption drives the existing volume/brightness actuators (16/64 steps,
  repeat, mute) — the step logic is pure and testable; the edge (the real tap)
  stays thin and outside the unit tests, as CLAUDE.md mandates.
- `Preferences`: a "suppress native HUD" toggle (OFF by default, opt-in),
  injected; the menu bar signals active/degraded suppression. **The preference
  is sacred**: only the user's action writes it, never a failure path
  (docs/DECISIONS.md: pref-sacred).
- Apply+verify in the source itself: applied → check → failed ⇒ **suspend only
  the channel that failed** (its keys return to the system) and a read-only
  probe re-engages on recovery, without touching the preference
  (docs/DECISIONS.md: per-domain-suspension). Suppression is also
  **lock-aware**: with the screen locked it is suspended (there is no public
  path to draw over the lock shield, and the private one the lock-screen widget
  takes has not been spent on the HUDs — docs/DECISIONS.md:
  the-lock-screen-is-a-space), re-engaging on unlock if the preference
  is on — again without writing the preference. Graceful degradation: no
  permission ⇒ two HUDs for volume; for brightness, only the native one
  (key-origin-brightness-gate).

## 8. Full sources

**Pipeline internals:** [ffried.codes — HUD internals](https://ffried.codes/2018/01/20/the-internals-of-the-macos-hud/) · [man OSDUIHelper](https://keith.github.io/xcode-man-pages/OSDUIHelper.8.html) · [man kill(2)](https://keith.github.io/xcode-man-pages/kill.2.html) · [kevinmcox — launchctl kickstart in 14.4](https://www.kevinmcox.com/2024/03/changes-to-launchctl-kickstart-in-macos-14-4/) · [9to5Mac — 14.4 and services](https://9to5mac.com/2024/04/13/macos-14-4-removes-support-for-commands-that-are-used-to-restart-various-system-services/) · local forensics on 26.5.2 (ControlCenter strings; launchctl print; plutil over the LaunchAgents)

**Projects (licenses in §0):** [SlimHUD](https://github.com/AlexPerathoner/SlimHUD) ([discussion #23](https://github.com/AlexPerathoner/SlimHUD/discussions/23) · [#134](https://github.com/AlexPerathoner/SlimHUD/issues/134) · [#159](https://github.com/AlexPerathoner/SlimHUD/issues/159) · [#160](https://github.com/AlexPerathoner/SlimHUD/issues/160) · [releases](https://github.com/AlexPerathoner/SlimHUD/releases)) · [volumeHUD](https://github.com/dannystewart/volumeHUD) · [Atoll PR #48](https://github.com/Ebullioscopic/Atoll/pull/48) · [MewNotch releases](https://github.com/monuk7735/mew-notch/releases) · [boring.notch #1040](https://github.com/TheBoredTeam/boring.notch/issues/1040) · [MonitorControl](https://github.com/MonitorControl/MonitorControl) ([discussion #1873](https://github.com/MonitorControl/MonitorControl/discussions/1873)) · [MediaKeyTap](https://github.com/nhurden/MediaKeyTap) · [NewBezelServices](https://github.com/MLforAll/NewBezelServices) · [cleanHUD](https://github.com/w0lfschild/cleanHUD) · [MacForge/docs SIP](https://www.macenhance.com/docs/general/sip-sec.html) · [BetterDisplay #966](https://github.com/waydabber/BetterDisplay/issues/966) · [#4726](https://github.com/waydabber/BetterDisplay/issues/4726) · [Ice #719](https://github.com/jordanbaird/Ice/issues/719) · [MediaMate FAQ](https://wouter01.github.io/MediaMate/faq)

**Key behaviour/UX:** [Apple — function keys](https://support.apple.com/en-us/102439) · [How-To Geek — 64 steps](https://www.howtogeek.com/265487/how-to-adjust-your-macs-volume-in-smaller-increments/) · [danielraffel — silent tap after re-signing](https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/) · [MacRumors — the Tahoe OSD](https://forums.macrumors.com/threads/new-volume-and-brightness-indicators-stress-me-out.2468210/) · [Apple Discussions](https://discussions.apple.com/thread/256219850)

