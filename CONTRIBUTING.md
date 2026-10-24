# Contributing to Crema

Thanks for taking the time to help. Crema is a small, focused app, and
contributions that keep it that way are the most welcome kind.

## Getting started

You need **Xcode 27** (the app links against the macOS 27 SDK and runs on
macOS 14 or later).

```bash
git clone https://github.com/colatte/crema.git
cd crema
open Crema.xcodeproj
```

Select the **Crema** scheme, then `⌘R` to run and `⌘U` to test. Before opening
a pull request, run the same checks CI runs:

```bash
xcodebuild -project Crema.xcodeproj -scheme Crema test
swiftlint lint --strict && swiftformat --lint .
python3 scripts/check-catalog-selftest.py && python3 scripts/check-catalog.py .
```

Read the test verdict from the `Test run with N tests` line, not from
xcodebuild's exit: the test host is the app, and its teardown can hang after
every test has already reported.

The Debug build adds a **Demo** menu that runs the real pipeline on fake
sources, so you can exercise the player and the indicators without media or
hardware. The conventions the code follows (architecture, naming, concurrency,
how the layers talk) are written up in [AGENTS.md](AGENTS.md).

## Reporting a bug

Open an [issue](../../issues/new?template=bug.yml). The form asks for what a
reproduction needs: what happened, the steps, what you expected, and your setup
(macOS version, Mac model, Crema version, style in use, displays, permission
state). Most of Crema's behavior depends on that last list, so the same bug can
be real on one setup and impossible on another. A screenshot or a short screen
recording helps whenever the problem is visual.

## Suggesting a feature

Crema is deliberately narrow in scope (see _What Crema is_ in the
[README](README.md), and SPEC.md's
[planned section](SPEC.md#planned--not-implemented-future-roadmap) for what's
already on the way). The ideas most likely to land sharpen what's already here
rather than broaden it. Open an
[issue](../../issues/new?template=feature.yml) to talk it through before
writing code; it saves everyone effort.

## Pull requests

1. Fork the repo and branch from **`dev`**.
2. Keep the change focused. Small, self-contained pull requests are easier to
   review and quicker to merge.
3. Add tests for new behavior where it makes sense, and run the checks above.
4. Match the surrounding code ([AGENTS.md](AGENTS.md)).
5. Open the pull request against **`dev`**, saying what changed and why. The
   template asks for the before and after, the proof, the docs touched, and
   what stays open.

CI gates every pull request, in order: SwiftLint in strict mode, SwiftFormat
as a lint, the String Catalog checker, the test suite, and a Release build with
its signature flags verified (Release is the only configuration that compiles
the updater). All of it must pass before a change can be merged.

By contributing, you agree that your contributions are licensed under the
project's [GPL-3.0 license](LICENSE).

### Branches

- **`main`** is the released branch: it's what users download, and every merge
  into it is a release, except a documentation-only merge, which may reach it
  between releases when the diff touches nothing but the repository's prose
  (docs/DECISIONS.md: main-takes-docs-outside-a-release).
- **`dev`** is where work comes together. Pull requests target `dev`.

Both are protected, administrators included: a pull request, the `Build & test`
check green, the branch up to date and every review conversation resolved. A
`git push` straight to either is rejected, the owner's included; the settings
and the reason for each live in [docs/GITHUB.md](docs/GITHUB.md).

Name the branch for what it does, lowercase and hyphenated:

- `feature/short-description` for a new capability
- `fix/short-description` for a bug fix
- `docs/short-description` for documentation
- `t<id>-short-description` for a task from [PLAN.md](PLAN.md), the id first
  (`t10.2-quantized-verify`): the id ties the branch to the task, the same
  reason the PLAN never renumbers one.

One branch per task or fix, cut from `dev` and gone at the merge. Merges are
merge commits, never squashes: the commits on `dev` are written to tell the
change, and the squash and rebase buttons are switched off.

## Issues and the docs

An issue is **work**: what's wrong or missing, and when it's done. The rules
live in the repository's documents (conventions in [AGENTS.md](AGENTS.md),
design memory in [docs/DECISIONS.md](docs/DECISIONS.md)), and an issue points
at them when one applies. No document cites an issue number back, because
issues close and the number goes stale. The area labels (`now playing`,
`indicators`, `styles`, …) are triage, so don't worry about picking any; blank
issues are fine when neither form fits. There is no Projects board:
[PLAN.md](PLAN.md) is the living order of execution, and a board would be a
second copy of it, aging.

An issue closes when the fix reaches **`main`**, the build users download, not
at the merge to `dev`: GitHub's auto-close only fires from the default branch,
so the release pull request closes what it carries.

## Translations

UI strings live in the String Catalog (`Crema/Localizable.xcstrings`): English
is the source language and pt-BR ships as the first translation. To improve a
translation or add a language, edit the catalog (Xcode renders it as a table);
every key must keep a non-empty unit per language. The checks cover only the
shipped pair (the test suite pins en↔pt-BR parity, and CI's catalog checker
reads pt-BR alone), so a new language arrives outside the net: extend both
checks in the same change, or its missing units ship silently. The reserved
vocabulary and the rules for each language are in
[docs/INTERNATIONALIZATION.md](docs/INTERNATIONALIZATION.md).

## Formatting and linting

[SwiftFormat](https://github.com/nicklockwood/SwiftFormat) (config in
[`.swiftformat`](.swiftformat)) handles layout. The config is deliberately
conservative, so `swiftformat .` should be close to a no-op on a clean tree;
CI runs `swiftformat --lint` and fails if any file isn't formatted.
[SwiftLint](https://github.com/realm/SwiftLint) (config in
[`.swiftlint.yml`](.swiftlint.yml)) catches correctness and style issues beyond
layout, and CI runs it in strict mode.

```bash
swiftformat .        # apply formatting
swiftlint --fix      # autocorrect what it can
```

Both tools are pinned in CI. Homebrew (`brew install swiftformat swiftlint`)
installs the latest versions, which may be newer: when a local run and CI
disagree, use the exact versions from [`ci.yml`](.github/workflows/ci.yml),
which downloads the release binaries directly. SwiftLint loads `sourcekitd`; if
it fails to, point it at a full Xcode rather than the Command Line Tools:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftlint
```

Compiler warnings are not gated: no build setting turns them into errors and CI
does not count them. A concurrency-isolation warning in app code is fixed when
it is seen, in the change that sees it.

## Third-party code

Crema is written from scratch and does not copy code from other projects,
including the ones credited in the README. Please keep contributions original:
don't paste in code from other apps, whatever their license.
