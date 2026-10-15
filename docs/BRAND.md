# Brand

> How Crema looks, sounds and writes its own name — the rules the product
> already follows, written down so the next change follows them too. Crema has
> no brand manual of its own and does not need one: it is a **house product of
> Colatte** under endorsed brand architecture (the product carries its own
> mark, the house signs discreetly), and almost everything visual here is
> borrowed from the house. This page is what is Crema's, and where the rest
> comes from.
>
> Sources, from most to least normative: this file for the rules; the vector
> mark in `design/icon/` and the tokens in `docs/index.html` for the values;
> the Colatte brand (`Workspaces/colatte/brand/`, chapter 09 and
> `design/creditos/`) for everything inherited. Where the two disagree about
> Crema, this page wins; where this page is silent, the house rule applies.

## What Crema is, in the words the product uses

A quiet companion for your Mac's notch. Native and out of the way. It shows
what's playing — album art, a touch of its colour, the controls you reach for —
and gives volume, brightness and keyboard backlight their own HUDs, optionally
replacing the system's. Free, open source (GPL-3.0), macOS 14+.

The tagline and subtitle are final (author's pick; the README says so at its
top). They are the product's voice: sober, warm, one idea per sentence, no
superlatives. "Quiet" is the load-bearing word — it is why the app has no brand
inside it (below).

## The name

| Context                                 | Form                                                         |
| --------------------------------------- | ------------------------------------------------------------ |
| Running text, UI, documents, e-mail     | **Crema** — capital C, no full stop                          |
| Logotype                                | **none** — the mark is the icon (next section)               |
| Identifiers                             | `crema` — bundle `com.colatte.crema`, `colatte/crema`, `colatte.github.io/crema` |
| Page title                              | `Crema — a quiet companion for your Mac's notch` (em dash)   |
| Article in pt-BR                        | **o** Crema — "o Crema mostra", "instalar o Crema"           |
| The three styles                        | **Notch · Card · Classic** — product names, English in both languages (docs/INTERNATIONALIZATION.md) |

Two things follow from the table. First, **"crema." — lowercase with a final
dot — is not Crema's logotype.** That device belongs to `colatte.` and to
`brio.`; the family shares short warm names, not the dotted wordmark, and Crema
never had one. Do not compose "crema." in a font and call it a logo, and do not
add a dot to the name in prose by analogy with the house. Second, the name is
a real word in Italian and Spanish (the foam on an espresso; cream), so it is
unsearchable on its own — every public surface pairs it with what it is
("Crema — a quiet companion…", "Crema app icon"). That is a known cost of the
name, accepted for a free utility, and not something copy should try to fix by
shouting.

## The mark is the icon

The icon is the whole visual identity: a soft, uneven disc of crema seen from
above, opened by one gesture — a dark hollow that enters from the upper right,
rounds out at the centre and leaves along a wave, with the crema above it drawn
out into a single fine point — on an espresso ground. One shape in two flat
colours: the house's language, with no exception for the artwork. The glass the
icon sits in is the system's material, not part of the drawing. It is
generated, never hand-edited:

- `design/icon/crema-mark.svg` is the mark's single source, one filled path.
  `makeicon.swift` writes the Icon Composer document `Crema/AppIcon.icon` from
  it (the ground, the mark at 56% of the width, and the Liquid Glass material),
  the only form of the icon the build ships. An Icon Composer file replaces any
  icon asset catalog, and Xcode generates from it the images for releases older
  than the material (Apple docs, Xcode, "Creating your app icon using Icon
  Composer"); the About tab shows the running app's `NSApp.applicationIconImage`. The
  document is never edited in Icon Composer, which only previews it: the next
  run overwrites an edit made there. The same run renders the web export,
  `docs/assets/icon.png`, through Icon Composer's own `ictool`, on the icon
  grid's margin; it is what the README shows, and `scripts/make-web-assets.sh`
  derives the landing's `icon.webp` and `favicon.png` from it.
- `makemenubaricon.swift` fills the same path black on transparent as the
  **menu bar template**, rendered by the system as a template so it follows the
  menu bar's own ink in light and dark.
- The colours are the landing's tokens: ground `--raise` `#1b1610`, mark
  `--cream` `#d6bd94`. The artwork carries no gradient, gloss or baked shadow.
  The depth is the material's (the glass, its specular, the ground's automatic
  gradient, the shadow), set in `makeicon.swift` and drawn by the system.

