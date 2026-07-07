# Contributing to Crema

Thanks for taking the time to help. Crema is a small, focused app, and
contributions that keep it that way are the most welcome kind.

## Reporting a bug

Open an [issue](../../issues) and include enough for someone to reproduce it:

- Your macOS version and Mac model (and whether it has a notch).
- Which style you're using (notch, card, or classic).
- What you did, what you expected, and what happened instead.
- A screenshot or short screen recording if the problem is visual.

If it relates to the volume or brightness HUDs, mention whether Crema had the
Accessibility permission and whether native-HUD replacement was on.

## Suggesting a feature

Crema is deliberately narrow in scope (see _What Crema is_ in the
[README](README.md)). Feature ideas are welcome, but the ones most likely to land
are those that sharpen what's already here rather than broaden it. Open an issue
to talk it through before writing code — it saves everyone effort.

## Branches

- **`main`** — the stable, released branch: it's what users download, and every
  merge into it is a release. Nothing lands here directly.
- **`dev`** — the integration branch where work comes together. Pull requests
  target `dev`.

Branch off `dev`, and name the branch for what it does:

- `feature/short-description` — a new capability
- `fix/short-description` — a bug fix
- `docs/short-description` — documentation

Keep it lowercase, hyphenated, and descriptive — for example
`fix/scrubber-jump-on-pause` or `feature/spanish-localization`.

## Submitting a pull request

1. Fork the repo and create your branch from **`dev`**.
2. Keep the change focused. Small, self-contained pull requests are easier to
   review and quicker to merge.
3. Make sure the tests pass (`⌘U` in Xcode, or `xcodebuild ... test`) and add
   tests for new behavior where it makes sense.
4. Match the surrounding code. The conventions are written up in
   [`CLAUDE.md`](CLAUDE.md) — architecture, naming, concurrency, and how the
   layers talk to each other.
5. Open the pull request against **`dev`** with a clear description of what
   changed and why.

Continuous integration builds the app, checks formatting with SwiftFormat, runs
SwiftLint, and runs the test suite on every pull request; the check needs to pass
before a change can be merged.

By contributing, you agree that your contributions are licensed under the
project's [GPL-3.0 license](LICENSE).

## Formatting and linting

The project uses two tools, both checked in CI. Run them before you commit:

```bash
swiftformat .        # apply formatting
swiftlint            # or `swiftlint --fix` to autocorrect what it can
```

[SwiftFormat](https://github.com/nicklockwood/SwiftFormat) (config in
[`.swiftformat`](.swiftformat)) handles layout — indentation, blank lines, and
the like. The config is deliberately conservative: it preserves the code's
existing style and only standardizes a few things, so `swiftformat .` should be
close to a no-op on a clean tree. CI runs `swiftformat --lint` and fails if any
file isn't formatted.

[SwiftLint](https://github.com/realm/SwiftLint) (config in
[`.swiftlint.yml`](.swiftlint.yml)) catches correctness and style issues that go
beyond layout. CI runs it in strict mode, so it needs to pass.

Both tools are pinned to a specific version in CI; if a local run is clean but CI
flags something (or vice versa), a version mismatch is the likely cause. Match
the pinned versions with `brew install swiftformat swiftlint` (or check
[`ci.yml`](.github/workflows/ci.yml) for the exact versions).

SwiftFormat parses Swift on its own and needs nothing extra. SwiftLint, though,
loads `sourcekitd`; if it fails to, point it at a full Xcode rather than the
Command Line Tools:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftlint
```

## A note on third-party code

Crema is written from scratch and does not copy code from other projects,
including the ones credited in the README. Please keep contributions original —
don't paste in code from other apps, regardless of their license.
