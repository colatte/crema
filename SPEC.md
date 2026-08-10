# SPEC.md

> Describes the **Crema that exists** — what it does and why. Anything planned
> but not implemented lives in the final section, "Planned / not implemented
> (future roadmap)": nothing outside that section should be read as future, and
> nothing inside it as already shipping.
>
> Companion documents: [PLAN.md](PLAN.md) is the order of execution,
> [CLAUDE.md](CLAUDE.md) is how the code is written, and
> [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md) is the observable definition of
> "correct" — the acceptance criteria live there and only there.

## Problem

macOS's native HUDs (volume, screen brightness, keyboard brightness) offer no choice of style or position, and the system has no dedicated now-playing surface in the notch region. The utilities that attack that space (MediaMate, for one) bundle far more than that — calendar, widgets, file drop.

Crema is a minimalist macOS utility that does exactly two things:

1. Shows **now playing** near the notch — hover to expand, play/pause, scrubbing — and, on displays without a notch, in a floating card.
2. Replaces the **native HUDs** for volume, screen brightness and keyboard brightness with versions of its own, in a selectable style (the General tab declares the style for all displays and, in the per-display list right below, gives any display its own; on a display with no slit, notch resolves to card).

## Users

- macOS users (Apple Silicon and Intel, with or without a notch) who want quieter system HUDs and media control always at hand.
- Owners of notched MacBooks who want to use the slit region as an information surface.
- Power users with external monitors already running BetterDisplay: Crema's HUD covers **brightness** on the displays it manages, in both directions. External-display **volume** stays roadmap (audio over DDC, which Core Audio cannot see), as does Lunar.

## Features

### Essential

Everything below works on its own, with no third-party dependency.

**Now playing**

- Now playing near the notch; on displays without one, a floating card.
- Hover expands the surface.
- Play/pause and scrubbing straight from the surface. The scrubber's drag owns the gesture (the bar follows the finger; one seek on release; a bare click seeks to the point) and the post-seek position has a grace window against the player's late echoes, with honest exits — confirmation, track change, failure (back to the pre-seek line) or timeout (docs/DECISIONS.md: scrub-grace).
- Multi-display: now playing appears on the internal display by default; the "show now playing here" preference is per display, controlled on the **General** tab (one row per connected display, in the "Displays" section) and honoured live — the toggle re-applies through the frame pass, with no panel rebuild.
- A "show controls" toggle (view-only): with it off, the expanded surface hides the transport row and **shrinks**, so no dead space is left behind.
- **Reactive now playing (ON by default)** — a toggle in Settings. In the default (reactive mode), media events surface it on their own for ~3 s, on two triggers: (1) a track change that arrives **playing** — one that lands paused is ignored on purpose, since a paused app coming back is not news; (2) play/pause originating **outside** the surface (a physical media key, or the player itself). The appearance is **compact** (track/artist, no scrubber), reflects the event's real state, and collapses after ~3 s; hover during the appearance holds it (cancelling the timer) and leaving hover resumes the collapse. Switched off (quiet mode) nothing appears by itself: every appearance is timed in both modes (reactive ~3 s, invoked ~5 s), and in quiet mode only click-invoke opens the surface — hover expands and holds what is already on screen, never summons it.
- A "include browser media" toggle (**OFF by default**): browser media (Safari, Chrome, … by bundle-ID prefix) is treated as nothing playing — the snapshot is discarded, never merely hidden, so hover and click are not armed over a ghost player — because site autoplay takes over the system's now playing for seconds at a time, and appearing for each one is the opposite of discreet. A Safari Web App passes (a site pinned as an app is intent, like any other player). Switched on, a browser enters as an ordinary player (`MediaSourceFilter`).
- **Click-invoke**: with media playing and nothing visible, a click on the physical slit opens the player **already expanded** — the pointer is already over the surface, and a compact state would only flash on the way to the hover expansion — with a linger of its own (~5 s), longer than the reactive one because it was asked for; hover ending there keeps the full tail, without the reactive mode's short re-arm. Leaving with the pointer collapses to compact and the linger takes over. Only the notch has an invocation zone (the slit is dead pixels; the floating styles' region covers live content, and the click passes through); paused media does not invoke — only a media event brings it back.