What the drawing must keep:

- **The crema ends in one fine point**, above the hollow; the hollow itself is
  rounded. One size is exempt: at 16 pt @1x the hollow reads as a notch, since
  the document takes one artwork for every size and the system scales it down.
- **The disc stays full around the hollow.** Thinned toward an outline, two
  pointed ends on a heavy side read as a crescent moon.

## Colour

The landing page's palette **is Colatte's espresso dialect**, value for value
(`Workspaces/colatte/design/social-web/colatte-pecas.css`, the `--esp-*` set;
`brand/09-digital.md`). Declared once, in `docs/index.html`:

| Token          | Value                      | Colatte name    | Role                                               |
| -------------- | -------------------------- | --------------- | -------------------------------------------------- |
| `--base`       | `#0d0b09`                  | `--esp-base`    | Page ground                                        |
| `--well`       | `#14100c`                  | (near `--esp-panel`) | Recessed surface                              |
| `--raise`      | `#1b1610`                  | —               | Raised surface, code chips                          |
| `--notch-ink`  | `#060402`                  | —               | The bezel black: darker than any page surface, the one thing pretending to be hardware |
| `--cream`      | `#d6bd94`                  | `--esp-cream`   | **The one accent**: eyebrow, emphasis, primary button, meter fill, every hover |
| `--cream-hi`   | `#eedcbb`                  | `--esp-cream-hi`| Only as the accent's hover                          |
| `--ink`        | `#efe8dd`                  | `--esp-ink`     | Text; never pure white                              |
| `--ink-2/-3`   | ink at .72 / .55           | —               | Two lower steps; the faintest still clears 4.5:1 on the ground (measured — .38 reads as decoration shaped like text) |
| `--line/-hi`   | cream at .12 / .28         | —               | Hairlines                                           |

**One cream.** A second accent is what turns a palette into a mood board — the
comment in the stylesheet says it and the page holds to it. There is no error
colour, no success green, no state tint: a static landing page has nothing to
report. And **one filled cream button per viewport**, the house's rule for the
accent: the hero owns it on arrival, and the notch's own "Get Crema" stays
folded until the hero's button has scrolled away. The notch itself carries
little — the mark, three section links, that one button — because a notch is a
small thing and the metaphor only reads while the shape stays narrow.

