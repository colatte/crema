# Documentation map

> What lives where in Crema's documentation.
>
> This file is also the homepage of the project site: GitHub Pages publishes
> `/docs` from `main`, and a folder's README renders as its index. Repository
> links below are therefore absolute — relative links like `../README.md` would
> break on the rendered page.

## Repository root

- [README.md](https://github.com/colatte/crema/blob/main/README.md) — public overview: what Crema is, installation, usage, license.
- [ROADMAP.md](https://github.com/colatte/crema/blob/main/ROADMAP.md) — directions and possibilities; not promises, not dated commitments.
- [CONTRIBUTING.md](https://github.com/colatte/crema/blob/main/CONTRIBUTING.md) — how to contribute.
- [CLAUDE.md](https://github.com/colatte/crema/blob/main/CLAUDE.md) — the contract, in Portuguese, for how code is written in this repository: architecture, conventions, concurrency, and the rules the layers live by. Read at the start of every working session; evolves with the code.
- [LICENSE](https://github.com/colatte/crema/blob/main/LICENSE) — GPL-3.0.

## docs/

- [DECISIONS.md](https://github.com/colatte/crema/blob/main/docs/DECISIONS.md) — design memory: the load-bearing decisions behind the fragile parts of the system, plus bug-class jurisprudence. Code comments cite its anchors as `(docs/DECISIONS.md: <anchor>)` but always carry the lesson themselves; the anchor is a pointer for depth.
- [design-reference.md](https://github.com/colatte/crema/blob/main/docs/design-reference.md) — research, in Portuguese: visual styles and polish that inform the notch/card/classic skins. Values are starting points to calibrate on hardware, not absolutes.
- `assets/` — the README's images: the showcase screenshots and the web export of the app icon.
- [osd-suppression-reference.md](https://github.com/colatte/crema/blob/main/docs/osd-suppression-reference.md) — research, in Portuguese: suppressing the native volume/brightness OSD — techniques surveyed, constraints (reversible, opt-in, no SIP changes) and discarded paths.
- [appcast.xml](appcast.xml) — the live Sparkle update feed, served by GitHub Pages (/docs from main). `scripts/release.sh` regenerates it on every release, and feed items are never authored by hand (each enclosure needs an EdDSA signature only the release tooling produces).
- `internal/` — gitignored, local-only working docs (SPEC, PLAN, release guide, audits and investigations). References to `docs/internal/…` from code or public docs point here; the cited lesson is always restated where it is cited, so readers without this folder lose depth, never meaning.
