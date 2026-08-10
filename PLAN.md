# PLAN.md

> Crema's execution plan ([SPEC.md](SPEC.md)), in the order the architecture
> asks for: pure logic tested first, UI over mocked data next, and the fragile
> edges last, one at a time. The app has shipped through v1.5.2, so Phase 0 is
> an inventory of what already stands and the detail starts at Phase 1 — the
> residues that survived the rounds that built it.

## Conventions

- Each task carries an id (e.g. T7.1), the responsible module (matching the folder structure in [CLAUDE.md](CLAUDE.md)), the tests or the verification that define it, and its acceptance.
- A phase starts only when the previous one's checkboxes are all ticked, except phases marked optional, which may be skipped.
- Detail per task covers the current phase and the next; phases beyond that carry only an objective and their dependencies until they come close.
- **Open task ids are historic and preserved.** T7.1, T10.2 and T17.6 were opened in the phases that built the app; collapsing those phases into Phase 0 did not renumber them, because renumbering would break the only thread tying a residue to the round that found it.
- Every edge enters behind a mockable protocol; i18n is a cross-cutting foundation, not a phase.
- Deviations are recorded in the task itself: what changed and why stay in its text.

## Phase 0 — What already exists (shipped through v1.5.2)

Objective: the app in the user's hands. Twenty-five phases (numbered 0–24) plus four post-release rounds, closed between the first commit and v1.5.2; the durable reasoning lives in [docs/DECISIONS.md](docs/DECISIONS.md) and the observable result in [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md).

- [x] **Foundation and domain** — project, Swift 6 language mode, CI (SwiftLint/SwiftFormat/catalog gate/serial tests), the `Sendable` Domain, the Coordinator with its states, priority and injectable `SleepClock`.
- [x] **Windows and styles** — one NSPanel per display, pure frame rules over `ScreenGeometry` (including the notch math), the three skins (notch, card, classic) over one shared non-visual skeleton.
- [x] **System sources** — volume (Core Audio), screen brightness (DisplayServices) and keyboard brightness (CoreBrightness), the media-key event tap, the screen-lock source and Low Power Mode, each behind its own protocol.
- [x] **Now playing** — mediaremote-adapter, JXA fallback, availability chain, the reactive/quiet modes, click-invoke, the browser filter and the scrubber that owns its gesture.
- [x] **OSD suppression** — opt-in, reversible, apply+verify per key, per-domain suspension with probe re-engagement, a write-health axis of its own, and lock-aware suspension that never touches the preference.
- [x] **External displays (brightness, both directions)** — `BetterDisplayOSDSource` inbound, and the drag written back over the neighbour's request/response channel, on the neighbour's scale.
- [x] **Shell and distribution** — menu bar menu, Settings in five tabs, the welcome tour, the login item as intent, self-signed release tooling, and the Sparkle cycle operating since v1.2.0 with a signed appcast.
- [x] **Per-display style** — declaration for all displays plus per-display overrides on one tab, where inheriting is the absence of the key.
- [x] **The lock-screen surface: built and removed whole** (2026-08-08) — proven on hardware, shipped for one session, removed by a decision about return rather than correctness. The app has no private window API; the investigation stays as the record (docs/LOCKSCREEN-INVESTIGATION.md, docs/DECISIONS.md: the-lock-screen-was-built-and-taken-out).
- [x] **The pruning round** — the demolition's debts paid, six bugs with them, and the cfprefsd instrument added to the probes drawer.

<!-- round: bootstrap-audit @ 2026-08-10 -->

## Phase 1 — The open residues

Objective: close, or consciously retire, what the building rounds left open. Nothing here blocks a release; each item is either a smoke test the author owes, a field measurement, or a small fix waiting on evidence.
Depends on: nothing — the items are independent of one another.

- [ ] T10.2 — Verify tolerant of a quantized channel · module: Sources
  - Prerequisite: a hardware smoke (suppression ON, Option+Shift + keyboard brightness at a level the coarse grid does not move) — it decides whether the read-back returns the quantized value or the armed float.
  - Tests (first): a no-move of up to one whole step without regression passes verify; a real regression keeps failing.
  - Acceptance: a keyboard-brightness key on a quantized channel neither suspends the domain nor lets a genuine write failure through.
- [ ] T10.9 — Spike: `coreaudiod` restart × listeners · module: Sources
  - Spike first (`sudo killall coreaudiod` with the app running): does volume observation survive? If not, a `kAudioHardwarePropertyServiceRestarted` listener re-running `observeCurrentDefaultDevice()`.
  - Acceptance: the volume HUD still appears after the daemon restarts — or the spike proves it already does, and the finding is recorded as verified-OK.
- [ ] T11.5 — Open investigation: the occasionally slow key · module: Sources
  - Recorded with no fix in [docs/KEY-LATENCY-INVESTIGATION.md](docs/KEY-LATENCY-INVESTIGATION.md), three candidate profiles mapped to code paths. **Waiting on field data from the author** — captured live with `log stream --level debug`, because the discriminating line is debug level and does not persist.
  - Acceptance: either a profile confirmed by a capture (and then a fix with its own task), or the investigation closed as unreproducible.
- [ ] T17.6 — `retrySuspendedNow`: the `else if` that should be two `if`s · module: Sources
  - Tests (first): a retry with both domains suspended re-engages both, not just the first.
  - Acceptance: the menu's retry clears every lasting suspension it names.
