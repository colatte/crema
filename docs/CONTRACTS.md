# The implicit contracts, made explicit

> Twenty-six named contracts the code obeys and cites by id — `MG*` motion and
> geometry, `G*` windows and coordinates, `S*` state and pipeline, `P*`
> preferences and strings. They exist so a comment can say "S4" and mean one
> precise thing in every file that says it.
>
> Provenance: distilled 2026-07-10 by a four-domain audit of the working tree.
> The audit's bookkeeping — which contracts were written down at the time, and
> the findings against that month-old tree — was dropped, all of it since fixed
> or carried forward as named tensions. What is below is the contract set
> itself, which is the part that outlives any working tree.
>
> Four are carried as **known-accepted tensions** rather than settled law: S4,
> P5, G2 and MG1 (the Card's width). They are debt the author took on purpose;
> a reader finding code that bends one of them is looking at a decision, not a
> bug. Where a contract has since become a rule of the house, CLAUDE.md states
> it and this file is the depth.

## Motion and geometry

**MG1 — Provenance-aware / frozen-empty motion contract.** An appearance from hidden or a disappearance to hidden is an opacity fade AT THE FINAL (last-visible) rect: surface geometry — frame size AND corner radius — must not travel across an empty↔visible boundary. Only visible↔visible transitions (compact↔expanded, nowPlaying↔HUD) morph under the directional spring; a hidden surface freezes the last-VISIBLE layout's rect, never snapping to compact behind a fading HUD nor mirror-shrinking on dismissal.

**MG2 — Every layoutKind-keyed animation is provenance-aware across ALL its layers.** The from-hidden rule must govern each layer it touches — outer frame, corner radius, content/material clip, and opacity — not just the outermost, so no inner material springs past a snapped frame (the Card's two-round fix).

**MG3 — Directional spring picks by destination.** Visible→visible morphs use open when expanding, close when collapsing; close is critically damped so a dismissal never overshoots against the static menu bar.

**MG4 — Level/glyph animations are value-scoped, never the surface.** `HUDLevelSlider`'s level spring and `SymbolReplaceEffect`'s replace are scoped to their own value/symbol and must never reach the surface morph, the window frame, or the appear/dismiss timing; both suspend under drag and under Reduce Motion.

**MG5 — Reduce Motion replaces motion with a dry landing.** Animations honour `accessibilityReduceMotion` — symbol swap, HUD level and waveform all gate on it and land dry. (Written as an app-wide rule in CLAUDE.md after this audit found the gate missing on the surface morph itself.)

**MG6 — HUD thresholds and icon mapping pinned once and shared.** `HUDPresentation` owns the icon family and the level boundaries as a pure struct, identical across all three styles and both Card variants; boundary conventions differ per icon family (volume inclusive-thirds, brightness midpoint) by design.

**MG7 — A variant is a different body, not a parallel component.** `HUDLevelSlider`'s three appearances (`.capsule`/`.segmented`/`.filled`) share one home for the drag/RTL mechanics, the level spring with its drag-suspension and Reduce-Motion gates, the kind-snap and the accessibility representation — their physics match by construction, not by luck.

## Windows, regions and coordinates

**G2 — Fixed-window invariant.** One NSPanel per display, created once at the union of every state's rule frame plus overshoot headroom, never resized nor ordered out; only SwiftUI content animates inside it. The window must contain every animatable state, or the morph clips at the window edge.

**G3 — Rendered-truth regions with decoupled hover.** The click-interactive region follows the rendered surface (zeroed while hidden); hover is judged against stable screen-space hysteresis regions decoupled from the animating frame, retargeted on every apply (rule frame ∩ last rendered, erring tight) and on every size report (the rendered truth) — every style, the same truth clicks use; exit = enter + per-edge band. Both armed only while a surface is visible on that display.

**G4 — Global coordinate space, UUID keying, pure rules.** Everything is AppKit global screen coordinates (bottom-left origin, y up, no flips); `NSScreen.frame` flows verbatim into `ScreenGeometry` and rule outputs go straight to `setFrame`. Displays are keyed by stable display UUID; every frame rule is a pure function of `ScreenGeometry`.

**G5 — Rebuild on geometry/style change of a kept display.** A kept display whose geometry (scale / safeTop / frame origin) or resolved style changes rebuilds its panel, because the slit inset and the per-state sizes are captured at creation; per-state frames — and the hover/click regions derived from them — flow fresh through `apply()`.

## State and pipeline

**S1 — One source of truth per value (echo, never optimism).** Every HUD level originates from a read-back of the actual value — volume echoes its Core Audio writes; brightness has no echo, so a slider or key write must poke the sampler to re-read before it is trusted. The UI never displays an optimistic write value.

**S2 — Brightness HUD is key-origin-gated.** A brightness HUD may be emitted only for a key-originated change (media-key router, suppressor post-apply poke, or slider poke) via `KeyOriginBrightnessGate`; an ambient-sensor move of the same value stays silent.

**S3 — Suppression reproduces native feedback for every consumed key.** When suppression consumes a media key the app is the sole applier and owes the native feel: apply, show the HUD, and refresh the revert timer for EVERY press — including presses at the scale boundaries, where the native OSD still flashes the full or empty bar.

**S4 — Physical re-verification of asserted world state.** Any logical assertion of world state (tap enabled, permission granted, adapter alive, lock state, suppressor engaged, Settings' cached style) must be re-verified against the physical, live world on a bounded schedule, never trusted forever — the zombie-tap class. The named tension: the Settings panes that seed a mirror once and re-read only when their own picker writes take a pinned-latent deal that costs a stale value there, deliberately.

**S5 — Bounded auto-disengage on a stuck actuator.** A consumed key whose apply hangs or fails must, within the apply deadline, disengage suppression for that domain and restore the native OSD, so the user is never left holding a dead volume or brightness key.

**S6 — Stream finish = unavailability; no unrepresentable ghost.** When a media source ends, the Coordinator drops the ghost snapshot and disarms click-invoke. A mid-chain failover must likewise not leave a snapshot on which controls are armed but which no live source can represent.

**S7 — Position tick writes only the live snapshot.** A pure position tick writes only `nowPlaying`, never `state`; identity and content changes (title/artist/layoutContent) drive `state` and the frame pass.

**S8 — Command optimism restored on every surfacing event.** `commandsAvailable` and `skipCommandsAvailable` are optimistic, flip false on a genuine command failure, and are restored to true on the next surfacing event, so a degraded control has a path back.

**S9 — Generation discipline across engage/disengage.** Every engage/disengage bumps the suppressor generation; every enqueued apply and every auto-disengage report checks it, so a key consumed just before a disengage cannot apply after a rapid re-engage.

## Preferences and strings

**P1 — Catalog verbatim discipline.** Every `String(localized:defaultValue:)` key exists in `Localizable.xcstrings` with `defaultValue` byte-identical to the `en` value, `extractionState` manual, a semantic (non-literal) key, and a translated `pt-BR` unit; no orphan keys. Enforced in CI by `scripts/check-catalog.py` (docs/INTERNATIONALIZATION.md).

**P2 — One name per concept, in each language.** A concept (style name, feature name) uses a single term across picker labels, footers, menu items and onboarding within each language. The three style names were later ruled product names and stay English in both (docs/INTERNATIONALIZATION.md).

**P3 — Conservative defaults.** A pref whose desired default differs from the type's zero reads `object(forKey:) as? T ?? default` to distinguish unset from zero; opt-in features default off via `bool(forKey:)`.

**P4 — rawValue degrade-to-default.** Every persisted enum (`Style`, `HUDIndicatorStyle`) decodes an unknown or removed rawValue to the shipped default instead of failing. The per-display override is the documented exception: it degrades to the user's declaration, never to the app default (docs/DECISIONS.md: global-style-default).

**P5 — Per-display UUID keys; dependent controls disabled-not-hidden; every live pref reachable from UI.** Per-display prefs are keyed by display UUID, global prefs by a bare key; a dependent Settings control stays visible-but-disabled with a footer naming its scope. A pref honoured live by the runtime must be writable from some UI surface, or explicitly annotated as deferred.

**P6 — DEBUG gating and footer/lint hygiene.** Each control owns exactly one footer; all demo code is strictly `#if DEBUG` with no release read of demo flags; every `swiftlint:disable` is scoped, justified and re-enabled.
