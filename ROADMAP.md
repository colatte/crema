# Roadmap

Crema does a few things, and tries to do them well. This is where it might go
next — directions and possibilities, not promises or dated commitments. If one of
these matters to you, contributions are welcome; see
[CONTRIBUTING.md](CONTRIBUTING.md).

## External displays

Crema already draws its HUDs where they belong: a reading that names a display
appears on that display and nowhere else, while volume and the keyboard backlight —
which no screen owns — appear on all of them (the now-playing player defaults
to the built-in one — see Per-display styles below). What it *controls*
today is the built-in display's brightness and the system volume. Brightness and volume
on external monitors rely on DDC, which is fiddly and fragile to drive directly.
Rather than reinvent that, the idea is to integrate with tools that already handle
it well — [BetterDisplay](https://github.com/waydabber/BetterDisplay) or
[Lunar](https://github.com/alin23/Lunar).

Brightness is in, both directions, on any display BetterDisplay manages: Crema
draws the HUD from its OSD notification — on the screen the reading belongs to,
not on all of them — and a drag on that bar is sent back to BetterDisplay so it
lands on the same scale the bar was drawn in (see Usage in the
[README](README.md#usage)). What's still open here: **volume** on external
displays (DDC audio, which Core Audio cannot see), and the equivalent integration
for [Lunar](https://github.com/alin23/Lunar).

The **brightness keys follow the pointer**: with the cursor on the laptop, F1/F2
dims the laptop and Crema draws the bar; with the cursor on the monitor, the key
goes whole to whoever drives that screen — BetterDisplay, if you have it, which
applies it and reports back, so the bar appears on the monitor you are looking at.

What is still open is Crema **applying** the change on an external display itself,
rather than handing the key over. That would give an external monitor the same step
size and the same fine step (hold Option-Shift) as the built-in panel, and a bar
even with the neighbour's own OSD reporting turned off. **The mechanism is half
there, and the missing half was measured rather than assumed.** The neighbour's
request channel writes brightness — that is what a drag on the bar already uses —
but it will not *read* it: a `get` was sent for five brightness spellings and
refused every time, with six metadata spellings answering in the same run to prove
the request itself was well formed. Stepping a key is read → step → write → verify,
so without a `before` there is nothing to step from. A relative command would need
no `before` at all, so nine relative shapes were tried against a working absolute
`set` as the control; the control answered and none of the nine did. Until one of
those comes back positive against a newer BetterDisplay, an external display is
write-only from Crema's side and the key stays handed over (docs/DECISIONS.md:
external-brightness-is-write-only; the probes are kept in `scripts/probes/`).
One trap is worth writing
down for whoever builds this, because it costs nothing to avoid and is invisible
once made: with the laptop closed the pointer is necessarily on an external display,
so a gate that takes the key only when it aims at the built-in panel turns that
entire cycle into dead code in the one arrangement it was written for — and the test
suite stays green while it does (docs/DECISIONS.md:
brightness-key-follows-the-pointer).

## Per-display styles — shipped ✓

Shipped: **Settings → General** declares a style for all displays and overrides it
per screen, including "Show now playing here" — see the [README](README.md#usage).

## The surface itself

Two directions the current surface points at, neither promised:

- **Volume beside the artwork.** Today a volume key while music plays swaps the
  whole surface to the HUD for a moment. The Dynamic Island answers the same
  moment differently — the level slots in next to the artwork and the track
  never leaves the stage. Crema's compact state could speak that grammar.
- **Live preview on hover.** The style tiles in Settings already draw each style
  on your own wallpaper; the step beyond a drawing is the real thing — resting
  the cursor on a tile briefly showing that style on the actual screen, the way
  the best pickers in this space do it.

## Automatic updates — shipped in 1.2.0 ✓

Shipped since v1.2.0: [Sparkle](https://sparkle-project.org) in release builds,
checking a signed feed on GitHub Pages (docs/RELEASE-GUIDE.md records the cycle).
What remains on this front is notarization, below.

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
