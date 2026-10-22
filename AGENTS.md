# Crema

Minimalist macOS utility: now playing by the notch (a floating card on displays
without one) and its own volume, screen-brightness and keyboard-brightness HUDs
in place of the native ones, in a style chosen for all displays or per display.

Contract for how code is written here. A convention decided with the user
enters as one line with its why. 150 lines at most; a section with no real
content leaves, except "Open decisions". SPEC.md says what the app is, PLAN.md
what is open, docs/DECISIONS.md the design memory, docs/KNOWN-GAPS.md the debts.

## How to run

```bash
xcodebuild -project Crema.xcodeproj -scheme Crema -configuration Debug build
xcodebuild -project Crema.xcodeproj -scheme Crema test # Swift Testing
swiftlint lint --strict && swiftformat --lint .        # CI pins 0.65.0, 0.62.1
python3 scripts/check-catalog-selftest.py && python3 scripts/check-catalog.py .
```

- The verdict is the `Test run with N tests` line, never xcodebuild's exit
  (teardown can hang after it); parallel runs need their own `-derivedDataPath`.
- Debug adds a Demo menu (`DemoMenu`, `DemoSources`): fake sources, real
  pipeline. Sign dev builds with a stable certificate; TCC keys on signature.
- One branch per task from `dev`, named per CONTRIBUTING.md, landed by PR; no
  direct push to `dev` or `main`, admins included (docs/GITHUB.md); no squash.

## Golden rule

**System data goes up already translated into the Domain; state comes down
pure to the views.** Every translation of an outside format happens inside
the source, at the edge; above it only Domain types circulate. Views read the
Coordinator's state and return intent as a method call; they never call a
system API, never mutate domain and never keep a copy of domain state.

## Structure

```
Crema/
  Domain/         # the app's own Sendable value types; nothing of Apple's
  Sources/        # the system edge: PROTOCOLS at the root, subfolder per tech
  Coordinator/    # the one @Observable of presentation state; timers ONLY here
  Windows/        # one fixed-size NSPanel per surface; frames by hand
  Styles/         # skins: one View + one frame rule each; never touch the core
  App/            # composition root, menu, Settings, Preferences, policies
CremaTests/       # mirrors the app; Mocks/ implements the sources' protocols
ThirdParty/       # vendored mediaremote-adapter; outside lint, not ours
docs/             # public docs and the Pages root; DECISIONS.md cited by anchor
scripts/probes/   # hardware instruments with their controls; never in app or CI
design/           # icon/badge sources; outputs (AppIcon.icon) never by hand
```

## Never do

- Never let an Apple type, the adapter payload or BetterDisplay's JSON leak
  above its source; it couples the UI to the fragile part of the system.
- Never call MediaRemote directly (blocked from macOS 15.4); now playing goes
  adapter → JXA → feature off, and every link degrades without crashing.
- Never use a brightness API beyond the spike-validated pair, DisplayServices
  and CoreBrightness, keyboard ID enumerated; a nil symbol means unavailable.
  The rationale header in `Crema/Sources/Brightness/` keeps its content.
- Never implement DDC; external displays belong to BetterDisplay, never a
  requirement (docs/DECISIONS.md: external-brightness-is-write-only).
- Never suppress the native OSD without opt-in, reversibility and apply+verify
  per key; a failure suspends only its domain and writes no preference
  (docs/DECISIONS.md: per-domain-suspension, write-health-axis, pref-sacred).
- Never swallow a key aimed at a display the app does not actuate; the whole
  key goes back (docs/DECISIONS.md: brightness-key-follows-the-pointer).
- Never fight for position in the event tap chain; Crema names who is ahead
  and stops (docs/DECISIONS.md: media-key-chain-contention).
- Never keep OSD suppression engaged with the screen locked; nothing is drawn
  over it (docs/DECISIONS.md: the-lock-screen-was-built-and-taken-out).
- Never couple a skin to the core; it conforms to `SurfaceStyleBody` and draws.
- Never size or move a window from SwiftUI; the NSPanel is fixed and only the
  content animates (docs/DECISIONS.md: hover-follows-the-eye).
- Never trust the chrome for a write guarantee; the pure rule refuses
  (docs/DECISIONS.md: the-chrome-is-not-the-guarantee).
- Never block main on a subprocess; stdout is an async stream, EOF means gone.
- Never unit-test against a real system API; the mocks implement the protocols.
- Never copy third-party code, any licence; neighbours lend ideas, never lines.
- Never pre-set Sparkle's consent defaults, compile the updater in Debug, or
  hand-edit `docs/appcast.xml` (docs/DECISIONS.md: the-feed-signs-itself).
