# Known gaps — the deliberate debts, in full

> The inventory of debts this project carries **on purpose**, each with the
> reasoning that made it a decision rather than an oversight, the palliative
> that stands in for the fix, and the gate that would reopen it. CLAUDE.md
> lists these one line each; this file is the depth. A gap that gets closed
> moves its lesson to the place that outlives it (a DECISIONS.md anchor, a test,
> a comment at the site) and leaves this file.

## The composition root (`AppCore.init`) is mostly unpinned, by decision

Audit of the `App` layer: **224 wiring points, 181 with no test at all**, a single root cause already confessed in a comment in the suite itself — *no test constructs an `AppCore`*, because the `init` touches ~8 system edges outside the `SystemGraph` (the AX permission and its poll, the event tap, `SMAppService`, the lock source, workspace observers, real `NSPanel`s, `UserDefaults`).

Closed the **5** where a wiring mistake **compiles, runs and produces a plausibly wrong app** — the brightness echo routed by authority, the post-apply poke, the escalation mirror the menu reads, the neighbour's source and its local sibling, and the notification center of the 4th trigger — each extracted into a `wire*` and killed by mutation (`AppCoreWiringSeamTests`).

The rest **stays**, in five classes:

1. Constructor arguments the type already decides, where the only conformer is the production one and a test would assert a distinction no observer makes.
2. Edges whose only honest observer is the real system (`SMAppService`, a live cursor, `describeAll()`, Settings URLs, Info.plist keys) — there a test is either tautology or a trip to hardware, and a mistake shows up on first launch.
3. `start()` and the retention guard, which break **loudly** on the build's first run, not silently.
4. What sits behind `#if DEBUG` and the duplicated construction in the `#else` — a real risk (the Debug-hosted suite does not compile the Release copy), but the fix is dedup, not a test.
5. The idea of an `AppCore` over doubles, which **moves** the hole instead of closing it — and an end-to-end test of the graph is less mutation-sensitive per line than the `wire*` seams, which fails the house criterion outright.

Two named survivors, accepted: `MenuInformation` (a 4-action switch — a button could re-register the login item under the re-enable-suppression label; the fix asks for a new protocol, more structure than the risk pays for) and `AppCoreAutomation:14` (a boolean inversion that would erase the Permissions line and leave a blocking consent poll running forever). A residue every `wire*` shares, and one still worth stating: they pin the **wiring**, not the `init` line that installs it.

What generalises, proven twice on a since-removed surface: rules killed by mutation while their call sites were reachable from no test, and extracting a seam refused as merely moving the untested line by one — this entry's verdict covers those cases too.

## CLAUDE.md exceeds the grammar's soft limit, and the remainder is a decision

The four largest area sections were extracted on 2026-08-10 (the system edge, state flow, the test discipline and i18n — each now a rule in CLAUDE.md and a mechanism in `docs/`), and this file took the Known gaps' detail in the same round; together they took CLAUDE.md from 101 KB to 66 KB. `Stack`, `Folder structure` and `Never do` stay inline by decision, because they are read on arrival rather than looked up. The residue is real and measured: every session pays for what is left, and the checker's report of it stays a warning rather than a violation for exactly that reason.

## Three grammar checks are suppressed, because the checker is Portuguese-keyed and the doc-set is English

`docscheck` verifies the mechanical invariants of the house grammar, and it recognises the structural
positions by their Portuguese names: the golden rule by a heading `Regra de ouro`, the present/future
frontier by a section `Planejado`, the module tree by a section `Estrutura`/`Módulos`. Crema's documents
are English — a decision, not an accident: this is a public GPL-3.0 repository whose README, ROADMAP and
CONTRIBUTING address contributors in English, and CLAUDE.md is the file any of them opens first.

So `C1` (CLAUDE.md), `F1` (SPEC.md) and `T3` (PLAN.md) are suppressed at their sites, each with its reason
on the line, which is what keeps a suppression auditable rather than silent. What is **not** suppressed is
`T2`: the task metadata field is spelled `· módulo:`, one Portuguese token in an English document, because
it is a field label rather than prose and it buys back the check that every task names a module — the
omission most likely to actually happen when a task is added.

The reason for suppressing instead of renaming is that the alternative costs prose, not tokens: `## Regra
de ouro` and `## Estrutura` are among the most-read lines of the two most-read documents, and a contributor
meets them before anything else. The reason for suppressing instead of ignoring the tool is that a gate
which always exits 1 is a gate nobody reads — the same failure `check-catalog-selftest.py` exists to
prevent — and with the baseline green a genuinely new violation is visible on the next run.

