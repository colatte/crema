# Crema

> Minimalist macOS utility that shows now playing near the notch (or in a floating card on displays without one) and replaces the native volume, screen-brightness and keyboard-brightness HUDs with versions of its own, with a selectable style (declared for all displays in the "All displays" section of the General tab — the declaration sweeps the overrides — and overridable per display in the "Displays" section just below it, which is only offered when there is a per-display answer the declaration does not give).

Use this document whenever you generate or change code in this repository — it says **how we write code here**: architecture, conventions, naming, concurrency and how the layers talk to each other. When a convention decision is made during implementation, record it here — this document evolves along with the code. What the app is and why lives in @SPEC.md; the order of execution and what is still open, in @PLAN.md.

## Stack

| Layer                 | Technology                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Language              | Swift, in Swift 6 language mode (`SWIFT_VERSION = 6.0` — strict concurrency checked by the compiler)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| UI and animations     | SwiftUI. **Deployment target 14.0, but the build links against the macOS 26 SDK** — and the platform's new design is granted on LINKAGE, not on target (_"absence of the key, or `NO`, is the default value for apps linking against the latest SDKs"_, `UIDesignRequiresCompatibility`, which is ignored once the app is built against the macOS 27 SDK). So on macOS 26 the app already renders standard components with Liquid Glass without anyone having chosen it, while the same build on Sonoma does not — the two differ and nobody has compared them side by side. The Glass APIs (`GlassEffectContainer`, `Glass`, `NSGlassEffectView`) are macOS 26.0 and out of reach at the floor; the HIG reserves the material for the functional layer (_"Don't use Liquid Glass in the content layer"_) with one documented exception this app sits inside — transient interactive controls such as sliders and toggles                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Windows and lifecycle | AppKit — borderless NSPanel; accessory app (LSUIElement)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Now playing           | mediaremote-adapter (Perl bridge) on all supported versions; JXA fallback; availability check — never direct MediaRemote                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| External displays     | **Brightness works in both directions, on any display BetterDisplay manages.** Inbound: `BetterDisplayOSDSource` consumes the OSD notification (`pro.betterdisplay.BetterDisplay.osd`) and draws the brightness HUD. Return: `BetterDisplayCommandChannel` + `BetterDisplayScreenBrightnessController` send the slider drag back over the request/response channel (`…​.request` → `…​.response`, matched by uuid, under a deadline), so the write lands on the same scale as the bar. A display's HUD appears **only on that display** (docs/DECISIONS.md: hud-belongs-to-its-display). External-display **volume** (audio over DDC, which Core Audio cannot see) and Lunar (the `lunar listen` socket) remain on the roadmap                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| Distribution          | Direct download, outside the Mac App Store; **signed with a self-signed certificate** (stable code identity across versions, so the Accessibility grant persists; does not satisfy Gatekeeper — "Open Anyway" on first launch; **never with hardened runtime** — library validation demands a real Team ID and a self-signed cert has none, so the app would crash loading Sparkle; `release.sh` guards this with a consistency check + launch smoke). **Sparkle integrated** (SPM 2.9.4, exact; compiled only in Release via `#if !DEBUG`) — update cycle **operational since v1.2.0** (appcast published on Pages). The partial Info.plist carries, beyond `SUFeedURL`/`SUPublicEDKey`, the two hardenings of the update channel — `SUVerifyUpdateBeforeExtraction` (without it the DMG is MOUNTED before the EdDSA signature is checked) and `SURequireSignedFeed` (the appcast becomes signed, so a served feed cannot lie about which version is newest); the two go together because Sparkle refuses to start the updater with the second on and the first off. `generate_appcast` signs the feed on its own when it sees the key in the packaged app — no new release step — and the consequence is that `docs/appcast.xml` now authenticates itself: hand-editing it is not sloppiness, it is a 20-day update outage for every client that already carries the key (docs/DECISIONS.md: the-feed-signs-itself). `scripts/release.sh` also implements the Developer ID + notarization path, awaiting an Apple Developer account — see ROADMAP.md; the whole ritual (and the single backup of the private EdDSA key, whose loss kills the update channel for the entire installed base) lives in docs/RELEASE-GUIDE.md |
| Lock screen           | **Nothing. The app draws nothing over the lock shield.** A now-playing card lived there for one session and was removed whole — surface, SkyLight space, panel, preference, probes (docs/DECISIONS.md: the-lock-screen-was-built-and-taken-out). What survives is the KNOWLEDGE, and it is worth keeping because it was expensive and is not re-derivable from the code: no window LEVEL reaches the shield, but the shield is a SPACE at absolute level 300 and a private SkyLight space at 400 composites over it — proven on hardware, along with clicks reaching, a screen-sized window behaving, and the login's geometry. Read docs/LOCKSCREEN-INVESTIGATION.md before proposing it again. The app has **no private window API**                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Target                | macOS 14+ (Sonoma), Apple Silicon and Intel, with and without a notch                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |

> **Built vs. roadmap:** of the external-display integration, what exists is **both directions, for brightness** — `BetterDisplayOSDSource` draws the HUD from the BetterDisplay notification (docs/DECISIONS.md: betterdisplay-osd-source) and `BetterDisplayCommandChannel` sends the drag back over the request/response channel, with the round-trip measured on hardware. Still **roadmap**: external-display volume (audio over DDC, which Core Audio cannot see) and Lunar (see [ROADMAP.md](ROADMAP.md)). Without BetterDisplay, what the app controls is the built-in display + system volume. **Exercised in the field:** dragging the bar drawn on the external monitor _itself_ has already run on hardware — and it exacted a price: fast dragging exposed the coalescing writer's as-built echo of its stale argument (the bar retreated under the finger before catching up), fixed to echo the WRITTEN value and pinned by test on both halves (docs/DECISIONS.md: betterdisplay-osd-source). **Sparkle is integrated** and the update cycle **has been operating since v1.2.0** (appcast published on Pages); the Developer ID + notarization path sits ready in `release.sh`, awaiting an Apple Developer account. Shipping remains self-signed ("Open Anyway" on first launch). On **actuating** an external display, the line is thin and it pays to know which side of it you are on: the **bar drag writes** for real, over the neighbour's channel (`BetterDisplayScreenBrightnessController`, shipped); a **key** aimed at an external is **handed back** whole, and Crema itself applying it there — the apply+verify cycle — is what remains roadmap.

## Folder structure

The app's folder structure, mirrored by the tests in `CremaTests/`.

