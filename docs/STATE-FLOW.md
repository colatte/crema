# State flow — from the Coordinator to the pixels

> The mechanism behind the rules CLAUDE.md states in one line each. What is
> observable, what is a mirror, what animates and what never travels: the app
> has exactly one observable of presentation state, and every other reactive
> value in it is a read mirror for views. Read this before adding an
> `@Observable`, before making a view read `nowPlaying` directly, and before
> touching an animation that crosses the empty↔visible boundary.

## One observable of state, and nine mirrors

A single `@Observable` of **presentation state**: the **Coordinator**. The app's other NINE observables are read mirrors for views, never domain — counting them as a single one was false, and `DECISIONS.md` itself already spoke of the observable of one of them. The state is the `PresentationState` enum (`hidden` / `nowPlaying` / `hud`), `Equatable`.

The nine:

- the Accessibility and the Automation permission monitors;
- the suppression and the now-playing ones;
- the per-panel `SurfaceDisplayPolicy`;
- the `LowPowerModeMirror` each panel carries along into its view's environment — guarded write, like the other mirrors: the power-state edge arrives on any power-source change, and an identical write still rebuilds every view that reads it (here, a surface drawn over the menu bar);
- the `SettingsNavigation` — a one-shot tab request that the reader consumes and clears, because a request that lingers becomes a mode and drags the window back to the tab the user just left;
- the `DisplayRoster` — the roster of connected displays that the General tab's per-display list reads, **reactive on purpose** (unlike the global declaration's mirrors, at the top of the same tab, seeded once, by decision): its rows ARE the displays, so a display plugged in with the window open would have no row until the window reopened, and a row that outlived its monitor would be control over a screen the user does not see. Fed by the SAME edge reading that builds the panels, never by a second `describeAll()`; the MENU never reads it, because every rebuild of its status block pays a `CGGetEventTapList` (docs/DECISIONS.md: one-screen-reading-per-edge);
- the evidence of the neighbour's integration (`BetterDisplayOSDSource.hasReported`) — the only observable that lives **in a source**: the Settings line that shows it is read from a body SwiftUI has already built, and whoever reads it is usually the person flipping the switch in the other app, so a claim that only flips on the next open answers "no" to the very person who just made it true. Guarded write, like the other mirrors.

## The position tick, and why it bypasses `state`

The playback position tick **samples the clock, never accumulates** — the source keeps anchor + instant + rate and every tick recomputes `position + age × rate`, so a late or missed tick corrects itself (docs/DECISIONS.md: sample-dont-integrate).

It **does not pass through `state`**: the Coordinator exposes `state` (shape/layout — what the WindowManager observes to reposition windows) and `nowPlaying` (the live snapshot, with the position advancing every second). A position-only update writes only to `nowPlaying`; views read position/scrubbing from there. This avoids firing the `state` observation (and a frame pass) once per second.

## Whatever shows title/artist outside the surface reads a mirror

`nowPlaying` is rewritten 1×/s and Observation invalidates per **property**, not per value — so any read of it (including `nowPlaying?.title`) subscribes to a rebuild per second. The Coordinator publishes `nowPlayingTitle`/`nowPlayingArtist` with guarded writes (only when the value changes, like `skipSupportedByTrack`) and clears them together with the snapshot; an expensive consumer goes in its **own View**, because tracking is per body.

In the menu bar this is the difference between a line and a system probe: the status block beside it pull-reads the tap chain (`mediaKeyChainNotice()`, which zeroes the latencies of every tap in the system on each call) and is re-evaluated whenever SwiftUI pleases, not when the user opens the menu. And the "there is media" predicate comes from the SAME value that draws the status line (`NowPlayingMenuLine.namesMedia`) — two predicates over the same fact diverge — and that same predicate also decides the EXISTENCE of the three transport items (when idle, the media block is just the line), while a command REFUSED by the player still greys the item out in place; the gate lives in the body that already reads the mirrors, never in `MenuStatus`, which is built in the body that pays the `CGGetEventTapList` (docs/DECISIONS.md: menu-reads-mirrors).

## Views report, the Coordinator decides

- Views read `coord.state` and return **intent** as methods (`hover(_:)`, play/pause, scrub, the HUD slider). A view never calls system API, never mutates domain, never keeps a copy of domain in `@State` (`@State` is for 100%-visual ephemera only).
- Priority and timers live **only** in the Coordinator: the HUD interrupts now playing and reverts ~1.5 s after the last key (the timer restarts on every keypress, like the native HUD).

## Skins are a pure function of state

Each style = one View + one frame rule. The frame rule takes pure values (a `ScreenGeometry` with frame, top safe area and the widths of the auxiliary areas) instead of `NSScreen` — that is what makes the notch computation testable.

The **non-visual skeleton** of the skins (layout/content derivation, the empty-boundary freeze, per-state sizes, the provenance and the animation gates that read it, intents) lives exactly once in `SurfaceStyleCore` (`SurfaceLayoutKind`/`SurfaceLayout`/`SurfaceProvenance`/`SurfaceStyleBody`); each style's View carries only the visual body, the provenance `@State` (the storage is SwiftUI's, the advance rule is not) and 1-line delegates that pin the Metrics parameter — a new skin = conform and draw, never re-copy the skeleton (docs/DECISIONS.md: shared-skin-skeleton).