The palliative for `T3` specifically: the module names are verified against CLAUDE.md's `Folder structure`
tree by hand, and the suppression's reason names all four so the claim can be re-checked in seconds.

Reopening gate: the kit learning the English keywords. That fix belongs in the kit's own repository, not
here — `~/.claude/bin/docscheck.mjs` is overwritten by its `install.sh`, so a local patch would revert
silently, which is worse than the suppression. When the kit recognises both languages, all four lines come
out and `· módulo:` goes back to `· module:`.

## `BrightnessConversion` and `VolumeConversion` hold eight byte-identical lines, and that is the decision

Both spell `normalize`/`denormalize` as the same NaN-guarded clamp into `0...1`, and a shared helper was considered and refused. Volume and screen brightness are independent domains that happen to agree on a defensive contract today; folding them together would couple Core Audio's edge to DisplayServices' for the sake of four lines each, and the rule of three has not been met. This is NOT the `shared-skin-skeleton` case — that was ~120 lines with a proven history of a fix landing on two skins and missing the third. Reopening gate: a third domain wanting the same clamp, or the first divergence between these two (a domain that needs the infinities handled differently would be the signal). The palliative is that each side documents the contract in full, so a reader fixing one can see what the other promises.

## The waveform is the app's only perpetual animation, and it carries no time veto

`WaveformGlyph` (the desktop skins) dances under `dances(animating:reduceMotion:lowPower:)`, the two app-wide vetoes and nothing else; a third veto once existed (`ArtworkDrift`'s `settled`, at 180 s, on the lock surface's backdrop) and was deleted with that surface (docs/DECISIONS.md: the-lock-screen-was-built-and-taken-out), so the surface that invented the time veto is gone and no surviving one has it.

The case for adding one is NOT established and should not be built on the "runs all night" framing alone: the display sleeping does not stop compositing (measured, before the probe was retired — the process went on compositing for 67 s in the dark, and only SYSTEM sleep stopped it), but four 12 pt bars are a different order of cost from a full-screen blurred bitmap transform, and nobody has measured which side of "worth a timer" they fall on. What would settle it: a power reading with a surface lit and playing, against the same surface paused, on a Mac configured not to sleep. Until then the honest position is that the veto is missing on purpose rather than by oversight.

## A process finishing is not its children finishing

Two orphaned `python` processes from a documentation review were found at ~100% CPU each, one hour and ten minutes after the run completed, adopted by launchd when the agents that spawned them died. They came from a `/System` scan the prompt itself invited by offering it as an alternative to the prepared corpus. Two palliatives: a prompt that hands agents a prepared file must not ALSO offer the expensive path, and closing a round includes `ps` for stray children, not just the run's own completion.

**The same class was then found in SHIPPED TOOLING, and fixed** (2026-08-08): `release.sh`'s launch smoke starts the app, kills its PID after 5 s and `rm -rf`s the temp bundle — but Crema spawns the mediaremote-adapter as a long-lived perl child that does NOT die with its parent. Measured on the release machine: an adapter from a smoke run three minutes earlier was still alive and streaming, against a bundle path that no longer existed, and it would have survived until reboot. Two `pkill -f` calls matched on the mktemp path now reap it on both the pass and the fail branch — matched on the path precisely so it cannot touch the adapter of the author's real installed copy, which is the app they are using to test.

The lesson generalises past this script: **killing a process is not killing what it started, and a `rm -rf` afterwards makes the orphan invisible rather than absent.** The app-hosted test target leaks the same child for the same reason; that one is short-lived per run but shows up in `ps` after a long session.

## SwiftLint's analyzer rules are off, so nothing in CI looks for dead code

`analyzer_rules` is empty in `.swiftlint.yml`; `unused_declaration` and `unused_import` need a compiler log (`swiftlint analyze --compiler-log-path`), which means CI would build twice and gain a step that can break on its own. Measured by hand instead: zero unused `private` declarations across the whole tree, and the four internal types with no cross-file reference each have a use in their own file. The gap is that this was a one-off sweep, not a gate — a declaration that dies tomorrow dies unnoticed, and so does one born dead in a file added since. The palliative is that sweep, and the decision to spend CI minutes on it is the maintainer's.