```
crema/                       # repository root
├── README.md                # public overview, installation, usage, license
├── ROADMAP.md               # future directions (public)
├── CONTRIBUTING.md          # how to contribute
├── LICENSE                  # GPL-3.0
├── CLAUDE.md                # this file — code conventions
├── SPEC.md                  # what the app is and why; everything planned-but-unbuilt isolated in the final section
├── PLAN.md                  # order of execution: an inventory of what stands, and the residues still open
├── release-notes/           # one <version>.html (or .md) per release — release.sh feeds it to the Sparkle panel and gh to the Release body; versioned, because that text ships to every user anyway
├── docs/                    # public documentation; also the GitHub Pages root (published from main)
│   ├── index.html                   # the Pages site homepage (static landing page — self-hosted except the Google Fonts it pulls; it plays assets/video/ and reads its images from assets/web/, never the full-size PNGs — those are the READMEs')
│   ├── README.md                    # documentation map (browsed on GitHub; index.html superseded it as the Pages homepage) — repository links absolute, never relative
│   ├── DECISIONS.md                 # design memory: named decisions and bug-class jurisprudence (anchors cited in code comments)
│   ├── ACCEPTANCE.md                # the acceptance criteria — 21 numbered, two retired with the lock screen — the observable definition of "the app is correct", and their ONLY home (the SPEC points here rather than restating them)
│   ├── SOURCES.md                   # the system edge: the mechanism behind each rule this file states in one line, and the measurement that produced it
│   ├── STATE-FLOW.md                # the nine mirrors, the skin skeleton, the window that never resizes and the motion vetoes
│   ├── TESTING.md                   # the test discipline, each clause with the failure that produced it
│   ├── INTERNATIONALIZATION.md      # the catalog gate, the reserved vocabulary and the two ceilings a string obeys
│   ├── CONTRACTS.md                 # the 26 named contracts the code cites by id (MG*, G*, S*, P*) — a comment saying "S4" resolves here
│   ├── RELEASE-GUIDE.md             # how a release is published and how the Sparkle cycle is fed (incl. the single backup of the EdDSA key)
│   ├── LOCKSCREEN-INVESTIGATION.md  # the evidence behind the lock-aware suppression: no window LEVEL reaches the shield, but the shield is a SPACE, and the private SkyLight path over it is proven on hardware — taken for one session by the opt-in now-playing widget, then removed whole (docs/DECISIONS.md: the-lock-screen-was-built-and-taken-out). The investigation stays as the record. Read the last sections before quoting this file
│   ├── KNOWN-GAPS.md                # the deliberate debts in full: reasoning, palliative and reopening gate of each (one line each in this file's Known gaps)
│   ├── KEY-LATENCY-INVESTIGATION.md # an OPEN investigation, no fix: the occasionally slow key, three disjoint profiles and the capture that discriminates them (PLAN T11.5)
│   ├── system-contact-inventory.md  # the ~90 points where the app touches a resource that can die underneath it (review checklist; statuses DATED)
│   ├── appcast.xml                  # Sparkle feed (live since v1.2.0; regenerated by release.sh, SIGNED — never hand-edited)
│   ├── assets/                      # README media, full size and lossless: showcase screenshots, the README's 2 GIFs, icon.png (web export of the appiconset), download badge and video/ (teaser)
│   │   └── web/                     # what index.html actually serves, derived from the above by scripts/make-web-assets.sh — 9.1 MB of PNG becomes 186 KB of WebP, and the three HUD specimens are CROPPED, not merely resized (full frame they are ~90% empty wallpaper and the tile reads as a grey rectangle). Regenerate there, never hand-edit
├── design/
│   ├── badge/               # makedownloadbadge.swift — generates the README's "Download for macOS" button (docs/assets/download-macos.png); ground calibrated against both GitHub themes
│   └── icon/                # icon source art: 4096 master (unmasked), makeicon.swift (applies the macOS template squircle and generates the appiconset), makemenubaricon.swift (derives the menu bar TEMPLATE — pill + crema line), full icns
├── scripts/
│   ├── release.sh           # build + build-number stamp + signing (ad-hoc / self-signed / Developer ID + notarization, incl. Sparkle's nested code) + DMG + docs/appcast.xml regeneration
│   ├── check-catalog.py     # the String Catalog gate (six rules + two "not verified" reports: multiline defaultValue and a call shape the checker does not read); CI and release.sh run it — Xcode enforces nothing
│   ├── check-catalog-selftest.py  # proves the checker by making it FAIL on every rule; runs BEFORE it, because a checker that stops checking returns the same "clean"
│   ├── make-web-assets.sh   # derives docs/assets/web/ (what the landing page serves) from the full-size PNGs in docs/assets/; idempotent, requires cwebp
│   └── probes/              # disposable-but-kept instruments against the real system — hardware, cfprefsd (`swift scripts/probes/<x>.swift`): each header says which decision it settles, and each carries the CONTROL that makes a negative result mean something — they never enter the app or the CI
├── ThirdParty/
│   └── mediaremote-adapter/ # vendored now-playing bridge (BSD-3-Clause)
├── Crema.xcodeproj          # Xcode project
├── Crema/                   # app code
│   ├── Assets.xcassets/     # AppIcon (generated by design/icon/makeicon.swift) + MenuBarIcon (the menu bar template, generated by design/icon/makemenubaricon.swift, incl. the Contents.json with the mandatory template-rendering-intent) — regenerate there, never hand-edit
│   ├── App/                 # entry point (LSUIElement), the menu bar menu, Settings in 5 tabs (General carries the style's two scales: the all-displays declaration — with the Card's `IndicatorPicker` in mini-tiles right below the style tiles, offered only where some display renders the Card — and, in the "Displays" section just below it, one row per display with style and now playing) + the `WallpaperTileStore`/`TileBackdrop` that set the real desktop under both tile groups and the `Thumbnail` that gives them one frame — its numbers AND the ring drawn from them, because sharing only the numbers still let the eleven lines tracing them diverge, the DisplayRoster this list reads, `DisplayStyleOptions` (the pure type that decides what the list offers, what it reads and what a choice may write — the refusal lives in it, never in the popup: the `.menu` Picker discards `.disabled` on options) and `PerDisplayStyleOverride` in the same home, first-run welcome tour (pure `WelcomeTourFlow` + `WelcomeTourView`), Accessibility onboarding (today only via the menu button), Preferences, login item, Sparkle updater (Release-only), the lock-aware suppression policy, demo infra (#if DEBUG)
│   ├── Domain/              # the app's own types (NowPlaying, SystemHUD, MediaKey, PresentationState, DisplayUUID) — nothing of Apple's leaks upward
│   ├── Sources/             # the Sources layer: system integration (the fragile part); PROTOCOLS and composite sources at the root, per-technology implementations in the subdirectories
│   │   ├── NowPlaying/      # mediaremote-adapter + JXA fallback + availability chain (never MediaRemote directly). The cover upgrade that lived here — `ArtworkLookup`, `CoverArtArchiveLookup`, `RequestPacer` — is GONE with the 300 pt tile it fed; the app makes no artwork request (docs/DECISIONS.md: the-click-was-the-last-thing-holding-the-lookup-up)
│   │   ├── Volume/          # system volume (Core Audio)
│   │   ├── Brightness/      # screen brightness (DisplayServices) and keyboard brightness (CoreBrightness) — see "Never do"
│   │   ├── MediaKeys/       # media-key event tap (requires Accessibility permission)
│   │   ├── OSDSuppression/  # native OSD suppression via key interception — opt-in, reversible, apply+verify with per-domain suspension and probe self-healing
│   │   ├── ScreenLock/      # screen lock state (notification edges + authoritative re-read) — feeds the lock-aware policy
│   │   ├── Power/           # Low Power Mode (`ProcessInfo` + power-state edge → authoritative re-read) — the second animation veto, alongside Reduce Motion
│   │   ├── Desktop/         # desktop picture (`NSWorkspace`, only the URL goes up) — the real desktop under the Settings style tiles
│   │   └── External/        # BetterDisplay integration: inbound (OSDSource + OSDTranslation) and the way back (CommandChannel + CommandTranslation + ScreenBrightnessController); Lunar stays roadmap
│   ├── Coordinator/         # decides what appears on screen: hidden / nowPlaying / hud, with priority and timers (injectable SleepClock)
│   ├── Windows/             # WindowManager: one NSPanel per display; resolves the style per display; frame computed by hand
│   └── Styles/              # skins: Notch, Card, Classic — each one a View + a window position/size rule (+ shared: SurfaceStyleCore — the non-visual skeleton every skin conforms to —, SurfaceAnimation, `SurfaceChrome` (the border numbers, also read by the Settings tiles), HUDLevelSlider, HUDIndicatorStyle, `CardHUDIndicator` (the body of the Card's HUD, which the Settings mini-tile renders frozen), `StylePreviewContent` (pure rule for the miniature content), `LowPowerModeMirror` + the environment that carries it…).
└── CremaTests/              # unit tests (mirroring the app's structure)
    └── Mocks/               # source fakes — they implement the same protocols as the real sources
```

