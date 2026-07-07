# Roadmap

Crema does a few things, and tries to do them well. This is where it might go
next — directions and possibilities, not promises or dated commitments. If one of
these matters to you, contributions are welcome; see
[CONTRIBUTING.md](CONTRIBUTING.md).

## External displays

Today Crema covers the built-in display and system volume. Brightness and volume
on external monitors rely on DDC, which is fiddly and fragile to drive directly.
Rather than reinvent that, the idea is to integrate with tools that already handle
it well — [BetterDisplay](https://github.com/waydabber/BetterDisplay) or
[Lunar](https://github.com/alin23/Lunar). With one of them installed, Crema's HUD
could cover external displays too, while staying entirely optional for everyone else.

## Automatic updates

Crema ships as a direct download, so updates are manual for now. Built-in
automatic updates — through [Sparkle](https://sparkle-project.org) — would let it
keep itself current without a trip back to the releases page.

## Signing and notarization

Crema isn't code-signed or notarized yet, so macOS flags it as coming from an
unidentified developer the first time you open it (the
[installation notes](README.md#installation) explain how to get past that). A
signed, notarized build would let it open without that step — a natural thing to
add as the project matures.

## More languages

Crema is built on Apple's String Catalog and currently ships in English and
Brazilian Portuguese. More languages are very welcome, and this is the easiest and
most valuable place to help: if you speak a language Crema doesn't cover yet — say,
Spanish or Japanese — a translation goes a long way. Contributions from native
speakers are especially appreciated.