**The app has no palette of its own.** It draws with the system's materials
and accent (the blue in Settings is macOS's, not ours), and the only colour
that is Crema's inside the app is the one it borrows from the album art now
playing — a touch of it, never a wash. The two gradients in Settings are
stand-ins, not brand colours: `TileBackdrop.swift`'s is the fallback desk under
the drawn previews when the real desktop cannot be read, and
`StyleThumbnail.swift`'s is the fake album cover in them.

## Typography

| Surface | Display                                  | Text                        | Labels                                  |
| ------- | ---------------------------------------- | --------------------------- | --------------------------------------- |
| Landing | **Raleway 700**, tracking −.035em (h1) / −.022em (h3) | Raleway 400, 16px/1.7 | **JetBrains Mono** 11px, +.2 to +.28em, uppercase |
| README  | GitHub's                                 | GitHub's                    | —                                       |
| App     | **none** — SF Pro at the system's sizes  | SF Pro                      | SF Pro                                  |

Raleway and JetBrains Mono are the house's text and mono families. The house's
display face, **Sklow, is not here and cannot be**: it is a commercial licence
held by Colatte, and this repository is public — shipping the file would
redistribute it. Raleway at 700 with tight tracking stands in for display, and
the result is that the landing reads as the house's site with a lighter voice,
which is what a house product's page should do. The two fonts load from Google
Fonts — the landing is one self-contained HTML, self-hosted except for them,
as docs/README.md records.

The eyebrow is the house's mono kicker — small caps, wide tracking, one accent
colour — **without the house's parentheses**. `( assim )` is the signature of
colatte.io itself; Crema's eyebrows are plain ("three styles", "install"), so
the page quotes the dialect without wearing the house's own mark.

Inside the app there is no display type at all, and no custom font: a HUD that
appears for a second and a Settings window that mirrors System Settings both
belong to the platform's type, not to a brand.

## Writing

- **Sentence case** everywhere — headings, buttons, menu items, the catalog.
  All-caps exists only in the mono eyebrows, by CSS transform, never typed.
- **h1 and h2 on the landing end with a full stop** (or a question mark: "Ready
  for a quieter Mac?"). This is the house's "period even in titles". **h3 are
  labels and carry no period** ("Blends into the cutout", "Grant
  Accessibility") — the line between a sentence and a label is the line
  between a period and none, and it is kept on purpose.
- **No exclamation marks. No emoji, anywhere in UI** — `check-catalog.py`
  refuses a value carrying one (rule 7), and the About signature is prose:
  "made with coffee by Colatte" / "feito com café por Colatte"
  (INTERNATIONALIZATION.md). Coffee is a word here, as it is on the house's
  site.
- **Emphasis is a bold word or the accent colour, once per sentence** — never
  a shouted word, never a second colour.
- **English is the base language; pt-BR is a translation** with the same
  shape (same breaks, same specifiers, same names for the same concepts —
  docs/INTERNATIONALIZATION.md). Media titles and artists are content and
  are never translated.
- **The voice is the house's: sober with warmth, short sentences, zero
  marketing jargon.** "Honest" appears in the copy more than "powerful" ever
  will ("one honest warning", "honest with your keys"). A claim about the
  product is checkable on a running Crema or it is not made; a claim about
  somebody else's API carries its source (AGENTS.md).

## The house endorsement and the invisible credits

Crema is signed the way every Colatte product is, and only there:

- **Landing footer, last line, right:** "Crema by `colatte.`" — the phrase is
  host text, `colatte.` is the official lettering as an inline SVG tinted by
  `currentColor`, per the Colatte credits kit. The kit's resting opacity is
  deliberately not applied on top of `--ink-3` (the two would compose to .33,
  under the measured floor); the CSS comment beside the rule explains it.
- **Invisible:** the HTML comment banner `<!-- Crema by colatte. — colatte.io -->`,
  `<meta name="author" content="Colatte — colatte.io">`, and one console line,
  "Crema by colatte. colatte.io", printed once.
- **In the app:** the About tab's "made with coffee by Colatte" — prose, no
  lettering, because the wordmark as an image would need a generated asset
  the icon pipeline does not produce, and a plaque in System Settings is not
  a brand surface.
- **README:** "Made by Victor, under **Colatte**" — prose with a link, never
  the lettering typed in Markdown.

In every one of these the house name is either the SVG lettering or the word
"Colatte" — never "colatte." typed in a text font. That is the house's golden
rule 2 and the one rule of theirs Crema can break by accident.

## What Crema deliberately does not have

- **A wordmark.** The icon is the mark; the name is a word.
- **A display typeface of its own**, or the house's (licence, above).
- **Brand inside the app.** Icon, signature line, album-art accent — nothing
  else. A quiet companion does not wear a uniform.
- **A palette beyond the landing's.** New surfaces (a release note, a badge, a
  screenshot frame) take the landing's tokens, not new ones.
- **Social pieces of its own.** The campaign pieces live in the Colatte
  archive (`Workspaces/colatte/design/campanhas/crema/`) and are not a
  template for anything here.

## State in the product

Everything above is applied. Two things to keep true:

- `docs/assets/settings-about.png` is a reference capture of the Settings
  window (unlinked; listed in docs/README.md). It predates the current icon
  and the About signature becoming prose, and still shows the earlier icon and
  a glyph — recapture it after the next release build, or leave it knowing it
  is stale.
- The icon and the menu bar template are regenerated from `design/icon/`, and
  the download badge from `design/badge/`; none is edited in place. A change
  to the mark or the material is a change to `crema-mark.svg` or
  `makeicon.swift` and a rerun, in order: `makeicon` (the document and
  `docs/assets/icon.png`), `makemenubaricon`, then
  `scripts/make-web-assets.sh`.