## Running locally

```bash
# open in Xcode and run with ⌘R (Crema scheme)
open Crema.xcodeproj

# or build via CLI
xcodebuild -project Crema.xcodeproj -scheme Crema -configuration Debug build

# tests (Swift Testing; CI runs the same on macos-15, SERIAL — see TDD)
xcodebuild -project Crema.xcodeproj -scheme Crema test

# lint/format like the CI (versions pinned there: SwiftLint 0.65.0 --strict, SwiftFormat 0.62.1 --lint; CI's Xcode is pinned too, 26.3)
swiftlint lint --strict
swiftformat --lint .
```

- Concurrent `xcodebuild test` runs fight over the build-system lock in the shared DerivedData (it looks like a deadlock) — for parallel runs, use an isolated `-derivedDataPath`. The test target is app-hosted and boots the real `AppCore`: the pollers hold the runloop and **the host's teardown can hang after every test has reported** — the trustworthy verdict is the `Test run with N tests` line in the log, not xcodebuild's exit.
- The app is an accessory (LSUIElement): it does not appear in the Dock — look for the icon in the menu bar.
- **In Debug, the menu bar menu has a Demo section** (`DemoMenu`/`DemoSources`, `#if DEBUG`): fake sources and actuators driving the real pipeline — you can exercise the HUD and now playing without touching a system API. None of it compiles in Release.
- **First run**: opens the **welcome tour** — five steps that CONFIGURE (Accessibility, style, replacing the system indicators, opening at login), once per installation (`hasSeenWelcomeTour`, written BEFORE the window appears, so a mid-tour crash cannot re-arm it; the gate consults no permission, so an upgrade sees it once too). No step blocks: there is always a way out (Skip, and Done on the last step) and the grant-Accessibility button sits BESIDE Continue, never in its place — the permission decides the OFFER, never the path (docs/DECISIONS.md: the-tour-configures-instead-of-pointing). The Accessibility step requests the permission and opens System Settings → Privacy & Security → Accessibility, and flips to "on" LIVE. Without the permission the app runs degraded (no key capture) and flags it in the menu bar menu; the Accessibility onboarding window still exists as the **manual** path, via the menu button. During development, sign with a stable certificate — TCC identifies the binary by its signature, and rebuilds may require granting the permission again.
- **Living with BetterDisplay**: if it is installed with **Settings → Application → Integration → OSD notification** turned on (4.2.1+), Crema draws the brightness HUD from its notification — nothing to enable on Crema's side. Turn off BetterDisplay's own OSD in that same panel, or two bars appear. Without BetterDisplay, nothing arrives and the app carries on unchanged. **Acting** on an external display is half-way on purpose: dragging the bar writes through the neighbour's channel, but a key aimed at an external is handed back to it instead of applied by Crema — see ROADMAP.md.

## Golden rule

**System data goes up already translated into the domain; state comes down pure to the views.** Everything below is that rule unfolded.

In practice: every translation of an outside format (the MediaRemote dict, the adapter payload, system notifications) happens **inside the source**, at the edge — above it, only Domain types circulate. In the reverse direction, views read state from the Coordinator and return intent as a method call; they never call system APIs and never keep a copy of domain state.

## Code standards

### Naming

- Swift API Design Guidelines — types and protocols in `UpperCamelCase`, members in `lowerCamelCase`; one main type per file, with the file named after the type (`NowPlayingSource.swift`).
- System-contact protocols name the **capability** and take the `Source` suffix: `NowPlayingSource`, `SystemHUDSource`.
- Implementations name **technology + capability**: `MediaRemoteAdapterNowPlayingSource`, `JXANowPlayingSource`, `BetterDisplayOSDSource` (and `LunarOSDSource`, when it exists).
- Actuators (they perform actions instead of emitting events — e.g. OSD suppression) follow the same scheme: protocol named for the capability, implementation named for the technology.

### Comments

- Comments explain the **why**, not the what: non-obvious decisions, API gotchas, contracts between layers, the rationale behind choices (e.g. why a path was discarded). The code already says what it does; the comment says what the code cannot say on its own.
- No decoration: no ASCII art, no section banners, no lines of `===` or `***`, no ornamental emphasis, no emoji. A comment is an objective sentence, not a poster.
- Don't narrate the obvious: never comment what a line clearly already expresses. Prefer renaming/restructuring the code over explaining it in a comment.
- Density over volume: if a block needs three decorated sentences, it probably needs one direct one. Cut redundancy.
- The exception that **stays detailed**: comments carrying expensive, durable knowledge — like the private-API rationale header in `Sources/Brightness/` (frameworks used, paths discarded and why, ownership/ID gotchas) — must still be objective, but the **content stays**; trimming decoration from these never means erasing the knowledge.

### Anti-recurrence contract (comments and decisions)

Permanent. An outdated comment is a **doc bug**, not a minor detail — it lies to the next reader with the authority of sitting next to the code. The critics of future rounds **enforce this contract**.