- [ ] T24.1 — `currentStyle()` seeds the leader's override, not the declaration · module: App
  - The residue the per-display round left open: `AppCore.currentStyle()` returns `preferences.style(for: leadingDisplay)`, so the "All displays" tiles can show Card (the leader's override) while the row below reads "Follow all displays (Notch)". Nothing breaks — writing there declares and sweeps all the same — but the seeded value is not the declaration, and the menu's Style submenu reads `declaredStyle` raw, so two surfaces of the SAME declaration can disagree. Readers: `GeneralSettingsView.init`, `WelcomeTourView.init`.
  - Tests (first): with an override on the leading display, the tiles seed from `declaredStyle`, matching the menu submenu.
  - Acceptance: both surfaces of the declaration show the same value, and `currentStyle()` either answers a question of its own or goes.

## Phase 2 (optional) — External displays: what is still missing

Objective: external-display volume and a brightness key Crema applies itself, over the neighbour's channel; Lunar behind the same protocols.
Depends on: Phase 1 not at all — but on evidence the neighbour's API does not give today (its `get` refuses every spelling of brightness, so the apply+verify cycle has no `before`; docs/DECISIONS.md: external-brightness-is-write-only). Tasks are detailed in the round that opens this phase.

- [ ] T7.1 — Integration detection and selection · module: Sources
  - Tests (first): with detection mocked (none / BetterDisplay only / Lunar only / both), the selection offers only what exists and allows one active integration at a time.
  - Acceptance: with both installed the user chooses in Settings; with one installed it is the one offered, which is why there is no preference today; never a requirement for the app to work.
- [ ] T7.4 — `LunarOSDSource` and the way back · module: Sources
  - Tests (first): fixtures of the socket's events (`lunar listen`) → the correct `SystemHUD`.
  - Acceptance: equivalent to the BetterDisplay pair, behind the same protocols. The socket's event format is an open decision below.

## Phase 3 (optional) — Notarized distribution

Objective: the downloaded `.dmg` opens with no "unidentified developer" warning.
Depends on: an Apple Developer account existing. The script path is already written and exercised; nothing in the code changes.

- [ ] T8.5 — Signing and notarization · module: docs
  - Verification: no unit test — a smoke on the release machine (`spctl --assess` accepts the app; a fresh download opens without the Gatekeeper prompt).
  - Acceptance: SPEC's criterion for notarized distribution passes, and docs/RELEASE-GUIDE.md's Developer ID path is the one release.sh takes by default.

## Phase 4 (deferred) — A Tahoe-native icon

Objective: an Icon Composer `.icon` alongside the classic appiconset, additive and without breaking macOS 14 (which falls back to the appiconset automatically).
Depends on: the author exporting the art in separate layers (background / pill / wave). Without them, Tahoe already applies its system treatment to the classic icon on its own, which is why this is deferred rather than open.

- [ ] T12.2 — Tahoe icon (Icon Composer, Liquid Glass) · module: design
  - Verification: visual, on Tahoe and on Sonoma, from one build.
  - Acceptance: the icon reads correctly in Finder, Get Info, Spotlight and Sparkle on both, with no regression at 16/32 pt.

## Risks and dependencies

- **Now playing blocked on macOS ≥ 15.4** (SPEC, constraint 1) → closed in Phase 0: a single path through mediaremote-adapter, a JXA fallback and an availability check. The Perl bridge is an external dependency vendored into the bundle.
- **Native HUD suppression is fragile** (SPEC, constraint 2) → closed in Phase 0 as opt-in and reversible; on failure, per-domain suspension with a read-only probe re-engaging and an informative escalation in the menu. It can break on any macOS release, and T10.2 is the one open edge of it.
- **The whole app depends on private API** (SPEC, constraint 3) → mitigated structurally: every point of contact sits behind a protocol, so an implementation can be swapped without touching the rest. The brightness APIs are chosen and embedded (DisplayServices, CoreBrightness); what remains is the standing risk of breakage on each release, which is why docs/system-contact-inventory.md exists.
- **The Accessibility permission** (SPEC, constraint 4) → closed in Phase 0: the event tap plus onboarding, and the app runs degraded without it. In development, TCC identifies the binary by its signature — sign with a stable certificate.
- **BetterDisplay/Lunar is an optional external dependency** (SPEC, "Planned", associated constraint) → Phase 2 is optional for exactly this reason, and degradation is pinned by test: with the integration absent, the essential flows are intact.
- **The neighbour's API gives no read-back for external brightness** → Phase 2's apply+verify cycle has no `before` to compare against. Plan B is to keep handing the key back to whoever moves that screen, which is what ships today.

## Open decisions

- [ ] **The format of Lunar's socket events** — the output of `lunar listen`, to be researched in the implementation (affects T7.4).
- [x] **Anonymous telemetry** — resolved: discarded; blocked by hosting rather than by principle, and the app collects nothing (docs/DECISIONS.md).
- [x] **The appcast's publishing infrastructure** — resolved: `release.sh` generates a signed `docs/appcast.xml` and Pages serves it at the `SUFeedURL`; publishing is the commit+push the script prints and never runs.
- [x] **Migrating to the observer model (SlimHUD's style)** — resolved: evaluated and discarded — freezing OSDUIHelper does not suppress the per-key OSD on macOS 26, and an orphaned SIGSTOP violates reversibility under crash.
- [x] **The concrete private brightness APIs** — resolved: DisplayServices for the screen, CoreBrightness with an enumerated ID for the keyboard; CoreDisplay and IOKit discarded as non-functional on this hardware.