What DOES repeat in every skin, by construction and not as residue, is the **declarations**: Swift hoists no stored property and no property wrapper through a protocol, so `coordinator`, `displayPolicy`, the environment reads and the provenance `@State` are written out again in each view. The rule they obey is not — **a shared rule restated beside every implementation is the same divergence risk as copied code, minus the compiler**, and it had already produced three drifted accounts of one freeze contract; the view says what is per-skin at the call site where it happens, and points at the shared type for the rest.

## The window is fixed; only the content animates

Each real style's NSPanel has a **fixed size** at the style's maximum frame (expanded + overshoot slack; `windowFrame`, a pure function of the rule): the window **never resizes** — only the SwiftUI content animates between states inside it. Coordinating an AppKit window + a SwiftUI render in the same transition was the origin of an entire family of intermittent flickers.

The frame rule stays pure and is the source of every derivation: per-state surface sizes and — via the panel retarget on each apply/size report — the hover regions and the **clickable region**, which derive from the SAME rendered surface in all skins (click and hover never diverge; docs/DECISIONS.md: hover-follows-the-eye). Clicks outside the visible surface pass through the window — `ignoresMouseEvents` tracks the cursor against the current state's tight frame (`SurfaceClickThrough`), so the menu bar beside the notch slit stays clickable. The WindowManager is notified **synchronously** by the Coordinator (`onPresentationChange`, in the state's `didSet`) so hover arming and click routing keep pace with the state on the same beat. At the edge, the panels' `NSHostingView` uses `sizingOptions = []` — the default (`.standardBounds`) installs constraints that would let SwiftUI resize the window.

## Two motion vetoes, neither reducible to the other

**Reduce Motion is app-wide**: with the accessibility preference on, no motion animation — geometry, morphs and layout-carrying crossfades settle dry; opacity fades are the permitted substitute. The gate lives in one place (`SurfaceAnimation`, the `reduceMotion` parameter) — no view decides this on its own.

A leaf component that holds **phase** in `@State` (the `WaveformGlyph`) has one extra obligation: following the preference's flip **live**. Whatever reads the preference inside the `body` follows it for free (the body re-runs); a phase latched at mount would keep dancing with the preference on, so the phase is derived from `animating && !reduceMotion && !lowPower` (the rule is the pure static `WaveformGlyph.dances(animating:reduceMotion:lowPower:)`) and the `onChange` is keyed on that value, not on `animating` nor on a per-input key — a per-input key is how one of the vetoes ends up observed and the other forgotten.

Reduce Motion is the user asking that nothing move; Low Power Mode is the system asking that nothing be spent on movement — and a `repeatForever` pulse over the menu bar is exactly that. The second arrives as rendering context, never domain: `ProcessInfoLowPowerModeSource` (`Sources/Power/` — a synchronous authoritative read at init, because a Mac that already boots in Low Power posts no notification at all, and every `NSProcessInfoPowerStateDidChange` edge triggers a **re-read**, never a toggle: the system posts that edge for any power-source change) feeds the `LowPowerModeMirror`, which each panel injects into its view's environment; an absent mirror (previews, Settings tiles) is absence of veto.

## Surfaces are always dark

Card and Classic pin `.environment(\.colorScheme, .dark)` **wrapping** the `vibrantSurface` (the environment reaches the AppKit material; the `VibrancyMaterial` still pins `NSAppearance` as belt-and-suspenders), as the Notch has always done with its opaque black — one appearance per surface, in every state; scoping it per branch would flip the palette mid-way through the HUD↔now-playing morph (docs/DECISIONS.md: hud-fixed-dark-palette). Consequence: the artwork accent uses a single brightness band.

## Animation contracts

Audited and pinned by test; the full audit is docs/ANIMATION-CONTRACTS.md.

1. Crossing `hidden` — appearing or vanishing — is an **opacity fade at the final rect**: geometry (frame and corner radius) never travels across the empty↔visible boundary, and the rule governs **all** layers of the surface (outer frame, radius, material clip, opacity), not just the outermost.
2. Visible↔visible morphs use a **directional spring chosen by the destination** — open when expanding, close (critically damped, no overshoot against the menu bar) when collapsing.
3. Value animations (slider level, symbol swap) are **scoped to the value itself** — they never reach the surface morph, the window frame or the appear/vanish timing — and suspend under drag and under Reduce Motion.

## Style dispatch and coordinate space

- Runtime style dispatch is the **`Style` enum** (a closed set: notch/card/classic — the card replaced the circular and then the pill). A persisted rawValue of a removed style — "pill", "circular" — degrades to the default (notch, which on a display with no notch slit resolves to the card) **in the global declaration**, but in a per-display override it falls to the user's DECLARATION and never to the default, because the override is not a choice the user made (docs/DECISIONS.md: global-style-default); the rawValue is the persistence format in Preferences. No type erasure: `PresentationStyle` remains the contract each style implements, and the enum only dispatches.
- **Coordinate space**: everything in AppKit global coordinates (origin at the bottom-left corner of the primary display, y pointing up). `NSScreen.frame` enters `ScreenGeometry.frame` verbatim; the frame rules return rects in that same global space, applied straight to `NSPanel.setFrame` with no conversion and no flip (documented in `ScreenTranslation`).