- **Every code change reviews the comments of the touched passage in the SAME change.** There is no "I'll fix the comment later": if the logic changed, the why beside it is either reconfirmed or rewritten, in the same diff.
- **A new comment carries why and contract, never what-the-code-does.** If the sentence paraphrases the line below it, cut it and, if needed, rename the code. The comment says what the code cannot say on its own (see "### Comments").
- **A reference to an internal doc is always self-sufficient.** The lesson lives **in the comment itself**; the ID (`docs/DECISIONS.md: J7-estado-do-outro-lado`) is a pointer for depth, never the only copy of the information — a reader without access to the doc still understands the why. Corollary (2026-08-08, amended 2026-08-10 when PLAN.md was promoted into the repository): a round name lives only in PLAN.md's own round markers, where the marker beside it carries the date and sha that make it resolvable — code, DECISIONS.md and every other doc still cite dates and anchors, never round names, because outside the PLAN a round name is vocabulary with no referent.
- **A new design decision relevant to an external reader = an entry in `docs/DECISIONS.md` in the same round.** The anchor is the canonical ID; the code comment points to it.
- **When knowledge goes into `docs/DECISIONS.md` instead of staying inline**: an entry when the decision has no single site to live in — it governs more than one place in the code, it is a discarded path someone will propose again (recorded with its reopening gate), or it is bug-class jurisprudence — and whenever an external reader would need it to avoid undoing the choice. A why that fits whole in a comment beside the only affected site stays inline and gets no anchor. The entry never replaces the comment (the lesson lives in the code; the anchor is depth — anti-recurrence contract), and an amendment counts as an entry: a decision that finalizes or retires an existing rule (the menu Toggle over menu-status-before-warnings) is recorded by amending the anchor the rule already has, in the same diff that changes the code — an anchor without its amendment is how a true entry ends up describing the opposite behaviour.
- **Dated vocabulary in shipped code is a pending review.** Words like "spike", "experiment", "temporary", "for now", "new/now" in a comment on code that has already shipped age and lie — on finding one, fix it (describe the stable contract, not the moment it was born). The **provenance** exception: a "spike" that records _how_ a piece of durable knowledge was obtained — validated by a hardware spike, with the spike itself already discarded (the `Sources/Brightness/` header) — is permanent history, not temporary state; there the word is the record of origin, and the exception already protected in "### Comments" ("the content stays") applies.

### Concurrency

- `@MainActor`: Coordinator, WindowManager and every view in `Styles/`.
- The Domain is 100% `Sendable` value types (struct/enum) — it crosses threads without drama.
- Sources may produce off the main thread (a process, notifications, system callbacks); **consumption** is always on main — the Coordinator consumes the streams in `Task`s on the MainActor.
- Presentation timers (e.g. the HUD revert) are cancellable `Task`s sleeping on the **`SleepClock`** protocol (an injectable clock in `Coordinator/`; production uses `ContinuousSleepClock`, tests use a fake clock and never actually sleep) — never `Timer`/RunLoop.
- Long-running/streaming external processes (the Perl adapter is the only one; the neighbour integration uses no subprocess — it speaks over `DistributedNotificationCenter`): read stdout as an async sequence (`FileHandle.bytes` or equivalent) and treat EOF as unavailability. Never `waitUntilExit`/`readDataToEndOfFile` on the main thread.
- **Every one-shot interaction with a subprocess is time-bounded**: waiting on `terminationHandler` with no deadline is waiting forever (a hung child froze the selection of the entire chain — the A6 audit). The pattern is a pure, testable race (deadline over `SleepClock` + single-resume) + a thin edge that on expiry calls `terminate()` escalating to SIGKILL — the child is abandoned and killed, never awaited (`ChildProcessDeadline`).
- **A blocking synchronous operation raced against a deadline runs on `DispatchQueue.global()`, never on the cooperative pool** (nor `Task.detached`): the cooperative pool has fixed width and does not overcommit — blocked orphans pile up, and the deadline resumes on that same pool, so enough orphans strangle the deadline itself. The global GCD pool grows when threads block; an orphan there never steals capacity from live work (`OSDApplyDeadline`, rule in the header). _Async_ operations stay on an unstructured detached task (the write/S5 pattern). When the calls also need **ordering among themselves** — the reads of a brightness channel, which record a value — the hop goes to a **dedicated serial queue** (`blockingCall(on:)`); the explicit price is that a stuck read holds up that channel's queue, never the app's concurrency (`PolledBrightnessSource`).

### Sources (the system edge)

Depth — each rule's mechanism, and the measurement that produced it — in docs/SOURCES.md.

- Every point of contact with the system sits behind a (mockable) protocol — including the integration with another app, which is just one more source: `BetterDisplayOSDSource` conforms to `SystemHUDSource` like any other.
- **Layout of `Sources/`**: the protocols and the generic composite sources live at the **root**; each subdirectory is a technology with the concrete implementations. The interesting edge logic is extracted pure and testable — the Reconciler/Translation/Conversion pattern (`ScreenLockReconciler`, `AdapterPayloadTranslation`, `VolumeConversion`) — and the thin edge keeps only the system contact.
- An event source exposes `updates: AsyncStream<DomainType>` + `isAvailable() async -> Bool`, and translates the outside format **inside the source**, at the edge. The Coordinator receives the sources **injected through the protocols** and never names a concrete implementation.
- **Unavailability is state, not a fatal error** — the stream ends and the consumer re-evaluates availability; `throws` is for one-shot operations, never for the event flow. End of stream discards the snapshot and disarms click-invoke: never leave armed controls that no living source can represent.
- **OSD suppression is lock-aware** — locked or off the console, suppression is suspended without touching the preference, and re-engages on unlock if (and only if) the preference is on. A notification edge never flips the state by itself: each edge triggers an authoritative re-read, with settle re-reads and a periodic tail armed from construction, because a dropped lock notification would wedge the state over the shield with no edge left to correct it (docs/DECISIONS.md: settle-rereads).
- **An apply failure suspends per domain, never globally** — the failing channel's keys go back to the system (native feedback) while the other domains stay suppressed, and a read-only probe re-engages on recovery. **No failure path writes a preference.** Write health is a **separate axis** that survives the probe's re-engage, otherwise a domain whose write is dead but whose read is alive flaps through re-engages forever (docs/DECISIONS.md: per-domain-suspension, write-health-axis, pref-sacred).
- **The brightness key acts on the display under the POINTER, and the app only swallows what it itself applies** — any other target hands the whole key back (down, autorepeats and up, latched in `SuppressionDecider`) and makes the local bar stand down. No fallback to the built-in — that fallback _is_ the bug — and a single display answers for itself, pointer or no pointer (docs/DECISIONS.md: brightness-key-follows-the-pointer).
- **Real state behind an IPC boundary cannot be audited by a local health-check** — the media-key tap goes `enabled`-but-deaf while `isValid`/`isEnabled` keep lying, so it is reinstalled preventively on the **4 physical edges** (`screensDidWake`, `didWake`, unlock, `didChangeScreenParameters`), and every port mutation runs on the tap's own thread (docs/DECISIONS.md: preventive-reinstall, tap-mutation-on-its-own-thread, J7-estado-do-outro-lado).
- **A key that goes missing may be position in the chain, not a sick tap** — session taps are chained and whoever inserts last receives first. Crema **names** who is ahead and never contests the position: re-inserting in a loop is an arm-wrestle decided by whoever moved last, and `kCGHIDEventTap` always wins by stealing the key from every third party that legitimately wants it (docs/DECISIONS.md: media-key-chain-contention).
- **Neighbour-app integration is a source like any other**, with four rules that took probing to discover — exact name (a `nil` name is deaf by construction), one prefix only, the payload in the `object` rather than `userInfo`, and the scale is the neighbour's — and three scoping rules with a single why, that with the neighbour's OSD off Crema's bar is the user's only feedback: emit only a target the app can **name**, **discard instead of guessing**, and **stand the local key source down** when the neighbour reports (docs/DECISIONS.md: betterdisplay-osd-source).
- **Integration feedback is by evidence, never by presence** — only a delivered payload proves the neighbour's integration is on, and the claim dies when that app terminates. Neighbour identity is compared by **bundle ID**, never by localized name.
- **A HUD that names a display appears only on it** — and it names a **role**, not a UUID (`SystemHUD.Target`), which whoever holds the panel roster resolves. `.noDisplay` (volume, keyboard backlight) stays on every screen on purpose; `.builtIn` **fails open** when no internal panel is in the roster, because a consumed key always produces feedback (docs/DECISIONS.md: hud-target-is-a-role, hud-belongs-to-its-display).
- **The bar and the write speak the same scale, and whoever drew receives the drag** — publish the level before writing, coalesce latest-wins with one write in flight, degrade to the system actuator instead of dying, roll back at the END of a gesture no actuator honoured, and never let a queued level lose the display it belongs to (docs/DECISIONS.md: the-bar-never-outruns-the-screen).

