# Known gaps — the deliberate debts, in full

> The inventory of debts this project carries **on purpose**, each with the
> reasoning that made it a decision rather than an oversight, the palliative
> that stands in for the fix, and the gate that would reopen it. AGENTS.md
> lists these one line each; this file is the depth. A gap that gets closed
> moves its lesson to the place that outlives it (a DECISIONS.md anchor, a test,
> a comment at the site) and leaves this file.

## The composition root (`AppCore.init`) is mostly unpinned, by decision

Audit of the `App` layer: **224 wiring points, 181 with no test at all**, a single root cause already confessed in a comment in the suite itself — *no test constructs an `AppCore`*, because the `init` touches ~8 system edges outside the `SystemGraph` (the AX permission and its poll, the event tap, `SMAppService`, the lock source, workspace observers, real `NSPanel`s, `UserDefaults`).

Closed the **5** where a wiring mistake **compiles, runs and produces a plausibly wrong app** — the brightness echo routed by authority, the post-apply poke, the escalation mirror the menu reads, the neighbour's source and its local sibling, and the notification center of the 4th trigger — each extracted into a `wire*` and killed by mutation (`AppCoreWiringSeamTests`, `AppCoreHandbackWiringTests`, `SuppressionUnlockReinstallSeamTests`).

The rest **stays**, in five classes:

1. Constructor arguments the type already decides, where the only conformer is the production one and a test would assert a distinction no observer makes.
2. Edges whose only honest observer is the real system (`SMAppService`, a live cursor, `describeAll()`, Settings URLs, Info.plist keys) — there a test is either tautology or a trip to hardware, and a mistake shows up on first launch.
3. `start()` and the retention guard, which break **loudly** on the build's first run, not silently.
4. What sits behind `#if DEBUG`, the demo graph. The production graph is wired once, in `makeProductionGraph`, which the Debug-real and the Release branch both call, so the branch the Debug-hosted suite never compiles carries no wiring of its own.
5. The idea of an `AppCore` over doubles, which **moves** the hole instead of closing it — and an end-to-end test of the graph is less mutation-sensitive per line than the `wire*` seams, which fails the house criterion outright.

Two named survivors, accepted: `MenuStatus.Action` (a 5-case switch — a button could re-register the login item under the re-enable-suppression label; the fix asks for a new protocol, more structure than the risk pays for) and `AppCoreAutomation:14` (a boolean inversion that would erase the Permissions line and leave a blocking consent poll running forever). A residue every `wire*` shares, and one still worth stating: they pin the **wiring**, not the `init` line that installs it.

What generalises, proven twice on a since-removed surface: rules killed by mutation while their call sites were reachable from no test, and extracting a seam refused as merely moving the untested line by one — this entry's verdict covers those cases too.

## `BrightnessConversion` and `VolumeConversion` hold eight byte-identical lines, and that is the decision

Both spell `normalize`/`denormalize` as the same NaN-guarded clamp into `0...1`, and a shared helper was considered and refused. Volume and screen brightness are independent domains that happen to agree on a defensive contract today; folding them together would couple Core Audio's edge to DisplayServices' for the sake of four lines each, and the rule of three has not been met. This is NOT the `shared-skin-skeleton` case — that was ~120 lines with a proven history of a fix landing on two skins and missing the third. Reopening gate: a third domain wanting the same clamp, or the first divergence between these two (a domain that needs the infinities handled differently would be the signal). The palliative is that each side documents the contract in full, so a reader fixing one can see what the other promises.

## The waveform is the app's only perpetual animation, and it carries no time veto

`WaveformGlyph` (the desktop skins) dances under `dances(animating:reduceMotion:lowPower:)`, the two app-wide vetoes and nothing else; a third veto once existed (`ArtworkDrift`'s `settled`, at 180 s, on the lock surface's backdrop) and was deleted with that surface (docs/DECISIONS.md: the-lock-screen-was-built-and-taken-out), so the surface that invented the time veto is gone and no surviving one has it.

The case for adding one is NOT established and should not be built on the "runs all night" framing alone: the display sleeping does not stop compositing (measured, before the probe was retired — the process went on compositing for 67 s in the dark, and only SYSTEM sleep stopped it), but four 12 pt bars are a different order of cost from a full-screen blurred bitmap transform, and nobody has measured which side of "worth a timer" they fall on. What would settle it: a power reading with a surface lit and playing, against the same surface paused, on a Mac configured not to sleep. Until then the honest position is that the veto is missing on purpose rather than by oversight.

## A process finishing is not its children finishing

Two orphaned `python` processes from a documentation review were found at ~100% CPU each, one hour and ten minutes after the run completed, adopted by launchd when the agents that spawned them died. They came from a `/System` scan the prompt itself invited by offering it as an alternative to the prepared corpus. Two palliatives: a prompt that hands agents a prepared file must not ALSO offer the expensive path, and closing a round includes `ps` for stray children, not just the run's own completion.

**The same class lives in SHIPPED TOOLING:** `release.sh`'s launch smoke starts the app, kills its PID after 5 s and `rm -rf`s the temp bundle, but Crema spawns the mediaremote-adapter as a long-lived perl child that does NOT die with its parent (measured on the release machine: an adapter from a smoke run three minutes earlier was still alive and streaming, against a bundle path that no longer existed, and would have survived until reboot), so two `pkill -f` calls matched on the mktemp path reap it on both the pass and the fail branch — matched on the path precisely so it cannot touch the adapter of the author's real installed copy, which is the app they are using to test.

