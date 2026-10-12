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
xcodebuild -project Crema.xcodeproj -scheme Crema test # Swift Testing; serial
swiftlint lint --strict && swiftformat --lint .        # CI pins 0.65.0, 0.62.1
python3 scripts/check-catalog-selftest.py && python3 scripts/check-catalog.py .
```

- The verdict of a test run is the `Test run with N tests` line, never
  xcodebuild's exit: the app-hosted test target can hang in teardown after
  every test has reported. Parallel runs need their own `-derivedDataPath`.
- Debug adds a Demo menu (`DemoMenu`, `DemoSources`): fake sources, real
  pipeline. Sign dev builds with a stable certificate; TCC keys on signature.
- One branch per task, cut from `dev`, named as CONTRIBUTING.md says, landed
  by pull request; a direct push to `dev` or `main` is rejected, admins
  included (docs/GITHUB.md). Merge commits, never squashes.

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
  Windows/        # one fixed-size NSPanel per display; frames by hand
  Styles/         # skins: one View + one frame rule each; never touch the core
  App/            # composition root, menu, Settings, Preferences, policies
CremaTests/       # mirrors the app; Mocks/ implements the sources' protocols
ThirdParty/       # vendored mediaremote-adapter; outside lint, not ours
docs/             # public docs and the Pages root; DECISIONS.md cited by anchor
scripts/probes/   # hardware instruments with their controls; never in app or CI
design/           # icon and badge sources; catalogs generated, never by hand
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
- Never couple a skin to the core; it conforms to `SurfaceStyleCore` and draws.
- Never size or move a window from SwiftUI; the NSPanel is fixed and only the
  content animates (docs/DECISIONS.md: hover-follows-the-eye).
- Never trust the chrome for a write guarantee; the pure rule refuses
  (docs/DECISIONS.md: the-chrome-is-not-the-guarantee).
- Never block main on a subprocess; stdout is an async stream, EOF means gone.
- Never unit-test against a real system API; the mocks implement the protocols.
- Never copy third-party code, any licence; neighbours lend ideas, never lines.
- Never pre-set Sparkle's consent defaults, compile the updater in Debug, or
  hand-edit `docs/appcast.xml` (docs/DECISIONS.md: the-feed-signs-itself).
- Never pair hardened runtime with self-signing; dyld then aborts on Sparkle.

## Conventions

- Stack: Swift 6 mode, SwiftUI over borderless NSPanels, accessory app; target
  macOS 14 on the macOS 26 SDK; one dependency, Sparkle 2.9.4 exact. Shipping
  is self-signed; the release ritual: docs/RELEASE-GUIDE.md.
- Naming: one main type per file; a protocol names the capability (`Source`),
  an implementation technology + capability (`BetterDisplayOSDSource`).
- Concurrency: `@MainActor` on Coordinator, WindowManager and `Crema/Styles/`;
  sources produce anywhere, consumption is on main. Timers are Tasks over the
  injected `SleepClock`. A blocking call raced against a deadline runs on
  `DispatchQueue.global()` (docs/DECISIONS.md: J3-deadline-cooperativo).
- Sources: every system contact, a neighbour app included, sits behind a
  mockable protocol, `updates: AsyncStream<T>` plus `isAvailable()`;
  unavailability is state (the stream ends). Depth: docs/SOURCES.md.
- State: one `@Observable` of presentation state, the Coordinator; the others
  are read mirrors with guarded writes. Skins are a pure function of state,
  always dark; motion vetoes gate in `SurfaceAnimation`; docs/STATE-FLOW.md.
- Tests: Swift Testing, mirroring the app's tree, mocks in `CremaTests/Mocks/`;
  waits are wall-clock-bounded, a negative claim needs a barrier, every clock
  is injected, `#expect` does not halt (`try #require`). Depth: docs/TESTING.md.
- Comments say the why the code cannot: contract, gotcha, discarded path; no
  banners, no emoji, no narration. Every change reconfirms or rewrites the
  comments of the touched passage in the same diff. A doc reference carries
  the lesson and cites the anchor, never a round name; a decision spanning
  sites gets a DECISIONS.md entry in the same round. Dated words ("for now")
  in shipped code are a pending review, except as a record of origin.
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

- The native OSD on macOS 26 is rendered by ControlCenter, not OSDUIHelper;
  suppression works by key interception.
- The platform's new design is granted on LINKAGE: one binary renders Liquid
  Glass on Tahoe and not on Sonoma; nobody has compared the two.

## Known gaps

- G1 — `AppCore.init` is mostly unpinned by decision; the 5 wirings that
  matter are `wire*` seams killed by mutation (`AppCoreWiringSeamTests`).
- G2 — `BrightnessConversion` and `VolumeConversion` hold eight identical
  lines on purpose; reopens with a third domain or the first divergence.
- G3 — The waveform carries no time veto; reopens with a power measurement.
- G4 — A process ending is not its children's; `release.sh` reaps the adapter.
- G5 — The keyboard-backlight client is resolved once and no edge re-creates
  it; degradation is honest; reopens with a hardware reproduction.
- G6 — No dead-code gate in CI (SwiftLint analyzer rules off); a hand sweep.

## In progress

The open residues (T10.2, T11.5) and the optional phases live in PLAN.md, one
task per id, never renumbered. Nothing there blocks a release.

## Open decisions

None pending about how code is written. The one open decision in the system,
the format of Lunar's socket events, gates T7.4 and lives in PLAN.md.