### State flow

Depth — the nine mirrors named one by one, the skin skeleton and the animation contracts — in docs/STATE-FLOW.md.

- A single `@Observable` of **presentation state**: the **Coordinator** (`PresentationState`: `hidden` / `nowPlaying` / `hud`, `Equatable`). The app's other NINE observables are read mirrors for views, never domain, and every one of them writes guarded — an identical write still rebuilds every view that reads it.
- The playback position tick **samples the clock, never accumulates**, and **does not pass through `state`**: a position-only update writes only to `nowPlaying`, so the frame pass does not run once per second (docs/DECISIONS.md: sample-dont-integrate).
- **Whatever shows title/artist outside the surface reads a mirror, never the snapshot** — Observation invalidates per property, so a single read of `nowPlaying` subscribes to a rebuild per second. An expensive consumer goes in its **own View**, because tracking is per body (docs/DECISIONS.md: menu-reads-mirrors).
- Views read `coord.state` and return **intent** as methods. A view never calls system API, never mutates domain and never keeps a copy of domain in `@State` (`@State` is for 100%-visual ephemera only). Priority and timers live **only** in the Coordinator.
- Skins are a **pure function of state**: one View + one frame rule over pure values (`ScreenGeometry`), which is what makes the notch math an ordinary test. The non-visual skeleton lives exactly once in `SurfaceStyleCore` — a new skin conforms and draws, never re-copies it (docs/DECISIONS.md: shared-skin-skeleton).
- Each style's NSPanel has a **fixed size** and never resizes; only the SwiftUI content animates inside it. Hover regions and the clickable region derive from the SAME rendered surface, and the WindowManager is notified **synchronously** in the state's `didSet` (docs/DECISIONS.md: hover-follows-the-eye).
- **Two motion vetoes, neither reducible to the other**: Reduce Motion is the user asking that nothing move, Low Power Mode is the system asking that nothing be spent on movement. The gate lives in one place (`SurfaceAnimation`); a leaf holding phase in `@State` derives it from both and keys its `onChange` on that derived value, never on a per-input key — that is how one veto ends up observed and the other forgotten.
- **Surfaces are always dark** — one appearance per surface, in every state; scoping it per branch would flip the palette mid-morph (docs/DECISIONS.md: hud-fixed-dark-palette).
- **Animation contracts** (pinned by test): crossing `hidden` is an opacity fade at the final rect and geometry never travels across that boundary, in any layer of the surface; visible↔visible morphs use a spring chosen by the destination; value animations are scoped to the value and never reach the surface morph, the window frame or the appear/vanish timing.
- Runtime style dispatch is the **`Style` enum**, no type erasure. A removed style's persisted rawValue degrades to the default in the global declaration, but in a per-display override it falls to the user's DECLARATION — the override is not a choice the user made (docs/DECISIONS.md: global-style-default).
- **Coordinate space**: AppKit global coordinates throughout (origin bottom-left of the primary display, y up), with no conversion and no flip between `NSScreen.frame`, the frame rules and `NSPanel.setFrame` (documented in `ScreenTranslation`).

### Graceful degradation (the default, not the exception)

- Now playing chain: adapter → JXA → feature off. No crash at any link; the state is signalled in the menu-bar menu.
- Without Accessibility permission: the app runs without key capture, plus a warning in the menu.
- Without **Automation** permission (Apple Events): only the **JXA** link of the now playing chain drops — the adapter doesn't use it, so now playing carries on unchanged, and that is why the Automation row in the Permissions tab is neutral, never an alarm. The state is discovered **without ever provoking the prompt** (`AEDeterminePermissionToAutomateTarget` with `askUserIfNeeded: false`), and the absences of an answer are kept apart from refusal (target app closed ⇒ `procNotFound`, which is the RESTING state of anyone with no music app open and therefore gets its own text; consent never requested ⇒ `errAEEventWouldRequireUserConsent`) — calling an absence a refusal would accuse the user of a "no" they never gave. The read is blocking, runs **only from the tab's lifecycle edges**, and stops while the consent dialog is open; its observable is **never** read by the menu, whose body already pays for the `CGGetEventTapList` (docs/DECISIONS.md: automation-is-fallback-only).
- Without BetterDisplay installed (or with its OSD integration switched off): no notification arrives, the source sits inert and everything else operates unchanged — which is why it has no on/off preference at all.

### Capability by build configuration