The lesson generalises past this script: **killing a process is not killing what it started, and a `rm -rf` afterwards makes the orphan invisible rather than absent.** The app-hosted test target leaks the same child for the same reason; that one is short-lived per run but shows up in `ps` after a long session.

## The keyboard-backlight client is resolved once, and no edge re-creates it

`CoreBrightnessKeyboardBridge.init` resolves the private `KeyboardBrightnessClient` — the class, its selectors and one instance — and holds that instance for the life of the process. Everything downstream of it was deliberately made per-operation, because a frozen handle is exactly how this family dies: the keyboard ID is re-enumerated on every read, write and availability check (`copyKeyboardBacklightIDs` + `isKeyboardBuiltIn:`), which closed the latent sibling of the display bridge's stale-ID death (docs/DECISIONS.md: J2-display-id-stale). The client is the one handle still frozen, and the IDs are enumerated OVER its connection: if that connection dies, every read returns nil, every write returns false, `isAvailable` asks the dead client and answers no, and the channel reports itself absent for the rest of the session. The four preventive-reinstall edges rebuild the media-key tap, not this.

Why it stays: the fix is not the code, it is knowing what to write. Re-resolving on a wake edge is a handful of lines, but whether a dead client is even reachable — whether the connection dies at all, whether the symptom is a nil read or a hang, whether a fresh client on the same machine recovers — is a hardware question nobody has answered here. The one probe that touches this class (`scripts/probes/hardware-probes.swift`, probe 2) hammers it from three threads to settle whether the bridge must serialize; it says nothing about a client that has died. Writing a recovery path against a failure nobody has reproduced would ship a rebuild on every wake for a fault that may not exist, on the border where every call is a private-framework round trip — and it would be untestable in the only way that counts, since the failure it recovers from cannot be staged.

The palliative is that the degradation is honest and total rather than partial: no crash, no fabricated value, no half-live channel — `isAvailable` answers false, the HUD stops surfacing, the keys go back to the system with their native feedback, and a relaunch restores everything. The other half of the channel already self-heals in the same shape a recovery would need: `PolledBrightnessSource.startPollingIfAvailable` re-arms the cadence at the first key after the channel answers again, so a bridge that DID come back would need nothing else added around it.

Reopening gate: a reproduction on hardware — a session where the backlight HUD stops while the keys still work, with a probe showing the enumeration empty (or the read failing) against a freshly constructed client that answers. That reproduction is also the test: the bridge's class resolver and ID provider are already injectable, so a re-resolve can be pinned without touching CoreBrightness.

## SwiftLint's analyzer rules are off, so nothing in CI looks for dead code

`.swiftlint.yml` declares no `analyzer_rules`; `unused_declaration` and `unused_import` need a compiler log (`swiftlint analyze --compiler-log-path`), which means CI would build twice and gain a step that can break on its own. Measured by hand instead: zero unused `private` declarations across the whole tree, and the four internal types with no cross-file reference each have a use in their own file. The gap is that this was a one-off sweep, not a gate — a declaration that dies tomorrow dies unnoticed, and so does one born dead in a file added since. The palliative is that sweep, and the decision to spend CI minutes on it is the maintainer's.

## The style declaration's adoption runs at every launch, with no exit

`Preferences.adoptDeclaredStyleFromOverrides` carries a pre-declaration install's style into the global declaration: before v1.4.0 the picker wrote per-display keys only, so that is where the user's choice lives. It runs on every launch, before the first panel roster, and nothing says when it may stop. It stays because Sparkle lets any older install update straight to the newest build, so an upgrade from before v1.4.0 can arrive at any time. The palliative is that it is idempotent and cheap: the presence of the declaration key closes it for good, an install with no override writes nothing, and what is left on every other launch is one key read. Reopening gate: a decision to stop supporting updates from installs older than v1.4.0; then the call and the method go, with the overrides untouched.

## The Privacy panes are opened by a hand-built URL

The Accessibility and Automation panes are opened with `x-apple.systempreferences:com.apple.preference.security?Privacy_…` (`AppCore.requestAccessibilityAccess`, `AppCore.openAutomationSettings`), the undocumented identifier kind Apple has already renamed once, and `NSWorkspace.open`'s `Bool` is discarded, so a renamed pane is a button that does nothing and says nothing. It stays because there is no public opener: the macOS 27.0 SDK's only `openSystemSettings…` method is `SMAppService.openSystemSettingsLoginItems`, which the Login Items repair already uses. The palliative covers Accessibility alone: the request raises the system's own prompt, which registers the app in that list; for Automation a dead link has no fallback. Reopening gate: Apple shipping an opener for the Privacy panes, or a renamed pane reported from the field. The cheapest first step then is logging the `false` that `open` returns.

## A guard in the native-OSD suppressor survives its own mutation

`MediaKeyInterceptionOSDSuppressor.noteAbsent` re-checks the engagement generation after its `await`, so a stale apply cannot write an absent capability into a newer engagement. The guard is not pinned, and removing it survives the suite: the window needs a stale apply to resume after an engage flip, and nothing observable marks that moment (the absent set has no test-visible snapshot, and a `.noOp` fires no callback), so every probe either presses too early, where both behaviours agree, or retries until the re-check has healed the difference. A test that pretended to pin it was written and removed rather than kept. The palliative is the comment at the site, which states the gap and its price. Reopening gate: a second reason to give the decider an absent-set snapshot, the way it already exposes `suspendedDomains`; with that snapshot the test can be written honestly.
