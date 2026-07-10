<!-- The bold tagline and the subtitle below it are final (author's pick). -->

# Crema

**A quiet companion for your Mac's notch. Native and out of the way.**

It shows what's playing: album art, a touch of its color, and the controls you
reach for. Volume, brightness, and keyboard backlight get their own HUDs,
optionally replacing the system's.

<!-- screenshot: hero — notch style with now playing (artwork + accent), on a real desktop -->

---

## Screenshots

<!-- screenshot: the three styles side by side — notch, card, classic -->
<!-- screenshot: now playing expanded — artwork, title/artist, scrubber, transport controls -->
<!-- screenshot: the volume, screen-brightness, and keyboard-brightness HUDs -->

## Features

- **Now playing at the notch.** Album artwork, a subtle accent color drawn from
  it, and the essentials: play/pause, previous, next, and a scrubber you can drag.
- **Its own volume and brightness HUDs.** Screen brightness, keyboard backlight,
  and volume get a HUD that matches the rest — optionally replacing the system's.
- **Three styles.** _Notch_ expands the cutout, _card_ floats a rounded panel,
  and _classic_ is a quieter take on the native bezel. Pick one per display.
- **Shows up when it's useful.** Crema surfaces briefly when the track changes,
  then tucks away. Hover to hold it open; click to reach the controls.
- **Native and light.** Built with SwiftUI and AppKit, it lives in the menu bar
  with no Dock icon, and stays out of the way when you don't need it.
- **Configurable.** A standard Settings window covers styles, HUD behavior,
  permissions, and launch at login.

## What Crema is

Crema does a few things — music, volume, brightness — and tries to do them well,
natively, without asking for your attention. It sits by the notch and waits. That
focus is deliberate: no widgets, no file shelf, no calendar, no drag-and-drop.
If those are what you're after, Crema isn't trying to be that app.

And that's fine — a few good ones already are:

- **[Boring Notch](https://github.com/TheBoredTeam/boring.notch)** — open source,
  and far more expansive: widgets, a file shelf, calendar, and heavy customization.
- **[Alcove](https://tryalcove.com)** — a polished, expressive paid app with a lot
  of character in how it animates the notch.
- **[MediaMate](https://wouter01.github.io/MediaMate/)** — a mature paid app if you
  want the essentials plus a broader feature set.

All good work. Crema just aims at a smaller target.

Curious what might come next? See the [roadmap](ROADMAP.md).

## Requirements

- macOS 14 (Sonoma) or later.
- Apple Silicon or Intel.
- A Mac with a notch for the _notch_ style. On Macs without one, the _card_ and
  _classic_ styles float near the top of the screen and work just the same.
- The **Accessibility** permission, if you want Crema to handle the volume and
  brightness keys (see [Usage](#usage)). Crema runs without it — you just keep the
  system's own HUDs.

## Installation

1. Download the latest [`Crema.dmg`](../../releases/latest/download/Crema.dmg) —
   or browse all [Releases](../../releases).
2. Open it and drag **Crema** into your Applications folder.
3. Launch Crema. It lives in the menu bar — look for its icon up top, not in the Dock.
4. When asked, grant **Accessibility** in System Settings so Crema can handle the
   volume and brightness keys. You can also do this later from Settings → Permissions.

### First launch

> [!NOTE]
> Crema isn't notarized by Apple (it's open source and distributed for free),
> so the first time you open it macOS warns that it's from an "unidentified
> developer." That's expected — nothing is wrong with the app, and you only need to
> do this once.

There are two ways to get past it:

**Terminal — recommended, always works.** Run this, then open Crema normally:

```bash
xattr -dr com.apple.quarantine /Applications/Crema.app
```

**System Settings — no Terminal, but may not work on non-admin accounts.** Try to
open Crema, dismiss the warning, then open **System Settings → Privacy &
Security**, scroll to the note about Crema, and click **Open Anyway** — confirm once
more and it opens.

The Terminal command is the more reliable of the two.

## Usage

- **Play something.** When the track changes, Crema shows it near the notch for a
  moment, then tucks away.
- **Hover** the notch to hold it open; **click** it to open the controls —
  play/pause, previous, next, and the scrubber.
- **Press a volume or brightness key** and Crema's HUD appears in the style you
  picked for that display.
- To have Crema **replace the system's HUDs** entirely, turn that on in
  **Settings → System HUD**. It's off by default, reversible at any time, and
  needs the Accessibility permission. Turn it off (or quit Crema) and the native
  HUDs come right back.
- The **menu bar icon** opens Settings (`⌘,`) or quits.

## Privacy

Crema runs entirely on your Mac. It reads now-playing information locally through
a vendored out-of-process bridge and, with your permission, watches the volume and
brightness keys. There are no accounts, no analytics, and no network calls —
nothing is collected, and nothing leaves your machine.

## Build from source

Requirements: **Xcode 16** or later (Crema's tests use Swift Testing) and the
macOS 14 SDK.

```bash
git clone https://github.com/vctorgriggi/crema.git
cd crema
open Crema.xcodeproj
```

Select the **Crema** scheme and press `⌘R`. To run the tests, press `⌘U`.

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md)
for how to file an issue and what a good pull request looks like.

## License

Crema is free software licensed under the **GNU General Public License v3.0**.
See [LICENSE](LICENSE) for details.

## Acknowledgments

Crema vendors **[mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)**
by Jonas van den Berg and contributors (BSD-3-Clause), which reads now-playing
state out of process — the only reliable way to do so on current macOS. Its
license is included at [`ThirdParty/mediaremote-adapter/LICENSE`](ThirdParty/mediaremote-adapter/LICENSE).

Crema was written from scratch, but several open-source projects in this space
were studied as references for approach and behavior — no code was copied from
them. Thanks to the people behind
[SlimHUD](https://github.com/AlexPerathoner/SlimHUD),
[Boring Notch](https://github.com/TheBoredTeam/boring.notch),
[MewNotch](https://github.com/monuk7735/mew-notch),
[Atoll](https://github.com/Ebullioscopic/Atoll), and
[volumeHUD](https://github.com/dannystewart/volumeHUD) for building in the open.

---

Made by [Victor](https://github.com/vctorgriggi), under
**[Colatte](https://colatte.io)** · [github.com/colatte](https://github.com/colatte)

If Crema is useful to you, you can support the work:

[![Support Crema on Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/colatteio)
