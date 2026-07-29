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
[Lunar](https://github.com/alin23/Lunar).

Both directions are in for the **built-in** display: Crema draws the brightness
HUD from BetterDisplay's OSD notification, and a drag on that bar is sent back to
BetterDisplay so it lands on the same scale the bar was drawn in (see Usage in
the [README](README.md#usage)). External displays are reachable the same way —
the write works — but Crema draws the same HUD on every screen and none of them
says which display the bar belongs to, so a bar on the laptop silently dimming
the monitor next to it would be worse than no bar. **Per-display HUD presentation
is what unlocks external displays**, and it is the same seam Per-display styles
below needs. The equivalent integration for Lunar is still open.

## Per-display styles

The style you pick applies to every display today, even though each display
already has its own window. The preference store is keyed per display under the
hood (style, and a "show now playing here" flag that defaults to the built-in
display); what's missing is the Settings surface to choose, say, _notch_ on the
MacBook and _classic_ on the monitor — or which displays show the player at all.

## Automatic updates — shipped in 1.2.0 ✓

Since v1.2.0, Crema keeps itself current: release builds embed
[Sparkle](https://sparkle-project.org), and the app checks a signed update feed
on GitHub Pages — with your consent (Sparkle asks first), or on demand via
**Check for Updates…** in the menu bar. What remains on this front is
notarization, below.

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
