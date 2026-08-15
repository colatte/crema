# PLAN.md

> Crema's execution plan: what is left to build, in the order the architecture
> asks for — pure logic tested first, UI over mocked data next, and the fragile
> edges last, one at a time. What already stands is not listed here; the app
> that ships is described, in the present, by [SPEC.md](SPEC.md). Phase 1 is
> the current one.

<!-- docscheck: ignore T3 — the four module names resolve in CLAUDE.md's "Folder structure" tree (Sources and App under Crema/, plus docs/ and design/), verified by hand; the checker reads the tree only from a section literally titled "Estrutura"/"Módulos", and renaming that heading would put Portuguese in the most-read line of an English document -->

## Conventions

- Each task carries an id (e.g. T7.1), the responsible module (matching the folder structure in [CLAUDE.md](CLAUDE.md)), the tests or the verification that define it, and its acceptance. The field is spelled `· módulo:` — the one Portuguese token in an English document, because it is what the grammar checker reads to verify that no task is added without naming a module. That the named module *exists* is checked by hand: the checker's own rule for it is suppressed above, for the reason stated there.
- A phase starts only when the previous one's checkboxes are all ticked, except phases marked optional, which may be skipped.
- Detail per task covers the current phase and the next; phases beyond that carry only an objective and their dependencies until they come close.
- **Task ids are never renumbered and never reused.** T7.1, T10.2 and T12.2 sit inside phases numbered 1 to 4 because the id — not the phase — is the thread tying a residue to the round that opened it; closing the numeric gaps would cut that thread and buy nothing. A retired task takes its id with it: the number is not returned to the pool.
- Every edge enters behind a mockable protocol; i18n is a cross-cutting foundation, not a phase.
- Deviations are recorded in the task itself: what changed and why stay in its text.

## Phase 1 — The open residues

Objective: close, or consciously retire, what the building rounds left open. Nothing here blocks a release, and both items wait on the same thing — the author at the machine, because neither question has an answer a unit test can give.
Depends on: nothing — the items are independent of one another.

- [ ] T10.2 — Verify tolerant of a quantized channel · módulo: Sources
  - Prerequisite: a hardware smoke (suppression ON, Option+Shift + keyboard brightness at a level the coarse grid does not move). The apply chain already reads a SECOND time when nothing moved (`OSDApplyVerification.mayBeAsynchronous`, for a write the HAL took but has not published), so what the smoke decides is narrower than it looks: whether that second read publishes the armed float, or the channel stores the quantized value and never moves for a fine step. In the second case the domain suspends today.
  - Tests (first): a no-move of up to one whole step without regression passes verify; a real regression keeps failing.
  - Acceptance: a keyboard-brightness key on a quantized channel neither suspends the domain nor lets a genuine write failure through.
- [ ] T11.5 — Open investigation: the occasionally slow key · módulo: Sources
  - Recorded with no fix in [docs/KEY-LATENCY-INVESTIGATION.md](docs/KEY-LATENCY-INVESTIGATION.md), three candidate profiles mapped to code paths. **Waiting on field data from the author** — captured live with `log stream --level debug`, because the discriminating line is debug level and does not persist.
  - Acceptance: either a profile confirmed by a capture (and then a fix with its own task), or the investigation closed as unreproducible.

## Phase 2 (optional) — External displays: what is still missing

Objective: external-display volume and a brightness key Crema applies itself, over the neighbour's channel; Lunar behind the same protocols.
Depends on: Phase 1 not at all — but on evidence the neighbour's API does not give today (its `get` refuses every spelling of brightness, so the apply+verify cycle has no `before`; docs/DECISIONS.md: external-brightness-is-write-only). Tasks are detailed in the round that opens this phase.

- [ ] T7.1 — Integration detection and selection · módulo: Sources
  - Tests (first): with detection mocked (none / BetterDisplay only / Lunar only / both), the selection offers only what exists and allows one active integration at a time.
  - Acceptance: with both installed the user chooses in Settings; with one installed it is the one offered, which is why there is no preference today; never a requirement for the app to work.
- [ ] T7.4 — `LunarOSDSource` and the way back · módulo: Sources
  - Tests (first): fixtures of the socket's events (`lunar listen`) → the correct `SystemHUD`.
  - Acceptance: equivalent to the BetterDisplay pair, behind the same protocols. The socket's event format is an open decision below.

## Phase 3 (optional) — Notarized distribution

Objective: the downloaded `.dmg` opens with no "unidentified developer" warning.
Depends on: an Apple Developer account existing. The script path is already written and exercised; nothing in the code changes.

- [ ] T8.5 — Signing and notarization · módulo: docs
  - Verification: no unit test — a smoke on the release machine (`spctl --assess` accepts the app; a fresh download opens without the Gatekeeper prompt).
  - Acceptance: SPEC's criterion for notarized distribution passes, and docs/RELEASE-GUIDE.md's Developer ID path is the one release.sh takes by default.

## Phase 4 (deferred) — A Tahoe-native icon

Objective: an Icon Composer `.icon` alongside the classic appiconset, additive and without breaking macOS 14 (which falls back to the appiconset automatically).
Depends on: the author exporting the art in separate layers (background / pill / wave). Without them, Tahoe already applies its system treatment to the classic icon on its own, which is why this is deferred rather than open.

- [ ] T12.2 — Tahoe icon (Icon Composer, Liquid Glass) · módulo: design
  - Verification: visual, on Tahoe and on Sonoma, from one build.
  - Acceptance: the icon reads correctly in Finder, Get Info, Spotlight and Sparkle on both, with no regression at 16/32 pt.

## Risks and dependencies

- **Now playing blocked on macOS ≥ 15.4** (SPEC, constraint 1) → answered in the shipped app: a single path through mediaremote-adapter, a JXA fallback and an availability check. The Perl bridge is an external dependency vendored into the bundle, and it stays a live risk for that reason.
- **Native HUD suppression is fragile** (SPEC, constraint 2) → answered as opt-in and reversible; on failure, per-domain suspension with a read-only probe re-engaging and an informative escalation in the menu. It can break on any macOS release, and T10.2 is the one open edge of it.
- **The whole app depends on private API** (SPEC, constraint 3) → mitigated structurally: every point of contact sits behind a protocol, so an implementation can be swapped without touching the rest. The brightness APIs are chosen and embedded (DisplayServices, CoreBrightness); what remains is the standing risk of breakage on each release, which is why docs/system-contact-inventory.md exists.
- **The Accessibility permission** (SPEC, constraint 4) → answered by the event tap plus onboarding, and the app runs degraded without it. In development, TCC identifies the binary by its signature — sign with a stable certificate.
- **BetterDisplay/Lunar is an optional external dependency** (SPEC, "Planned", associated constraint) → Phase 2 is optional for exactly this reason, and degradation is pinned by test: with the integration absent, the essential flows are intact.
- **The neighbour's API gives no read-back for external brightness** → Phase 2's apply+verify cycle has no `before` to compare against. Plan B is to keep handing the key back to whoever moves that screen, which is what ships today.

## Open decisions

- [ ] **The format of Lunar's socket events** — the output of `lunar listen`, to be researched in the implementation (affects T7.4).

<!-- rodada: docs-audit @ 30a11e5 -->
