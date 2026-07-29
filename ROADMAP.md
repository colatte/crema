# Roadmap

Crema does a few things, and tries to do them well. This is where it might go
next — directions and possibilities, not promises or dated commitments. If one of
these matters to you, contributions are welcome; see
[CONTRIBUTING.md](CONTRIBUTING.md).

## External displays

Crema already draws its HUDs on any display (the now-playing player defaults
to the built-in one — see Per-display styles below) — what it *controls*
today is the built-in display's brightness and the system volume. Brightness and volume
on external monitors rely on DDC, which is fiddly and fragile to drive directly.
Rather than reinvent that, the idea is to integrate with tools that already handle
it well — [BetterDisplay](https://github.com/waydabber/BetterDisplay) or
[Lunar](https://github.com/alin23/Lunar). With one of them installed, Crema's HUD
could cover external displays too, while staying entirely optional for everyone else.

## Per-display styles

The style you pick applies to every display today, even though each display
already has its own window. The preference store is keyed per display under the
hood (style, and a "show now playing here" flag that defaults to the built-in
display); what's missing is the Settings surface to choose, say, _notch_ on the
MacBook and _classic_ on the monitor — or which displays show the player at all.

## Automatic updates

Crema ships as a direct download, and updates are manual for now: new versions
mean a trip back to the releases page. The groundwork for built-in automatic
updates — through [Sparkle](https://sparkle-project.org) — is already in place:
release builds embed Sparkle, and the release pipeline generates a signed update
feed (an intentionally empty placeholder today; it goes live on GitHub Pages
with the first Sparkle release). What remains is shipping a first release into
that feed and validating an update end to end — then Crema can keep itself
current.

## Signing and notarization

Crema ships signed with a self-signed certificate — enough for a stable code
identity across versions, but not trusted by Apple, so macOS still flags it as
coming from an unidentified developer the first time you open it (the
[installation notes](README.md#installation) explain how to get past that). The
release pipeline already implements the full Developer ID + notarization path;
what's missing is the Apple Developer account behind it. Once that exists, the
first-launch warning goes away.

## A Tahoe-native icon

The app icon ships in the classic format, which every macOS version renders
(Tahoe applies its own treatment to it automatically). A native Icon Composer
version — with proper Liquid Glass layers — is a natural next step; it needs
the source art split into layers (background, pill, wave) first.

## More languages

Crema is built on Apple's String Catalog and currently ships in English and
Brazilian Portuguese. More languages are very welcome, and this is the easiest and
most valuable place to help: if you speak a language Crema doesn't cover yet — say,
Spanish or Japanese — a translation goes a long way. Contributions from native
speakers are especially appreciated.