- Capabilities that only make sense in one configuration compile **only in it**: the demo infrastructure is `#if DEBUG` (`DemoMenu`, `DemoSources`); the Sparkle updater is `#if !DEBUG` (`UpdaterModel` in Debug is an inert shell and the menu item doesn't even compile — keeps an updater from running in a development build; the gate is over the updater's **code** — the Sparkle.framework binary ships in every configuration, since the SPM link is not conditioned on configuration). The source of truth is a compile-time `static isSupported`, and **contract tests pin the behaviour** (`SparkleUpdaterTests`: `isSupported == false` in Debug, with no pending-update mirror; feed URL, EdDSA key and the two hardenings (`SUVerifyUpdateBeforeExtraction`, `SURequireSignedFeed`) present in the Info.plist; no consent default pre-set; the menu strings resolving in both languages from the BUILT bundle, which is where the catalog gate does not reach). In Release the updater is also the delegate of Sparkle's user driver (`supportsGentleScheduledUpdateReminders`): an accessory app receives the scheduled alert BEHIND every other app and has no Dock to bring it forward, so the menu gains the informative line + a button that leads to it, with a guarded-write mirror (docs/DECISIONS.md: the-update-alert-nobody-sees).

### Internationalization

Depth — the catalog gate's rules, the reserved vocabulary and the two ceilings — in docs/INTERNATIONALIZATION.md.

- **Never a UI string literal in a view** — visible text comes from the String Catalog (`Crema/Localizable.xcstrings`) via `String(localized:defaultValue:)`, under **semantic** keys, never the literal text as the key.
- **Base language English**, `pt-BR` an additional translation. Number/date/time always through locale-aware `FormatStyle` — never manual digit interpolation. Media title/artist is external content and is never translated.
- **Catalog verbatim discipline**: `defaultValue` byte-for-byte identical to the `en` value, `extractionState` manual, a translated `pt-BR` unit, no orphan keys, the same specifiers in both languages. **`scripts/check-catalog.py` enforces it in CI — Xcode enforces nothing** (measured: with `extractionState: manual`, `xcstringstool sync` walks past an entry whose `en` diverged from the code without a warning), and its self-test runs first, because a checker that silently stops checking returns the same "clean".
- **The type ramp is ONE**, and a second scale needs a published number rather than a preference (Apple's Accessibility HIG: macOS default 13 pt against minimum 10 pt).
- **One name per concept, in each language** — the picker, tab and section labels are the source of truth. The three STYLE names are product names and stay English in both languages; `indicator` is what Crema draws, `display` is a display, and `built-in display` is reserved for the built-in panel; an external monitor carries its `localizedName` verbatim, because it is the only name the user can match to the thing on the desk.
- **Menu strings have a ~72-character ceiling** — NSMenu sizes itself by the widest item, and a 116-character line opened the menu at ~1500 px. The break lives in the catalog, falls at a clause of the language itself, and both languages keep the same number of breaks.
- **No emoji in UI strings that communicate state** — the glyph duplicates the sentence, VoiceOver reads it mid-sentence, and `✓` collides with NSMenu's own vocabulary, where a checkmark means a checked item (docs/DECISIONS.md: menu-status-before-warnings).

### A claim about somebody else's API carries its source

The same discipline as the measured-constant rule below, pointed outward: **an
assertion about how an Apple or neighbour-app API behaves does not enter code, a
comment or a document until it has been read from a primary source** — the SDK
header (`xcrun --show-sdk-path`), the current documentation, a Swift Evolution
proposal, the vendor's release notes. An archived page quoted as current is the
same error as no source at all. The cost is not hypothetical: a window level
written 14 above the documented ceiling, a Core Audio listener the header says a
`coreaudiod` restart destroys silently, and a decode flag whose documented
default is the opposite of what the comment beside it claimed — each found only
when somebody went and looked.

**Two questions, not one, and they have different answers.** What a symbol
requires is availability; what the app _gets_ is linkage.
`MACOSX_DEPLOYMENT_TARGET` answers the first,
`xcrun --sdk macosx --show-sdk-version` the second, and an appearance claim
needs both. Measured here and still true: this project targets macOS 14 and
builds against the macOS 26 SDK, and the platform's current design is granted on
LINKAGE — _"absence of the key, or `NO`, is the default value for apps linking
against the latest SDKs"_ (`UIDesignRequiresCompatibility`, which is
ignored once the app is built against the macOS 27 SDK). So the app already renders standard components differently on
Tahoe than on Sonoma, from one binary, with nobody having chosen it — and
nobody has compared the two side by side.

**And the fetch fails silently, which is why the mechanics are written down.**
`developer.apple.com` renders client-side, so an ordinary request returns the
page title and nothing else — indistinguishable from an empty page. The DocC
JSON behind it is what carries the content: swap `/documentation/` for
`/tutorials/data/documentation/` and append `.json` (the HIG lives under
`/tutorials/data/design/` instead).

```
https://developer.apple.com/tutorials/data/documentation/swiftui/glasseffectcontainer.json
https://developer.apple.com/tutorials/data/design/human-interface-guidelines/materials.json
```

`metadata.platforms` is the authoritative availability list — name,
`introducedAt`, and a `beta` flag — which settles "is this symbol reachable at
our floor?" in one call. The prose sits in `abstract` and
`primaryContentSections` as nested `text`/`codeVoice` nodes that need
flattening.

### A constant read off the screen carries its measurement

Some numbers cannot be derived. The rule is not "never measure"; it is that **a
measured constant ships with what measured it, and with the signal that would
invalidate it** — the value, the probe that produced it, the date, and the fact
that makes it durable. The reference case was a lock-screen constant whose
surface has since been removed; the discipline outlived it, and the corollaries
below were all earned there.

Two corollaries, earned the hard way. **Separate the axis that
moves from the axis that does not**: the login's vertical position has already
changed between releases, while horizontally it has been centred in every
version — so the surface stays centred by structure and only its height is a
measurement. And **a comment asserting a layout fact without a measurement
behind it is worse than no comment**: the card sat 96 pt up for a week under a
sentence claiming that cleared the avatar, which was not merely unproven but
backwards.

A third corollary, from deleting the lock surface's backdrop: **some rects cannot
be measured at all, and the honest move is to stop trying rather than to measure
harder.** The login's resting rect is measurable; the login's _widest_ rect is
not, because one of its inputs is a string an administrator types — the MDM lock
message wraps to the width of the display, and behind it sit the recovery text
after three failures, the password hint, the Apple Watch failure and Switch
User. Five proposed designs sized a clear column against that rect, with four
different numbers, and every one of them would have clipped an instruction
telling the user who to call. A measurement has a signal that invalidates it; an
unbounded rect has none, and the shape that depends on it is unshippable
regardless of the ruler (docs/DECISIONS.md: the-lock-surface-is-a-card).

### Preferences and logging

