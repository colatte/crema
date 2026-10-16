# Documentation map

> What lives where in Crema's documentation.
>
> GitHub Pages publishes `/docs` from `main`; the site's homepage is
> `index.html`, not this file. This map is what you read
> when browsing the repository on GitHub. Repository links below stay
> absolute — relative links like `../README.md` would break anywhere Pages
> renders this file outside the repository tree.

## Repository root

- [README.md](https://github.com/colatte/crema/blob/main/README.md) — public overview: what Crema is, installation, usage, license.
- [CONTRIBUTING.md](https://github.com/colatte/crema/blob/main/CONTRIBUTING.md) — how to contribute.
- [AGENTS.md](https://github.com/colatte/crema/blob/main/AGENTS.md) — the contract for how code is written in this repository: architecture, conventions, concurrency, and the rules the layers live by. Read at the start of every working session; evolves with the code.
- [SPEC.md](https://github.com/colatte/crema/blob/main/SPEC.md) — what the app is and why, with everything planned-but-not-built isolated in a final section. The acceptance criteria are not restated there; they live in `ACCEPTANCE.md` below.
- [PLAN.md](https://github.com/colatte/crema/blob/main/PLAN.md) — the order of execution: only what is still open, each item with the module that owns it. What already stands is not listed there — the shipped app is described, in the present, by `SPEC.md`.
- [LICENSE](https://github.com/colatte/crema/blob/main/LICENSE) — GPL-3.0.
- `release-notes/` — one file per released version, `<version>.html` (or `.md`), which `scripts/release.sh` feeds to the Sparkle update panel and `gh release create` to the GitHub Release body. Versioned because that text ships to every user anyway.

## docs/

- [index.html](https://github.com/colatte/crema/blob/main/docs/index.html) — the homepage GitHub Pages serves: a static landing page in the system font, with no script library. Every picture of the app is a capture from `assets/site/`, and the icon and favicon come from `assets/web/`.
- [DECISIONS.md](https://github.com/colatte/crema/blob/main/docs/DECISIONS.md) — design memory: the load-bearing decisions behind the fragile parts of the system, plus bug-class jurisprudence. Code comments cite its anchors as `(docs/DECISIONS.md: <anchor>)` but always carry the lesson themselves; the anchor is a pointer for depth.
- [ACCEPTANCE.md](https://github.com/colatte/crema/blob/main/docs/ACCEPTANCE.md) — the acceptance criteria (numbered, the retired ones struck through in place): the observable definition of "the app is correct", each one checkable on a running Crema.
- [RELEASE-GUIDE.md](https://github.com/colatte/crema/blob/main/docs/RELEASE-GUIDE.md) — how a release is built, signed, packaged and published, and how the Sparkle update cycle is fed — including the one-time backup of the EdDSA private key, whose loss would end the update channel for every installation.
- [LOCKSCREEN-INVESTIGATION.md](https://github.com/colatte/crema/blob/main/docs/LOCKSCREEN-INVESTIGATION.md) — the measured facts about drawing over the lock shield: no window level reaches it, the shield is a space and a private SkyLight path over it exists. The evidence behind lock-aware suppression, which code comments cite; the app draws nothing over the shield (docs/DECISIONS.md: the-lock-screen-was-built-and-taken-out).
- [SOURCES.md](https://github.com/colatte/crema/blob/main/docs/SOURCES.md), [STATE-FLOW.md](https://github.com/colatte/crema/blob/main/docs/STATE-FLOW.md), [TESTING.md](https://github.com/colatte/crema/blob/main/docs/TESTING.md) and [INTERNATIONALIZATION.md](https://github.com/colatte/crema/blob/main/docs/INTERNATIONALIZATION.md) — the depth behind four areas AGENTS.md states in one line each: the system edge, presentation state and animation, the test discipline, and the String Catalog with its reserved vocabulary. AGENTS.md carries the rule; these carry the mechanism and the measurement that produced it.
- [BRAND.md](https://github.com/colatte/crema/blob/main/docs/BRAND.md) — how Crema looks, sounds and writes its own name: the icon as the only mark (no wordmark — the dotted lowercase belongs to `colatte.` and `brio.`), "Crema" in prose, the landing's palette as Colatte's espresso dialect value for value, Raleway standing in for the house's licensed display face, the period-in-titles rule and where it stops, and the house endorsement. One page, because almost everything visual is borrowed from the house and the page says from where.
- [CONTRACTS.md](https://github.com/colatte/crema/blob/main/docs/CONTRACTS.md) — the twenty-six named contracts the code cites by id (`MG*`, `W*`, `S*`, `P*`), so a comment saying "S4" means one precise thing everywhere it appears.
- [GITHUB.md](https://github.com/colatte/crema/blob/main/docs/GITHUB.md) — the repository's settings that live outside the tree: the protection on `main` and `dev` (a pull request, the `Build & test` check, an up-to-date branch, resolved conversations — binding administrators too), the merge buttons, Dependabot's targets, and the idempotent `gh api` block that reapplies all of it.
- [KNOWN-GAPS.md](https://github.com/colatte/crema/blob/main/docs/KNOWN-GAPS.md) — the deliberate debts in full: for each open gap, the reasoning that made it a decision, the palliative standing in for the fix, and the gate that would reopen it. AGENTS.md lists them one line each.
- [KEY-LATENCY-INVESTIGATION.md](https://github.com/colatte/crema/blob/main/docs/KEY-LATENCY-INVESTIGATION.md) — an OPEN investigation with no fix: a media key that occasionally lags, with the three candidate profiles mapped to disjoint code paths and the capture that would tell them apart. Nothing is touched until that capture exists.
- [system-contact-inventory.md](https://github.com/colatte/crema/blob/main/docs/system-contact-inventory.md) — every place the app touches a resource that can die underneath it: where in the code, and what happens when it goes away. Each row names its site, which stays the authority.
- `assets/` — the web export of the app icon (`icon.png`) and the README's download badge (`download-macos.png`, generated by `design/badge/makedownloadbadge.swift` — regenerate there, never edit by hand). Two captures are kept for reference that no page links yet — the notch at rest (`notch-compact.png`) and the Settings window (`settings-about.png`); naming them here is what keeps a future sweep from reading them as litter.
- `assets/site/` — the captures of the app the landing page and the root README show, and the page's hero video, taken from the real app on the demo sources by [`scripts/site-capture/capture.sh`](https://github.com/colatte/crema/blob/main/scripts/site-capture/capture.sh) and replaced by running it again, never by hand. It takes over the screen for a few minutes, and the notch shots need a built-in display with a notch.
- `assets/web/` — the icon and the favicon at the sizes the landing page uses, derived from `assets/icon.png` by [`scripts/make-web-assets.sh`](https://github.com/colatte/crema/blob/main/scripts/make-web-assets.sh) and regenerated there, never edited by hand.
- [appcast.xml](appcast.xml) — the live Sparkle update feed, served by GitHub Pages (/docs from main). `scripts/release.sh` regenerates it on every release, and the file is never touched by hand: each enclosure needs an EdDSA signature only the release tooling produces, and the feed itself is signed, so an edit after generation is an outage rather than a mess (docs/DECISIONS.md: the-feed-signs-itself).

## scripts/

- [release.sh](https://github.com/colatte/crema/blob/main/scripts/release.sh) — the release: build, build-number stamp, signing (ad-hoc / self-signed / Developer ID + notarization), dmg, and the appcast regeneration. It commits nothing.
- [check-catalog.py](https://github.com/colatte/crema/blob/main/scripts/check-catalog.py) and [check-catalog-selftest.py](https://github.com/colatte/crema/blob/main/scripts/check-catalog-selftest.py) — the String Catalog gate, plus the self-test that proves the gate still fails on every rule it claims to enforce. Both run in CI; Xcode enforces none of it.
- `probes/` — standalone hardware probes (`swift scripts/probes/<name>.swift`). Each one decides a question no unit test can answer — is the neighbour publishing, does a held media key repeat, does one keypress move two displays — and each carries a control that makes a negative result mean something. They are instruments, not part of the app or of CI.