**System HUDs**

- The app's own HUDs for volume, screen brightness and keyboard brightness, replacing the native ones.
- Native HUD suppression: **opt-in and reversible** (by media-key interception, with apply+verify per key; suspending OSDUIHelper was discarded — on macOS 26 the OSD is rendered by ControlCenter, measured; the rationale lives in `MediaKeyInterceptionOSDSuppressor`'s header). A failure — or a hang past the 2 s deadline, on a write **or a read** — **suspends only the affected domain**: its keys go back to the system (the native OSD gives the feedback, the local bar stands down — one keypress, one indicator; the user is never left without control) while the others stay suppressed, with automatic re-engagement by probe when the channel recovers. A lasting suspension shows up in the menu bar with a retry action, and **the persisted preference is never altered by a failure**. Off by default.
- Suppression is **lock-aware**: with the screen locked (or the session off the console), suppression is suspended **without touching the preference** — the keys go back to the system and the native OSD gives the feedback. There is no public path to draw over the lock shield, proven on hardware (docs/LOCKSCREEN-INVESTIGATION.md); the private path was proven too, used for one session by an opt-in card and removed whole with it — the app has no private window API (docs/DECISIONS.md: the-lock-screen-was-built-and-taken-out). On unlock it re-engages if, and only if, the preference is on.
- The level indicator the app draws is aligned with the native OSD: a thin capsule whose fill has a **curved** cap (a deliberate departure from the native square cut — the author's taste, iOS Music's language; minimum width at the track's thickness, 0% draws empty — docs/DECISIONS.md: hud-capsule-track) and no thumb at rest; an oval knob appears only under the cursor (the cursor over the HUD pauses the revert and leaving re-arms it, so the hover genuinely holds the HUD and the affordance exists exactly when there is a cursor) — in the notch and in the card. Classic renders the pre-Tahoe bezel's 16-segment bar (reverse-engineered; the measurements live inline in `ClassicStyle`/`HUDLevelSlider`). In the card the appearance is selectable: **Line** (default, the capsule) or **Filled** (the whole card fills to the level). Level, icon and knob animate with the value and settle dry under Reduce Motion.
- Media-key capture via event tap (requires the Accessibility permission).
- The brightness key acts on the display **under the pointer**. The app reads and writes the built-in panel and no other, so only that one is swallowed; any other target hands the whole key back (down, autorepeats and up) and the local bar stands down (docs/DECISIONS.md: brightness-key-follows-the-pointer).
- A HUD that **names** a display appears only on it; volume and keyboard brightness, which no screen owns, appear on all of them (docs/DECISIONS.md: hud-target-is-a-role, hud-belongs-to-its-display).

**External-display brightness, via BetterDisplay (optional)**

An optional enhancement: without BetterDisplay nothing arrives, the source sits inert, and the rest of the app operates unchanged — which is why it has no on/off preference at all.

- **Inbound**: with BetterDisplay installed and its _OSD notification integration_ on (4.2.1+), Crema draws the brightness HUD from its notification. The user turns off BetterDisplay's own OSD in that same panel, or two bars appear.
- **Return**: dragging that bar writes for real, over BetterDisplay's own request/response channel (`…request` → `…response`, matched by uuid, under a deadline) — never through the system actuator, which is on a different scale (measured: the neighbour's 0.625 against the hardware's 0.504 on the same screen).
- The bar and the write speak the **same scale**: the `SystemHUD` carries the authority that produced it and the drag goes back to that authority. The level is published **before** the write (otherwise the bar freezes under the finger), writes **coalesce** latest-wins with one in flight, and the echo carries what was actually written — not what was asked (docs/DECISIONS.md: betterdisplay-osd-source). An echo from a coalesced call is **never evidence**; only a confirmed write on the wire anchors the rollback.
- **Failure degrades, it does not die**: a refused command falls back to the system actuator within the same drag — writing the **newest** frame the failure carries with it, never the driving call's stale argument — stops being asked until the neighbour reports again (evidence, never a timer), and is never retried mid-gesture. When **neither** actuator writes — the external-display case, which DisplayServices refuses by design — the bar returns to the last level with evidence behind it, at the end of the gesture (docs/DECISIONS.md: the-bar-never-outruns-the-screen).
- The menu confirms the integration **by evidence**: only a delivered payload proves it is on, and the claim dies when the neighbouring app terminates.
- **Not implemented here**: Crema **applying a key** on an external display (it needs the apply+verify cycle; today the key is handed back to the neighbour) and external-display **volume**. See "Planned / not implemented".

**Styles**

- The display style is selectable on both scales, on the SAME tab. The "All displays" section of **General** declares the style for **every display** (and the declaration sweeps the per-display overrides — saying so in its footer when any exist, pointing at the list right below), and the "Displays" section immediately under it gives any connected display its own, through a popup of names whose first item is "Follow all displays (…)" — inheriting IS the absence of the key, so that item removes the override and never copies the declaration. The list is offered only when there is a per-display answer the declaration does not give (more than one screen, or a sole non-built-in one, or a sole one already carrying an override). A style that display does not draw appears checked-and-disabled, and the refusal of the write lives in the pure type, never in the chrome (docs/DECISIONS.md: rendered-style-gates-settings, selected-and-disabled-is-a-state, the-chrome-is-not-the-guarantee). Three options:
  - **notch** — expands the slit;
  - **card** — a floating rounded rectangle;
  - **classic** — the native bezel, redrawn.
- One window per screen; each style defines the View and the window's position/size rule.
- The card and classic surfaces are fixed in a dark appearance in every state, as the notch always was — the HUD and now playing do not follow the system's light/dark mode (docs/DECISIONS.md: hud-fixed-dark-palette).
- Configuration through a **menu bar icon** (a monochrome template image — the pill with the crema wave, generated by `design/icon/makemenubaricon.swift`; the system tints it by theme and accent) with a quick menu that opens on the switch for replacing the system indicators, continues into the status and warnings block — each fix one click away —, then, only with the media chain alive, the Now Playing section (play/pause, previous/next), and closes on the actions: open Settings ⌘,, check for updates (Release only) and quit. There is no "pause app". Plus a standard macOS **Settings window** with five tabs — General (the all-displays style declaration and, in the "Displays" section below it, one row per connected display: its own style through the popup that includes "Follow all displays (…)", and "show now playing here"), Now Playing, Indicators, Permissions and About (version and build read from the bundle, signature, GitHub/issues/Ko-fi links, and credit to Sparkle and mediaremote-adapter). **Launch at login is off by default** — the app never registers itself; the user enables it in Settings (adding a login item on first run would be intrusive). If macOS later revokes the registration (a bundle identity change — rebuild, reinstall, migration to Developer ID), the app **warns in the menu bar and offers to re-enable it in one click**; it never re-registers on its own, and a removal the user performed in System Settings is respected in silence (docs/DECISIONS.md: login-item-intent).

**Behaviour**

- Accessory app (LSUIElement), no Dock icon.
- The app icon (the crema pill with the wave over dark coffee — the author's final art) in the classic asset catalog (16→512 @1x/@2x, macOS 14+), with optical correction at the 16/32 pt sizes; its stages are Finder, installation, Get Info, About, Spotlight and Sparkle. Master and reproducible pipeline in `design/icon/`.
- The Coordinator decides what appears on screen — states `hidden` / `nowPlaying` / `hud` — with priority between them and show/hide timers.
- Default timers: the HUD disappears ~1.5 s after the last key (the timer restarts on every press, like the native one); now playing is never resident — a reactive appearance collapses in ~3 s, a click-invoked one in ~5 s; hover holds the timer and leaving re-arms it. In **reactive mode** (the default), media events — track change and external play/pause — also trigger a temporary compact appearance (~3 s, held by hover), reusing the same state machine and timers the HUD already uses.

### Out of scope

- Calendar, widgets, file drop / AirDrop.
- Mirror/webcam, teleprompter, clipboard.
- A DDC implementation of our own — external brightness and volume control is delegated to BetterDisplay/Lunar. For brightness both directions already exist over that channel; what is missing is volume (see "Planned / not implemented").

## Modules

Architecture: one core, several views.

- **Sources** — system integration (the fragile part): now playing, volume, screen brightness, keyboard brightness, media keys, native HUD suppression and screen lock state. Every point of contact with the system sits behind a protocol, so it can be swapped without affecting the rest. The BetterDisplay integration is just one more source, behind the same protocol (`Sources/External/`); Lunar stays roadmap.
- **Domain** — the app's own types (`NowPlaying`, `SystemHUD`); nothing of Apple's leaks into the layers above.
- **Coordinator** — decides what appears on screen (`hidden` / `nowPlaying` / `hud`), with priority between states and timers.
- **WindowManager** — one window per screen; resolves the style per display and scopes the HUD to the display it names (`effectiveState`).
- **Styles** — the skins (notch, card, classic); each one a View plus a window position/size rule.
- **App** — composition root and chrome: the menu bar menu (status, warnings and the suppression switch), the Settings window, Accessibility onboarding, Preferences, the login item, the Sparkle updater (Release only) and the policies that tie sources to preferences (lock-aware suppression, login-item intent).

## Stack

- **Swift + SwiftUI** — UI and animations.
- **AppKit** — borderless NSPanel; accessory app (LSUIElement).
- **Target**: macOS on Apple Silicon and Intel, with and without a notch. Minimum version: **macOS 14 (Sonoma)**.
- **Auxiliary bridges**: mediaremote-adapter (a Perl bridge) for now playing on **all supported versions**, with a JXA fallback and an availability check — never MediaRemote directly (blocked without an entitlement from macOS 15.4 on; a single path avoids branching by version).
- **Distribution**: direct download, outside the Mac App Store (private API use rules it out). Signing through `scripts/release.sh`, which supports three modes (ad-hoc / self-signed / Developer ID + notarization); what ships today is **self-signed** (a stable code identity, so the Accessibility grant persists; Gatekeeper still asks for "Open Anyway"; Developer ID awaits an Apple Developer account — see "Planned / not implemented"). Auto-update through **integrated Sparkle** (SPM 2.9.4, compiled in Release only): the cycle **has operated since v1.2.0**, with the appcast published on GitHub Pages. `release.sh` regenerates the signed `docs/appcast.xml` on every release; publishing is a commit+push the script prints and never runs.
- **App name**: **Crema** (bundle ID `com.colatte.crema`).

## Technical constraints

1. **Now playing blocked on macOS ≥ 15.4** — `MRMediaRemoteGetNowPlayingInfo` is blocked without an entitlement from macOS 15.4. Solution: the **mediaremote-adapter** (a Perl bridge), with a **JXA fallback** and an **availability check** before enabling the feature.
2. **Native HUD suppression is fragile** — an unsupported mechanism, and on macOS 26 the renderer is ControlCenter — so it has to be **reversible and opt-in**.
3. **The whole app depends on private API** — expect breakage on every macOS release. Architectural mitigation: every point of contact with the system sits behind a protocol, so an implementation can be swapped without affecting the rest.
4. **The Accessibility permission** — required for the key event tap. Onboarding on first launch: a single screen explaining why the permission is needed, with a button that opens the Accessibility pane in System Settings. Without it the app runs degraded: key capture goes, and with it the brightness HUDs (which only surface for key-originated changes — docs/DECISIONS.md: key-origin-brightness-gate); the volume HUD carries on through Core Audio. The state is flagged in the menu bar menu.

## Acceptance criteria

The criteria live in **[docs/ACCEPTANCE.md](docs/ACCEPTANCE.md)** and only there — 19 numbered items, each one checkable by a person on a running Crema. Two homes for one list is how a list ends up with two versions of item 4: while this file kept a copy, the two drifted (the published one carried a pair of criteria the internal one had already retired). A new criterion is written there, in the same round as the behaviour it describes.

## Planned / not implemented (future roadmap)

> Everything below is **planned** and is **not part of the Crema that ships**.
> It stays here as roadmap. Today the app covers the built-in display plus
> system volume without any of it, and no essential flow depends on it.

### The surface and the picker: directions on record

Deferred by an explicit decision of the author, and public in the ROADMAP ("The surface itself"):

- **Cohabitation in the compact state** — a volume key with music playing puts the level BESIDE the artwork in the compact state (the Dynamic Island's grammar), instead of swapping the whole surface for the HUD. Amber zone: it touches per-state content (`StyleContent`), without touching the Coordinator.
- **Live hover-preview in the tiles** — a cursor resting on a style tile shows that style ON THE REAL SCREEN for a moment. A genuine amber zone: it needs a preview state crossing Coordinator and WindowManager (expiry, priority over HUD and now playing, multi-display) and deserves a round of its own.

### External displays: what is still missing

**Brightness** through BetterDisplay is implemented in both directions (see Features). Still not implemented:

- **External-display volume** — audio over DDC, which Core Audio cannot see, so neither the read nor the write goes through the existing volume path. It needs the same inbound/return pair brightness got, over the neighbour's channel.
- **A brightness key applied to an external display by Crema** — today it is handed back whole to whoever moves that screen. Closing this needs the apply+verify cycle over the neighbour's channel, with the deadline it already has. Recorded trap: gating that cycle on "built-in only" would make it dead code precisely in clamshell, the arrangement it exists for — and the suite would stay green. Also **blocked by measurement, not by effort**: the neighbour's `get` refuses every spelling of brightness (and the nine relative forms too), so there is no `before` for the verify step (docs/DECISIONS.md: external-brightness-is-write-only).
- **Lunar** — the equivalent over its socket (`lunar listen`).
- **Choosing the integration in Settings**, once there is more than one: the app lists the ones it detects and allows **one active at a time**, so OSD events are not duplicated. With only one installed it is the one offered — which is today's situation, and why the current integration has no preference at all.

Associated constraint: **BetterDisplay/Lunar is an optional external dependency** — it requires the third-party app installed and its integration enabled; part of BetterDisplay's features are paid (Pro); it only works on displays with native DDC (docks and dongles may not pass DDC). It can never be a requirement for the app to work.

Acceptance criteria (when implemented):

- With BetterDisplay managing a monitor's audio, a volume key with the pointer on it draws the bar on that monitor and writes it over the neighbour's channel; without BetterDisplay, system volume operates as always.
- A brightness key aimed at an external display is applied by Crema and verified, with the bar drawn only on that display; a failure hands the key back to the system like any other.
- With both BetterDisplay and Lunar installed, Settings lists the two integrations and allows only one active at a time; no OSD event is rendered twice.

### Notarized distribution (the script path exists; the shipped artifact is self-signed)

What is **not implemented** is the distribution: the app the user downloads is self-signed, and first launch requires "Open Anyway" (the README documents the step). The Developer ID + notarization path is already written in `release.sh` — hardened runtime + entitlements, `notarytool submit --wait`, `stapler staple`, including the adapter's nested Mach-O — and depends only on an Apple Developer account existing.

Acceptance criterion (when activated): the downloaded `.dmg` opens with no "unidentified developer" warning; `spctl --assess` accepts the app.

## Open decisions

- [ ] **The format of Lunar's socket events** — the output of `lunar listen`, to be researched in the implementation (affects T7.4).
- [x] **App name** — resolved: Crema, bundle ID `com.colatte.crema`.
- [x] **The appcast URL** — resolved: `https://colatte.github.io/crema/appcast.xml`, configured as `SUFeedURL` (re-addressed when the repository moved to the organization; Pages does not redirect between accounts).
- [x] **Where the high-resolution cover comes from** — resolved: the Cover Art Archive, never Apple's Search API, whose terms grant album art only beside a purchase badge (docs/DECISIONS.md: the-cover-comes-from-the-archive-not-the-store). The feature was then removed whole with the expanded state that fed it (2026-08-08), so the decision has no subject; the reasoning stands for whoever picks a source again.
- [x] **Migrating to the observer model (SlimHUD's style)** — resolved: evaluated and **discarded** — freezing OSDUIHelper does not suppress the per-key OSD on macOS 26 (measured on hardware; the renderer is ControlCenter), and an orphaned SIGSTOP violates reversibility under crash.
- [x] **The concrete private brightness APIs** — resolved: screen via DisplayServices, keyboard via CoreBrightness `KeyboardBrightnessClient` with an enumerated ID; CoreDisplay and IOKit discarded, tested and non-functional on this hardware (CLAUDE.md, "Never do").