- Preferences (style — the UI exists on **both sides**, today on the SAME tab (and the menu-bar menu is a second site for the global side: the Style submenu declares through the SAME `setStyleEverywhere`): the "All displays" section of the General tab **declares** the style for every display (global key `declaredStyle`, the fallback) and sweeps the overrides; the rows of the "Displays" section, right below it, **override** per display (per-display key, the override) and return a display to the declaration through the popup's own "Follow all displays (…)" item, which writes `clearStyle` — there is no separate reset button any more; inheriting IS the absence of the key, so the item REMOVES instead of writing the current declaration, which would shadow the next declaration forever (docs/DECISIONS.md: global-style-default) —, suppression toggles and "Show now playing here" (also on the General tab, on the display's own row), the tour gate (`hasSeenWelcomeTour`, once-per-install, written BEFORE the presentation — the only pref committed before the effect it guards, so a crash mid-tour does not re-arm it), launch at login — persisted as **intent**, never the real state: the registration lives in BTM and macOS revokes it on an identity change, so the intent exists only to detect the loss and warn, never to re-register on its own; docs/DECISIONS.md: login-item-intent) live in `UserDefaults`, behind a `Preferences` type injected wherever needed. The stable per-display key is the **display UUID** (`CGDisplayCreateUUIDFromDisplayID`) — the displayID→UUID translation happens at the edge; preferences and the Domain see only the UUID.
- **Conservative defaults**: a pref whose desired default differs from the type's zero reads `object(forKey:) as? T ?? default` to tell "not set" apart from zero; opt-in features are born off via `bool(forKey:)`.
- Logging via `os.Logger`, always built through `Logger.crema(_:)` (`Crema/App/Logging.swift` — the only place that knows the `subsystem`), with the unlabelled argument = layer or source (`Logger.crema("NowPlaying")`, `"Windows"`, `"OSD"`). No `print`; never instantiate `Logger(subsystem:category:)` directly.

### Examples

```swift
// ✅ The protocol speaks the Domain's vocabulary; translation happens INSIDE the source
protocol SystemHUDSource {
    var updates: AsyncStream<SystemHUD> { get }
    func isAvailable() async -> Bool
}

final class BetterDisplayOSDSource: SystemHUDSource {   // the real one: Sources/External/
    // BetterDisplay's JSON is decoded here, at the edge (systemIconID 1 =
    // brightness); volume and mute don't travel up, because Core Audio already emits for them
}

// ❌ An outside format leaking upward
var updates: AsyncStream<[String: Any]>   // raw MediaRemote dict reaching the UI
func handle(osdJSON: Data)                // Coordinator parsing BetterDisplay JSON
```

```swift
// ✅ A skin is a pure function of state; intent comes back as a method
struct CardView: View {
    let coord: Coordinator
    var body: some View {
        content(for: coord.state)
            .onHover { coord.hover($0) }   // the view reports; the Coordinator decides
    }
}

// ❌ A second source of truth + a view talking to the system
struct CardView: View {
    @State private var track: NowPlaying?  // local copy — drifts out of sync with the Coordinator
    var body: some View {
        artwork
            .onAppear { _ = DistributedNotificationCenter.default() } // a source disguised as a view
    }
}
```

```swift
// ✅ A frame rule is a pure function of values — the notch math becomes an ordinary test
struct ScreenGeometry {
    let frame: CGRect
    let safeTop: CGFloat        // height of the notch slit
    let auxLeft: CGFloat        // width of the left auxiliary area
    let auxRight: CGFloat       // width of the right auxiliary area
}
func frame(for state: PresentationState, on geo: ScreenGeometry) -> CGRect

// ✅ WindowManager is notified in didSet and applies the state to the panels by hand
// (clickable region + hover arming; the window itself is fixed and never resizes)
coord.onPresentationChange = { [weak self] in self?.applyFrames() }

// ❌ SwiftUI dictating the window size
.frame(width: expanded ? 420 : 220)   // animates the view; the NSPanel is left behind
```

## TDD

Depth — every clause below with the failure that produced it — in docs/TESTING.md.

- Framework: **Swift Testing** (`@Test`/`#expect`; Xcode 16+ — the macOS 14 deployment target is unaffected). Tests mirror the app's structure in `CremaTests/`; protocol mocks in `CremaTests/Mocks/`.
- Test waits are **wall-clock-bounded and MainActor-fair**, never yield-counted: a budget of scheduler slots runs out on a saturated machine, a deadline does not (`TestSupport.boundedWaitDeadline`, 5 s locally, environment-scalable to 25 s in CI). A test double that parks a real thread uses that SAME budget, never a constant of its own.
- **`#expect` does not halt the test** — an index precondition (a `count` followed by a subscript, a `!` on an optional) uses `try #require` or a whole-collection assertion: a trap kills the process, takes the in-flight siblings with it, and the verdict line never prints.
- **A test double never carries a real wall clock**, including through a constructor default: every test that builds a clock-bearing type injects **all** of its clocks, even the one that will never advance — otherwise the runner's CPU decides a deadline and the test goes green for the wrong reason.
- **A negative claim is proven by a barrier, never by yield counting** — a sentinel emitted BEHIND what is being denied, on the same ordered stream. The barrier is an END-OF-WORK signal, not fact-arrival, and every `advance()` on a test clock is preceded by `waitForSleep()`.
- **Never a unit test against a real system API** — real sources never enter tests; the mocks implement the protocols. The thin edge (the adapter process, Core Audio, the event tap, the real `DistributedNotificationCenter`) is validated by smoke or by hand, and stays thin precisely so everything interesting is testable above it.
- CI runs the suite **serial**, and the verdict is the `Test run with N tests` line, never xcodebuild's exit — **absence of a verdict is failure**, including when it exits 0.
- Minimum focus (living checklist):
  - [ ] Coordinator: state transitions, HUD priority, timer revert (with mocked sources, without touching a system API)
  - [ ] Window rules (`windowFrame`) per style, including the notch computation
  - [ ] Now-playing fallback when the adapter is unavailable
  - [ ] Integration source: decode the OSD notification and map it to the correct `SystemHUD`; the app works normally when the integration is absent (graceful degradation)

## Never do

