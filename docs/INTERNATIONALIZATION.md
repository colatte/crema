# Internationalization — the catalog, the vocabulary and the ceilings

> The mechanism behind the rules CLAUDE.md states in one line each. The app
> ships in two languages from one String Catalog, and the interesting part is
> not the translation: it is what the catalog gate enforces (because Xcode
> enforces nothing), which words are reserved, and the two physical ceilings a
> string has to respect. Read this before adding a visible string.

## The catalog is the only source of visible text

- **Never a UI string literal in a view** — all visible text comes from the String Catalog (`Crema/Localizable.xcstrings`) via `String(localized:defaultValue:)` (or `LocalizedStringKey`). **Semantic** keys (`menu.quit`, `style.stub.title`), never the literal text as the key; the `defaultValue` is the source text.
- **Base language: English** (keys and source text in English in the code); `pt-BR` is an additional translation in the catalog. Languages configured in the project: `en` (source) + `pt-BR`.
- **Number/date/time formatting always via locale-aware `FormatStyle`** (`.formatted()`, `Duration…formatted(.time(…))`, `.percent`) — never manual digit interpolation (the 0.8 vs 0,8 decimal separator follows the locale on its own).
- Media data (title/artist) is never translated — it is external content; what gets localized is the UI chrome and composition formats.

## Catalog verbatim discipline, and why a script enforces it

Every `String(localized:defaultValue:)` key exists in `Localizable.xcstrings` with a `defaultValue` byte-for-byte identical to the `en` value, `extractionState` manual, a semantic (not literal) key and a translated `pt-BR` unit — no orphan keys, and with the same specifiers in both languages (a translation that drops or renames a `%@` is a broken format string served only to the Brazilian user).

**`scripts/check-catalog.py` is what enforces this, in CI** — Xcode enforces nothing: measured, with `extractionState: manual` the `xcstringstool sync` walks right past an entry whose `en` diverged from the code, intact and without a warning, and never flags an orphan.

The comparison is of SHAPE, not text: both sides normalize each hole to a sentinel, and the checker **never guesses the type** of the hole — a regex cannot type a Swift expression, and the version that guessed accused nine clean strings. `check-catalog-selftest.py` proves each rule by making the checker fail, and runs before it in CI: a checker that silently stops checking returns the same "clean" as a working one.

## The type ramp is ONE, and a second one has a price of admission

`TrackTextStack` carries the single ramp the desktop skins share. A second scale (`.glance`) existed for one session — the lock card, read from across a room — and left with that surface (docs/DECISIONS.md: the-lock-screen-was-built-and-taken-out).

The jurisprudence it earned stays: the rule used to be "one ramp, full stop", and a comment refused a second on the grounds it would be broken "for a feeling nobody measured" — the feeling was then measured. Apple's Accessibility HIG publishes **macOS default 13 pt against minimum 10 pt** and asks custom type to follow the defaults, and the family ramp puts the title two points UNDER the default and the artist exactly AT the minimum — correct at desk distance, wrong at room distance. A future second scale needs the same standard: a published number, not a preference.

## One name per concept, in each language

A style/feature uses a single term across picker, footers, menu and onboarding within each language; the picker, tab and section labels are the source of truth (Now Playing / Tocando Agora, Displays / Telas).

**The three STYLE names are product names and stay in English in both languages** — Notch, Card, Classic. Not a shortcut: `notch` has no Portuguese word and had already entered the app's own pt-BR prose as a common noun ("Esta tela não tem notch"), so translating the other two produced "o Notch aparece como Cartão", one style named in each language inside one sentence. English for all three makes the rule legible — a style name is capitalised and English, the physical cutout is lowercase — at the price of diverging from Apple, who does translate her own feature names (Tela Bloqueada, Modo Escuro). The price was already paid by `notch`. Where a style name lands inside a Portuguese possessive it takes the word `estilo` rather than standing alone ("Indicador do estilo Card").

The reserved words: the menu says **indicator/indicador** for the HUD Crema draws, **display/tela** for a display and **built-in display/tela integrada** for the built-in panel — and the suppression footer says "system indicators" so the word "built-in" never names two concepts; it stays reserved for the built-in panel.

On the General tab this decides the section labels: the global declaration opens the tab under "All displays"/"Todas as telas" (the same phrase its footer and the menu's submenu use for the scope) and the per-display list comes right below it under "Displays"/"Telas" (`settings.general.displays` — the pair that used to label the dead tab now names the section). The built-in panel is labelled with the reserved term (built-in display/tela integrada), never with the name AppKit gives it; every external monitor carries its `localizedName` **verbatim** — a display name is neither translated nor invented, it is the only name the user can match to the thing on the desk (an empty string falls back to a generic localized noun, the view's choice).

## Menu strings have a width ceiling, and the ceiling lives in the catalog

NSMenu sizes itself by the **widest** item, so a 116-character line opened the menu at ~1500 px (measured in the field). Every menu line (`menu.*`) stays at **~72 characters**; whatever exceeds that gets a `\n` in the catalog, and the code's `defaultValue` carries the same `\n` (the verbatim discipline still holds byte-for-byte).

The break falls at a **clause of the language itself** — the em-dash, the period — never at the position of the neighbouring translation's break; the `en`/`pt-BR` pair keeps the same **number** of breaks, so the two versions have the same shape on screen. `CremaMenu.sentence` is what stacks the lines (one menu item per line, left-aligned like every native item — no centering, no truncating).

## No emoji in UI strings

The glyph carries meaning the sentence has to carry anyway (and VoiceOver reads it mid-sentence), and `✓` collides with NSMenu's own vocabulary — a checkmark there means **checked item**, so a title starting with ✓ reads as a toggle switched on. An informative line in a menu-bar menu is a plain disabled sentence, as in Apple's status menus; the state is communicated by the word and, when there is a fix, by the button right below (docs/DECISIONS.md: menu-status-before-warnings).

**The rule is about strings that COMMUNICATE STATE** — menu, warnings, control labels: that is where the glyph replaces the word and collides with the system's vocabulary. The About tab's signature ("made with ☕ by Colatte") stays out because it asserts nothing about the app: it is brand, not state, and nothing in it reads as a toggle. The scope is declared because the rule is mechanically verifiable, and without that the app's only glyph is a permanent violation — a rule you live in violation of teaches you to ignore it.
