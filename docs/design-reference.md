# Design reference — styles and visual polish

> Research document informing the implementation of Crema's styles and visual
> polish. **Every value here is a starting point to calibrate visually on
> hardware — not absolute truth.** Research conducted on 2026-07-04 (macOS 26
> "Tahoe" current); reference target: MacBook Pro 14" M4 Pro.
>
> **Shipped style set (`Style`): notch · card · classic.** The original
> research explored four styles (notch, pill, circular, classic); the **pill**
> and the **circular** were dropped and converged into the **card** — the
> rounded floating panel that today covers displays without a notch slit.
> Sections §4.2 and §4.3 below remain as a record of those precursor
> explorations (the capsule and ring research fed the card); where they cite
> code metrics, the current one is the card (`CardMetrics`), not `PillMetrics`.

## 0. Licenses of the projects cited — read before opening any repo

Crema is written from scratch. Project rule: **never copy, transcribe or
adapt third-party code** — not from copyleft projects, not from permissive
ones. From this document we use **approaches, principles and numeric values**
(facts, not protected by copyright), described in prose. Crema ships under
GPL-3.0; writing everything from scratch is independent of the license — it
keeps the code free of any inherited lineage, copyleft or permissive.

Licenses verified on 2026-07-04 via `api.github.com/repos/OWNER/REPO/license`:

| Project                                                       | Licence (SPDX)                   | Type         | Permitted use in Crema                                                     |
| ------------------------------------------------------------- | -------------------------------- | ------------ | -------------------------------------------------------------------------- |
| [Atoll](https://github.com/Ebullioscopic/Atoll)               | **GPL-3.0**                      | ⚠️ Copyleft  | Inspiration/principles only — **never code**                               |
| [boring.notch](https://github.com/TheBoredTeam/boring.notch)  | **GPL-3.0**                      | ⚠️ Copyleft  | Inspiration/principles only — **never code**                               |
| [MewNotch](https://github.com/monuk7735/mew-notch)            | **GPL-3.0**                      | ⚠️ Copyleft  | Inspiration only — the project most similar to Crema; redoubled caution    |
| [SlimHUD](https://github.com/AlexPerathoner/SlimHUD)          | **GPL-3.0**                      | ⚠️ Copyleft  | Inspiration/principles only — **never code**                               |
| [NotchDrop](https://github.com/Lakr233/NotchDrop)             | MIT                              | Permissive   | Reading reference (copying would require attribution; policy: do not copy) |
| [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) | MIT                              | Permissive   | Reading reference; legally usable even as an SPM dependency                |
| [volumeHUD](https://github.com/dannystewart/volumeHUD)        | MIT                              | Permissive   | Reading reference (classic bezel values)                                   |
| [Notchmeister](https://github.com/chockenberry/Notchmeister)  | custom                           | —            | Reading reference (slit geometry)                                          |
| Alcove ([site](https://tryalcove.com))                        | **closed/commercial** (US$ 17)   | Proprietary  | Only the product's observable behaviour; the GitHub repo is releases only  |

Safety practice: **do not open the GPL projects' source code side by side
while implementing an equivalent feature** — use this document as the
intermediary.

---

## 1. Notch geometry (target: MBP 14" M4 Pro)

### 1.1 Dimensions

Panel: 14.2", native 3024×1964 @ 254 ppi; default "looks like" scale
**1512×982 @ 2x** ([Apple Tech Specs](https://support.apple.com/en-us/121553)).

The physical slit is ~370×64 **native px**; in **points it varies with the
scaling mode** (hence the project rule of deriving it at runtime, never
hardcoding):

| Scaling mode           | Slit height (`safeAreaInsets.top`) | Approximate width  |
| ---------------------- | ---------------------------------- | ------------------ |
| Default (1512×982)     | **32 pt**                          | ~185–200 pt        |
| More Space (1800×1169) | 38 pt                              | ~220 pt            |
| Larger Text            | 22 pt                              | ~127 pt            |

Sources: a real datapoint of `safeAreaInsets.top == 32` ([The Swift Den](https://www.answeroverflow.com/m/1145112887048810606));
Notchmeister uses 185×32 / 220×38 / 127×22 pt per mode. Fallbacks the apps
chose for screens where measuring is impossible: 185 pt (boring.notch,
Notchmeister), 180 pt (MewNotch), 160 pt (Atoll, a style choice), 150 pt
(NotchDrop, deliberately smaller).

**Central gotcha — menu bar ≠ slit:** the menu bar on a notched machine is
**37 pt** in the default mode (vs the slit's 32 pt) and varies 27/29/34/37/43 pt
with the scale ([Bjango, systematic measurement](https://bjango.com/articles/designingmenubarextras/)).
The mature apps (boring.notch, Atoll, MewNotch) expose **as a preference**
whether the panel matches the slit (`safeAreaInsets.top`) or the menu bar
(`frame.maxY − visibleFrame.maxY`). For Crema: start by matching the slit
(our `ScreenGeometry.safeTop`), consider the preference later.

### 1.2 APIs

All on `NSScreen`, macOS 12+:

- [`safeAreaInsets`](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets)
  — distances from the edges within which content is not obscured; only `top`
  is non-zero on notebooks with a slit; zero on displays with no obstruction.
- [`auxiliaryTopLeftArea` / `auxiliaryTopRightArea`](https://developer.apple.com/documentation/appkit/nsscreen/3882915-auxiliarytopleftarea)
  — the two _usable_ rects flanking the slit, **in global coordinates** (the
  same space as `frame`); `nil` when there is no slit.

Deriving the slit (a principle common to every app studied):

- Detection: `safeAreaInsets.top > 0` ⇔ there is a slit.
- Width: `frame.width − auxLeft.width − auxRight.width` (equivalently: the gap
  from `auxLeft.maxX` to `auxRight.minX`).
- Height: `safeAreaInsets.top`.
- Global rect: `x = auxLeft.maxX`, `y = frame.maxY − safeAreaInsets.top`.
  Since the auxiliary rects already come in AppKit's global space, the result
  goes straight into `NSPanel.setFrame` — exactly the coordinate convention of
  CLAUDE.md/`ScreenTranslation`.

### 1.3 How the apps anchor the window (principles, in prose)

Consolidated pattern (boring.notch/Atoll, described as a principle):

- Non-activating transparent panel, **level `.mainMenu + 3`** (above the menu
  bar), `collectionBehavior` with canJoinAllSpaces + **fullScreenAuxiliary**
  (visible over fullscreen apps) + stationary + ignoresCycle.
- Window **sized for the open state** and anchored top-center (x centered on
  the screen's midX — the slit is centered on the display; maxY flush against
  `frame.maxY`); the closed state is drawn _inside_ the larger window. This
  avoids re-framing the window on every hover — only the view animates.
  - Note — shipped: this is exactly the model adopted — a FIXED window at the
    style's maximum frame (`windowFrame`, a pure function of the frame rule),
    only the content animates; the per-state frame survives only as a
    defensive fallback, never applied by the styles (CLAUDE.md, "Never do").
- **Widen the slit by ~4 pt** when drawing (2 pt per side, or −4 of inset):
  the physical cutout has softened corners; without the allowance, cracks of
  light show through (boring.notch/Atoll add 4 pt; NotchDrop expands 4 pt per
  side).
  _(Shipped diverges: `NotchMetrics.lateralInset = 0` — flush with the cutout,
  with device-pixel snapping in `topAnchored`; the overhang dropped by
  hardware calibration ("never negative") and the cracks covered by a static
  black underlay in NotchView.)_
- Multi-display: one window per screen keyed by **display UUID** (identical to
  our convention); reconcile on `didChangeScreenParametersNotification`.
- MewNotch uses a window the size of the whole screen with content positioned
  by SwiftUI — an alternative that avoids re-frames but demands hit-testing
  control.

### 1.4 Gotchas

- **The slit is a dead zone for pixels and clicks** — the cursor passes
  beneath it ([AppleInsider](https://appleinsider.com/articles/21/10/20/macbook-pros-mouse-cursor-moves-behind-camera-notch)).
  Never place interactive UI inside the physical rect; only around/below it.
- **"Scale to fit below built-in camera"** (Get Info) rescales the screen to a
  slit-less mode at runtime — one more reason to react to the
  parameters-changed notification and never cache geometry.
- **Tahoe:** MewNotch documented a WindowServer crash when moving the notch
  window to a private space via SkyLight ([releases](https://github.com/monuk7735/mew-notch/releases))
  — **avoid CGSSpace/SkyLight**; an NSPanel with a high level +
  collectionBehavior is the safe path (what we already do). There is also the
  login bug with "Displays have separate Spaces" turned off ([BetterDisplay #4752](https://github.com/waydabber/BetterDisplay/discussions/4752)).
- Fullscreen: the menu bar goes away but the slit stays — without
  `fullScreenAuxiliary` the panel disappears over fullscreen apps.

---

## 2. Timing and animation

### 2.1 Why springs

[WWDC23 "Animate with springs"](https://developer.apple.com/videos/play/wwdc2023/10158/):
springs **preserve position and velocity when retargeted** — exactly the hover
case (mouse enters/leaves/returns mid-flight). Fixed easing "jumps" on
retarget. Since iOS 17/macOS 14, SwiftUI's default is already spring. Apple's
guidance for `bounce`: 0 = critically damped (the versatile default); ~0.15 =
subtle liveliness; ~0.3 = clearly bouncy; **> 0.4 discouraged for UI**.

### 2.2 Reference values (convergence of the sources)

Apple presets ([doc](<https://developer.apple.com/documentation/swiftui/animation/snappy(duration:extrabounce:)>)):
`.smooth` = bounce 0, `.snappy` = bounce 0.15, `.bouncy` = bounce 0.3 (all
duration 0.5 default). Useful conversions: `dampingFraction = 1 − bounce`;
`response ≈ duration`. Classic defaults: `.spring()` = 0.55/0.825;
`interactiveSpring()` = 0.15/0.86.

Observed values (facts, GPL projects described in prose):

| Source                | Open                                          | Close                               | Interactive/hover                                                      |
| --------------------- | --------------------------------------------- | ----------------------------------- | ---------------------------------------------------------------------- |
| boring.notch          | response **0.42** / damping **0.8**           | response **0.45** / damping **1.0** | interactiveSpring 0.38/0.8 (one spring shared for frame+content)       |
| Atoll                 | same as boring.notch                          | same                                | `.bouncy` sped up 1.2×; micro-interactions 0.16–0.2 / 0.5–0.72         |
| DynamicNotchKit (MIT) | notch: `.bouncy(0.4)`; pill: `.snappy(0.4)`   | `.smooth(0.4)`                      | hover `.snappy(0.4)`                                                   |

**Synthesis:** open with response/duration **0.35–0.45 s** and bounce
**0.15–0.3** (card at the floor, notch at the ceiling); close with
**0.4–0.45 s** and bounce **0** _(shipped: 0.35 — exit-latency budget;
docs/DECISIONS.md: hover-follows-the-eye)_ —
**never bounce on collapse** (overshoot against the screen edge reads as
instability). iOS uses more bounce in the Dynamic Island (recreations converge
on dampingFraction ~0.6), but the macOS consensus is restraint, because the
surface lives next to the static menu bar.

### 2.3 Hover: delay, hysteresis, collapse

Convergent pattern (boring.notch/Atoll, in prose) + UX research:

- **Delay before expanding (hover intent): default 0.3 s**, exposed as a
  0–1 s preference. Implemented as a cancellable task (our timer convention
  already covers it). [Baymard](https://baymard.com/blog/dropdown-menu-flickering-issue)
  recommends 300–500 ms for hover menus; notch apps sit at the floor (300 ms)
  because the top edge is an "infinite" Fitts target.
- **Immediate feedback even with the delay**: a subtle growth of a few points
  fires instantly (interactiveSpring ~0.38/0.8); only the full expansion waits
  for the intent — responsiveness without accidental triggering.
- **Collapse on exit: ~100 ms debounce**, also cancellable — re-entering
  within the window cancels the close (eliminates the edge "flicker").
- **Spatial hysteresis for free**: the exit boundary is the expanded surface
  (larger than the entry one) — geometric + temporal hysteresis.
  _(Shipped diverges: the exit boundary follows the rendered surface of the
  CURRENT state + a per-edge band — a boundary pinned to the expanded surface
  created an invisible ~100 pt sticky zone under the compact notch;
  docs/DECISIONS.md: hover-follows-the-eye.)_
- **Post-action suppression**: a ~0.35 s window with no hover-open after a
  programmatic close (e.g. the HUD took over the surface), otherwise it
  reopens because the mouse is still there. _(Shipped diverges: not
  implemented — the constant existed without a call site and was removed;
  re-arming is covered by the exit debounce + the committed-hover model's
  `hoverExitRelinger`.)_
- **Recheck on firing**: when the timer expires, revalidate the conditions
  (still hovering, still closed) before opening.

---

## 3. Liquid Glass (macOS 26 "Tahoe") — the native API

### 3.1 SwiftUI (the right path; **not** a home-made blur)

Core API: [`glassEffect(_:in:)`](<https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)>)
(**macOS 26.0+**; defaults to `Glass.regular` + a `Capsule` shape):

```swift
content.padding().glassEffect()                          // regular capsule
content.glassEffect(.regular, in: .rect(cornerRadius: 16))
content.glassEffect(.regular.tint(.accentColor).interactive())
```

- [`Glass`](https://developer.apple.com/documentation/swiftui/glass): `.regular`
  (adaptive — use it for almost everything), `.clear` (only over rich media;
  never mix the variants), `.identity` (turns the effect off conditionally);
  methods `.tint(_:)` (for meaning only, not decoration) and `.interactive()`.
- [`GlassEffectContainer`](https://developer.apple.com/documentation/swiftui/glasseffectcontainer):
  groups nearby shapes into a single sampling pass and enables blend/morph
  ("glass cannot sample other glass" — WWDC25 323). `glassEffectID(_:in:)` +
  `@Namespace` for morphing between states; `glassEffectUnion` to merge;
  `glassEffectTransition(.materialize)` when the effects sit far apart.
- Buttons: [`buttonStyle(.glass)` / `.glassProminent`](https://developer.apple.com/documentation/swiftui/glassbuttonstyle)
  — prefer these over hand-rolled glassEffect on clickable controls.
- **Apply `glassEffect` last** in the modifier chain.

Sessions: [Meet Liquid Glass (219)](https://developer.apple.com/videos/play/wwdc2025/219/),
[Build a SwiftUI app with the new design (323)](https://developer.apple.com/videos/play/wwdc2025/323/),
[Build an AppKit app with the new design (310)](https://developer.apple.com/videos/play/wwdc2025/310/);
guide: [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass).

### 3.2 AppKit

[`NSGlassEffectView`](https://developer.apple.com/documentation/appkit/nsglasseffectview)
(macOS 26+): set **`contentView`** (not a sibling) — the glass binds the
geometry and applies vibrancy to the content; `cornerRadius` (999 → capsule),
`tintColor`, `style` (.regular/.clear). [`NSGlassEffectContainerView`](https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview)
for merging/performance. The window needs `backgroundColor = .clear` +
`isOpaque = false` (our panel already is).

### 3.3 Applying it to Crema's card/notch

- Liquid Glass is, by Apple's own definition, the material of the **floating
  functional layer above the content** — a floating HUD is exactly that case.
- **Recommended route for Crema**: keep the panel transparent and apply
  `.glassEffect(in:)` **inside the SwiftUI view** (the WindowManager stays the
  owner of the frame). Reasons: reports of `NSGlassEffectView` wrapping an
  `NSHostingView` with blank/wrongly tinted content ([cmux #2459](https://github.com/manaflow-ai/cmux/issues/2459));
  and the SwiftUI route matches the pure skins.
- **Shipped diverges**: the shipped material is classic vibrancy
  (`NSVisualEffectView` via `VibrancyMaterial`, pinned dark — see
  DECISIONS: hud-fixed-dark-palette); the `.glassEffect` route was not adopted.
  This section remains as research for a Tahoe-native revisit.
- **Edges/highlight come for free** (lensing, reflection, light/dark adaptation)
  — the view draws **no** stroke/highlight of its own on the 26+ branch.
- **Never do**: home-made blur/material over or under the glass; glass nested
  in glass; glass on the content layer; too many simultaneous effects (a
  literal warning in the docs).
- **Mandatory smoke test**: there is a report of glass degrading to a plain blur
  when the app is not focused ([HWS forums](https://www.hackingwithswift.com/forums/swiftui/glasseffect-in-floating-window-panel/30067))
  — Crema is an LSUIElement and is almost never the active app; validate on hardware.

### 3.4 Fallback (macOS 14+ target)

All the glass APIs are **26.0+, with no back-deployment**. Pattern for the skins:

```swift
if #available(macOS 26.0, *) {
    content.glassEffect(.regular, in: .capsule)
} else {
    content.background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
}
```

The subtle stroke exists only on the legacy branch (on 26+ the system draws the
highlight). Our views already use `.ultraThinMaterial` — the work here is
wrapping that in a "surface" modifier with the availability branch. Test with
Reduce Transparency/Reduce Motion (the system adapts both branches on its own).

---

## 4. The four styles — visual reference

### 4.1 Notch (expands the slit)

- **Anchor**: the real notch slit via safe area/aux areas (§1); the drawing
  widened by ~4 pt.
- **Compact**: the slit itself (~185×32 pt on the default) — HUD content
  inline in the auxiliary areas, **never under the physical cutout**: a
  3-region pattern (icon+label on the left, a central black spacer the width
  of the slit, value/progress on the right), the same layout as the compact
  Dynamic Island.
- **Expanded**: 640×190 pt of content as the reference (+20 pt of breathing
  room for the shadow) — boring.notch's values taken as fact.
- **Asymmetric radii — the style's central principle**: top smaller than
  bottom (bottom ≈ 2× top) produces the look of the slit "dripping" out of
  the hardware. Reference: closed **6 pt top / 14 pt bottom**; open **19 / 24**.
- **Concentric corners** (Apple's rule): inner radius = outer radius −
  padding; ≤ 0 becomes a square corner. iOS 26 formalized it with `ConcentricRectangle`
  ([Livsy](https://livsycode.com/swiftui/concentricrectangle-and-corner-radius-consistency/)).
  Reference artwork: 90×90 pt (radius 13) open, 20×20 pt (radius 4) closed.
- Expanded layout (the Dynamic Island/Live Activities pattern,
  [HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)):
  leading = artwork, center = title/artist, trailing/bottom =
  controls/progress; iOS reference expanded radius: 44 pt, margins 20 pt.

### 4.2 Pill (precursor exploration — converged into the card)

> Style **discarded**; the capsule research below fed the shipped **card**
> (screens without a slit). `PillMetrics` no longer exists in the code — the
> current type is `CardMetrics` (compact 280×64), a rounded panel, not a
> pure capsule.

- **Always a capsule**: radius = height/2, continuous corners (squircle,
  `.continuous`), radius never exceeding half the smaller dimension.
- **Compact**: 36–44 pt tall (compact Dynamic Island ≈ 36–37 pt, 24 px icon,
  15 pt text — [Infinum](https://infinum.com/blog/start-designing-for-dynamic-island-and-live-activities/));
  Atoll uses 185×32 as fact. The shipped card uses `CardMetrics.compact`
  (280×64, a rounded panel with width hugging); calibrate visually.
- **Expanded**: 640×200 pt as the reference (Atoll uses the same sizes as the
  notch to reuse content — the same trick our skins already pull).
- Inspiring behaviour: the iOS 13+ volume indicator shrinks from a full pill
  to a thin line after a moment ([9to5Mac](https://9to5mac.com/2019/06/03/this-is-the-new-volume-indicator-in-ios-13/))
  — two levels of presence (interaction → minimal persistence).

### 4.3 Circular/radial (precursor exploration — discarded)

> Style **discarded** (never shipped; the card replaced it before it replaced
> the pill). Kept as a record of the ring/gauge research; nothing here maps to
> current code.

The classic audio knob/gauge convention + Atoll's values (facts):

- **Ring with a gap at the bottom**: an arc of ~**252°** (15%→85% of the
  circumference, starting at 144°) — the gap at the bottom is the style's
  signature (SwiftUI's accessory circular `Gauge` follows the same drawing).
- **Everything scales from a single diameter**: central icon = 32% of the
  diameter; numeric label below = 15%; indicator dot at the tip = 1.45× the
  stroke width.
- Adaptive icon per context (mute / `speaker.wave.1→3` by volume band with
  thresholds ~0.3/0.8; min/max sun with a 0.6 threshold) — fits our
  `HUDPresentation`, which may gain levels later.
- Layout: icon at the center ("what"), ring at the edge ("how much"), numeric
  value below; a light shadow to lift it off the background.

### 4.4 Classic (the pre-Tahoe native bezel, restyled)

The OSD Apple **retired in Tahoe** (today it is a slider in the top-right
corner, and a criticized one — [MacRumors](https://forums.macrumors.com/threads/new-volume-and-brightness-indicators-stress-me-out.2468210/);
that validates "classic" as deliberate nostalgia, along with the very market
of apps restoring it: volumeHUD, Hudlum).

Measurements of the original (reverse engineering, [ffried.codes](https://ffried.codes/2018/01/20/the-internals-of-the-macos-hud/)

- MIT recreation [volumeHUD](https://github.com/dannystewart/volumeHUD)):

* **200×200 pt square**, centered in x, **y = 140 pt from the bottom** of the
  screen (constant across displays).
* **Corner radius 16–19 pt** (the system used 18.0; the recreation uses 16).
* Translucent material (vibrancy/blur; the recreation uses `regularMaterial`),
  adapts to dark mode.
* **Icon ~80 pt** centered at ~70% opacity; vertical layout ~100 pt for the
  icon + ~80 pt for the bar; horizontal margins 20 pt.
* **16-segment bar** at the bottom (7.5×7.5 pt with 2 pt spacing in the
  recreation): filled at ~70% opacity, empty at ~20%. A faithful detail:
  segments **wider than tall**, with partial fill **by width**, not by
  opacity ([Hudlum](https://manytricks.com/blog/?p=6623)); with Option+Shift
  the system adjusted in **quarter segments** (64 steps —
  [How-To Geek](https://www.howtogeek.com/265487/how-to-adjust-your-macs-volume-in-smaller-increments/)).
* Timing of the original: visible for ~1.1 s with a ~0.11 s fade-out
  (recreation); the system used a 2000 ms fade via OSDUIHelper at priority 500.
  - Note: our current revert is 1.5 s — within the range; the short fade
    (~0.1 s) is the detail to copy.
* Suggested restyling: keep the proportions/position/segments and swap the
  material for Liquid Glass (§3) on macOS 26.

---

## 5. Summary — recommended starting values

**Everything below is a starting point, to be calibrated visually on hardware.**

| Parameter                       | Starting value                                                                                                  | Source |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------- | ----- |
| MBP 14 notch slit (default)     | ~185×32 pt — **always derive at runtime** (aux areas + safeTop); cosmetic fallback 185 pt                       | §1.1  |
| Widening of the slit drawing    | research: +4 pt (2 pt/side); **shipped: inset 0** (flush + pixel snap; the underlay covers the gaps)            | §1.3  |
| Window level (notch style)      | `.mainMenu + 3`, canJoinAllSpaces + fullScreenAuxiliary + stationary                                            | §1.3  |
| Open spring                     | research: 0.42/0.8 (notch) · `.snappy(0.4)` (card); **shipped: one family, 0.42/0.8** (`SurfaceAnimation.open`) | §2.2  |
| Close spring                    | research 0.45 / damping 1.0 — **no bounce**; shipped 0.35 (hover-follows-the-eye)                               | §2.2  |
| Hover-intent delay              | 0.3 s (preference 0–1 s), cancellable task + recheck                                                            | §2.3  |
| Hover-out debounce              | ~100 ms, cancellable                                                                                            | §2.3  |
| Post-close suppression          | research: ~0.35 s; **shipped: not implemented** (exit debounce + re-linger cover it)                            | §2.3  |
| Liquid glass                    | `.glassEffect(.regular, in:)` inside the SwiftUI view (26+); `.ultraThinMaterial` + subtle stroke on the <26 fallback | §3    |
| Notch: radii                    | closed 6/14 (top/bottom), open 19/24; concentric corners for content                                            | §4.1  |
| Notch: expanded                 | ~640×190 pt                                                                                                     | §4.1  |
| Card (shipped; screens without a slit) | rounded panel with width hugging; compact `CardMetrics` 280×64; expanded grows in height                 | §4.2  |
| ~~Pill / Circular~~ (discarded) | precursor explorations that converged into the card — recorded in §4.2/§4.3, with no counterpart in code        | §4.2/§4.3 |
| Classic                         | 200×200 pt, y=140 from the bottom, radius 16–19, 80 pt icon, 16 segments filled by width, ~0.11 s fade          | §4.4  |

## 6. Full sources

**Apple (official):** [safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets) · [auxiliaryTopLeftArea](https://developer.apple.com/documentation/appkit/nsscreen/3882915-auxiliarytopleftarea) · [glassEffect](<https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)>) · [Glass](https://developer.apple.com/documentation/swiftui/glass) · [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer) · [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views) · [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview) · [NSGlassEffectContainerView](https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview) · [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass) · [HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials) · [HIG Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities) · [WWDC23 Animate with springs](https://developer.apple.com/videos/play/wwdc2023/10158/) · [WWDC25 219 Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) · [WWDC25 323 SwiftUI new design](https://developer.apple.com/videos/play/wwdc2025/323/) · [WWDC25 310 AppKit new design](https://developer.apple.com/videos/play/wwdc2025/310/) · [Animation.snappy](<https://developer.apple.com/documentation/swiftui/animation/snappy(duration:extrabounce:)>) · [Animation.bouncy](<https://developer.apple.com/documentation/swiftui/animation/bouncy(duration:extrabounce:)>) · [MBP 14 M4 Tech Specs](https://support.apple.com/en-us/121553)

**Projects studied (licenses in §0):** [boring.notch](https://github.com/TheBoredTeam/boring.notch) (GPL) · [Atoll](https://github.com/Ebullioscopic/Atoll) (GPL) · [MewNotch](https://github.com/monuk7735/mew-notch) (GPL) · [SlimHUD](https://github.com/AlexPerathoner/SlimHUD) (GPL) · [NotchDrop](https://github.com/Lakr233/NotchDrop) (MIT) · [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) (MIT) · [volumeHUD](https://github.com/dannystewart/volumeHUD) (MIT) · [Notchmeister](https://github.com/chockenberry/Notchmeister)

**Articles/measurements:** [Bjango — menu bar by scale](https://bjango.com/articles/designingmenubarextras/) · [ffried.codes — HUD internals](https://ffried.codes/2018/01/20/the-internals-of-the-macos-hud/) · [Hudlum/Many Tricks](https://manytricks.com/blog/?p=6623) · [How-To Geek — 16 segments](https://www.howtogeek.com/265487/how-to-adjust-your-macs-volume-in-smaller-increments/) · [Infinum — Dynamic Island specs](https://infinum.com/blog/start-designing-for-dynamic-island-and-live-activities/) · [Baymard — hover delay 300–500ms](https://baymard.com/blog/dropdown-menu-flickering-issue) · [Ondřej Konečný — nested rounded corners](https://www.ondrejkonecny.com/blog/nested-rounded-corners/) · [The Swift Den — safeAreaInsets 32pt](https://www.answeroverflow.com/m/1145112887048810606) · [9to5Mac — iOS 13 volume](https://9to5mac.com/2019/06/03/this-is-the-new-volume-indicator-in-ios-13/) · [MacStories — NotchNook/MediaMate](https://www.macstories.net/reviews/notchnook-and-mediamate-two-apps-to-add-a-dynamic-island-to-the-mac/) · [sinasamaki — Dynamic Island recreation](https://www.sinasamaki.com/dynamic-island/) · [Create with Swift — springs](https://www.createwithswift.com/understanding-spring-animations-in-swiftui/) · [GetStream — spring catalog](https://github.com/GetStream/swiftui-spring-animations)