- Never use any brightness API beyond the ones validated by spike (macOS 26 / Apple Silicon) — screen via **DisplayServices** (`DisplayServicesGet/SetBrightness`, dlopen/dlsym) and keyboard via **CoreBrightness** `KeyboardBrightnessClient` (dlopen + ObjC runtime), with the keyboard ID **enumerated** (`copyKeyboardBacklightIDs` + `isKeyboardBuiltIn:`), never hardcoded; **discarded** (tested, do not work on this hardware): CoreDisplay (returns a fixed 1.0) and IOKit `IODisplayGetFloatParameter` (dead service on Apple Silicon). Every private symbol/class lookup is checked: nil ⇒ `isAvailable() == false` and the feature degrades without crashing.
- Never call MRMediaRemoteGetNowPlayingInfo directly (blocked on 15.4+) — always via mediaremote-adapter, with fallback
- Never let an Apple type (MediaRemote/Core Audio) or BetterDisplay's JSON leak up into the view layer — translation to the domain happens at the edge (golden rule); an outside format above the source couples the UI to the fragile part of the system
- Never suppress the native OSD without making it reversible and opt-in (and never leave the user without volume control: consuming a key requires apply+verify; a failure suspends the **domain** that failed and hands its keys back to the system, with a probe re-engaging on recovery) — a consumed key always produces feedback: at the edge of the scale the HUD refreshes showing the clamped value, as the native one does — and **no failure path writes the persisted preference**
- Never swallow a key aimed at a display the app does not actuate — the pointer gate hands the whole key back (down, autorepeats and up, via the `SuppressionDecider` latch), because swallowing would move the wrong screen or eat the keypress without drawing anything. Corollary for when the external cycle exists: gating on "built-in only" makes that cycle dead code precisely in clamshell, the arrangement it was written for — and the suite stays green
- Never fight for position in the event tap chain to take back a key another app got first — neither by reinserting in a loop nor by tapping at `kCGHIDEventTap`: two legitimate features can want the same key, and the choice belongs to the user. Crema names who is ahead and stops there
- Never couple a style to the core — a new skin must not require changes in Sources/Domain/Coordinator
- Never update the window frame through SwiftUI — every style uses a FIXED window (`windowFrame`; only the content animates); the per-state frame applied by hand exists only as a defensive fallback for some future view that fills the window. Never reintroduce per-state setFrame in the styles
- Never let a write guarantee depend on the chrome — a `Picker` in `.menu` style **discards** the options' `.disabled` (measured on macOS 26.5.2, `scripts/probes/picker-option-disabled.swift`: the checked item read `isEnabled == true` against an `NSPopUpButton` whose natively disabled item read `false`), so the option the screen does not draw is still clickable there. What blocks the write is the pure rule the control calls (`DisplayStyleOptions.write(for:)`, which answers `refused` and writes nothing); the custom `Menu` only takes the option out of REACH (docs/DECISIONS.md: the-chrome-is-not-the-guarantee)
- Never treat the BetterDisplay/Lunar integration as mandatory — it is an optional enhancement; without it the app covers the built-in display + system volume
- Never implement our own DDC — external brightness/volume control is delegated to BetterDisplay/Lunar. For brightness, both directions already exist over that channel (reading via the OSD notification, writing via request/response); what remains roadmap is Crema **applying a key** to an external display, which needs the apply+verify cycle, and external volume, which Core Audio cannot see. And applying a key to an external is **blocked by measurement, not for lack of work**: the neighbour's `get` refuses every spelling of brightness (and the nine relative forms too), so there is no `before` for the step — external brightness is write-only from our edge (docs/DECISIONS.md: external-brightness-is-write-only; instruments in `scripts/probes/`)
- Never block the main thread waiting on an external process (`waitUntilExit`, `readDataToEndOfFile`) — stdout is read as an async stream, and EOF means unavailability
- Never write a unit test that touches a real system API — real sources never enter tests; the mocks implement the protocols
- Never keep OSD suppression engaged with the screen locked or the session off the console — there is no public path to draw over the lock shield (docs/LOCKSCREEN-INVESTIGATION.md): the user would be left with no feedback at all. The lock-aware suspension never alters the persisted preference. **The word public is load-bearing:** a window LEVEL never reaches the shield, but the shield is a SPACE, and a private SkyLight path over it is proven on hardware. So the rule stands on a decision rather than on impossibility — spending a private space API on the HUDs, which are a security surface's worth of noise several times a day. **There is no longer an exception.** An opt-in now-playing card took that path for one session and was removed whole, so the app has no private window API at all (docs/DECISIONS.md: the-lock-screen-was-built-and-taken-out)
- Never copy, transcribe or adapt third-party code — not from copyleft projects, and not from permissive ones either. From the neighbours studied we use approaches, principles and numeric values (facts, not protected), described in prose. Crema is GPL-3.0 and writing everything from scratch is independent of the licence — it keeps the code free of inherited lineage. The licence table of the audited neighbours (Atoll, boring.notch, MewNotch, SlimHUD — GPL-3.0; NotchDrop, DynamicNotchKit, volumeHUD — MIT; verified 2026-07-04) lives in the git history (docs/design-reference.md §0, deleted 2026-08-08)
- Never pre-set Sparkle's consent defaults (`SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`) and never compile the updater in Debug — consent belongs to Sparkle itself, and the Debug-without-updater contract is pinned by test (`SparkleUpdaterTests`). And never edit `docs/appcast.xml` by hand: the feed is now signed (`SURequireSignedFeed`), so any byte altered after generation breaks verification for every client that carries the key — regenerating through `release.sh` is the only path

## Known gaps

Deliberate debts, one line each — the reasoning, the palliative and the reopening gate of every open item live in docs/KNOWN-GAPS.md. A closed gap moves its lesson to the place that outlives it (a DECISIONS.md anchor, a test, a comment at the site) and leaves both lists.

- [ ] **The composition root (`AppCore.init`) is mostly unpinned, by decision** — 224 wiring points, 181 untested; the 5 where a mistake produces a plausibly wrong app are extracted into `wire*` seams and killed by mutation (`AppCoreWiringSeamTests`); the rest stays, in five named classes.
- [ ] **CLAUDE.md exceeds the grammar's soft limit** — the area sections and the gap detail are extracted; `Stack`, `Folder structure` and `Never do` stay inline by decision, read on arrival rather than looked up.
- [ ] **`BrightnessConversion` and `VolumeConversion` hold eight byte-identical lines, and that is the decision** — independent domains agreeing on a defensive contract; the rule of three has not been met. Reopening gate: a third domain wanting the clamp, or the first divergence between these two.
- [ ] **The waveform carries no time veto** — the two app-wide vetoes and nothing else; the case for a third is unestablished until someone measures the power cost of four 12 pt bars (the display sleeping does not stop compositing — measured).
- [ ] **A process finishing is not its children finishing** — the mediaremote-adapter outlives whoever spawned it; `release.sh` reaps it by path, the app-hosted test target still leaks it per run, and closing a round includes `ps` for stray children.
- [ ] **SwiftLint's analyzer rules are off, so nothing in CI looks for dead code** — a gate would build twice; the palliative is a by-hand sweep (zero unused `private` declarations across 320 files), and spending the CI minutes is the maintainer's call.

## Open decisions

- [x] **`SWIFT_VERSION = 5.0` in the pbxproj × `--swiftversion 6` in `.swiftformat`** — resolved: project raised to Swift 6 language mode (`SWIFT_VERSION = 6.0`; the formatter already assumed it), full suite green; the individual concurrency annotations are documented at their sites (2026-07-27).
- [x] **The lock screen's own geometry, and whether a measured constant may ship** — resolved: it may, with its measurement attached and its expiry named — the rule now lives in "A constant read off the screen carries its measurement".
- [x] **Where the high-resolution cover comes from** — resolved: the Cover Art Archive, never Apple's Search API, whose terms grant album art only beside a purchase badge (docs/DECISIONS.md: the-cover-comes-from-the-archive-not-the-store); the feature was then removed whole (2026-08-08), so the decision has no subject — the reasoning stands for whoever picks a source again (docs/DECISIONS.md: the-click-was-the-last-thing-holding-the-lookup-up).

None pending.