- Never self-sign with the runtime but library validation on (Sparkle aborts),
  nor with allow-dyld-environment-variables (Crema-SelfSigned.entitlements).

## Conventions

- Stack: Swift 6 mode, SwiftUI over borderless NSPanels, accessory app; target
  macOS 14 on the macOS 27 SDK; one dependency, Sparkle 2.9.4 exact. Shipping
  is self-signed; the release ritual: docs/RELEASE-GUIDE.md.
- Naming: one main type per file; a protocol names the capability (`Source`),
  an implementation technology + capability (`BetterDisplayOSDSource`).
- Concurrency: `@MainActor` on Coordinator, WindowManager, views and skin view
  state, not pure values; sources produce anywhere, main consumes; timers are
  Tasks on the injected `SleepClock`. A blocking call raced against a deadline
  runs on `DispatchQueue.global()` (docs/DECISIONS.md: J3-deadline-cooperativo).
- Sources: each system contact, neighbour apps too, sits behind a mockable
  protocol, `updates: AsyncStream<T>` plus `isAvailable()` probed where a
  chain picks; one that cannot run ends its stream or says so. docs/SOURCES.md.
- State: one `@Observable` of presentation state, the Coordinator; the others
  are read mirrors with guarded writes. Skins are a pure function of state,
  dark palette; motion vetoes gate in `SurfaceAnimation`; docs/STATE-FLOW.md.
- Tests: Swift Testing, mirroring the app's tree, mocks in `CremaTests/Mocks/`;
  waits are wall-clock-bounded, a negative claim needs a barrier, every clock
  is injected, `#expect` does not halt (`try #require`). Depth: docs/TESTING.md.
- Comments say the why the code cannot: contract, gotcha, discarded path; no
  banners, emoji or narration. A change reconfirms the comments of the touched
  passage in the same diff. A doc reference carries the lesson and the anchor,
  never a round name; a decision spanning sites gets a DECISIONS.md entry in
  the same round. Dated words ("for now") in shipped code are a pending review;
  a record of origin, or of a regression with its anchor, is not history.
- A claim about an Apple or neighbour API enters only read from a primary
  source named beside it; a measured constant ships with its probe, date and
  invalidating signal. Machine-reading Apple's docs: docs/SOURCES.md.
- Preferences: `UserDefaults` behind the injected `Preferences` type, keyed per
  display by UUID translated at the edge; a non-zero default reads
  `object(forKey:) as? T ?? default`, opt-ins born off. Log: `Logger.crema(_:)`.
- i18n: never a UI literal in a view; `String(localized:defaultValue:)` under
  semantic keys in `Crema/Localizable.xcstrings` (en, pt-BR). Only the catalog
  script catches drift, Xcode does not. Depth: docs/INTERNATIONALIZATION.md.

## Gotchas

- macOS 26 draws the OSD in ControlCenter, not OSDUIHelper: we intercept keys.
- Liquid Glass is granted on LINKAGE: Tahoe renders it, Sonoma not; uncompared.
- `AppCore.init` runs inside SwiftUI's scene update, so it shows no window
  inline: linked against the macOS 27 SDK the nesting aborts the launch
  (docs/DECISIONS.md: the-composition-root-draws-a-turn-later).

## Known gaps

- G1 — `AppCore.init` mostly unpinned by decision; 26 static seams are pinned.
- G2 — Three 0...1 clamps unshared; the third refuses NaN, so the gate is met.
- G3 — Waveform and title marquee carry no time veto; reopens on a power read.
- G4 — A process ending is not its children's; `release.sh` reaps the adapter.
- G5 — Backlight client resolved once, never rebuilt; needs a hardware repro.
- G6 — No dead-code gate in CI (SwiftLint analyzer rules off); a hand sweep.
- G7 — Declared-style adoption runs every launch; ends with pre-1.4 updates.
- G8 — Privacy panes open by hand-built URL: the SDK has no public opener.
- G9 — `noteAbsent`'s generation guard survives its mutation; no snapshot API.
- G10 — The browser filter runs after translation; browsers known by prefix.
- G11 — An older signed feed can be served again and freeze clients there.
- G12 — No sender identity on BetterDisplay's channel: readings can be forged.
- G13 — The vendored adapter's binaries carry no upstream commit or digest.
- G14 — Whoever can write Crema.app swaps the adapter or a library in it.
- G16 — Two hover hypotheses and two motion constants await a hardware probe.

## Open decisions

None pending on code conventions; PLAN.md holds what is open, ids never reused.
