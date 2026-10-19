# Acceptance criteria

> The observable definition of "the app is correct". Each item describes
> behaviour a person can check on a running Crema — not an intention and not a
> plan: everything below describes the app as it ships today. Where a criterion
> names something not yet built, it says so in place.
>
> This file is the **only home** of the criteria: [SPEC.md](../SPEC.md) points
> here instead of restating them. The SPEC says what the app is and why; this
> list says how you check it.

1. With media playing (browser media only with the toggle on — it is filtered by
   default), now playing appears near the notch (or in the floating card, on a
   screen without one); hover expands the surface; play/pause and scrubbing work
   from it.
2. Pressing the volume, screen-brightness or keyboard-brightness keys shows the
   app's own HUD in the display's configured style; with the opt-in suppression
   active, the native HUD does not appear.
3. Turning suppression off restores the native HUD (verifiable reversibility).
4. Each display renders the HUD and now playing in its resolved style — its own
   override from the Displays list in General when it has one, else the style
   declared just above it; notch→card where there is no slit — positioned and
   sized by that style. That list is offered for every connected display, a lone
   built-in panel included: its row carries the only switch for the now-playing
   surface, so a MacBook on its own still shows the Each display section with its one
   row. Picking a style for one display moves only that
   display; picking that display's "Same as the others" item returns it to
   the declaration at once, and declaring for all displays (General's Style
   section, or the menu bar's "Style for All Displays" submenu) replaces every per-display style. On
   a display without a notch, Notch is offered greyed out: it cannot be picked,
   and a pick that reached the store anyway writes nothing — that display keeps
   the style it had. The per-display "Show now
   playing here" toggle is honoured live, on by default for the built-in display.
   Each display's row shows what that display draws, in a thumbnail and a
   caption: a notchless monitor under a Notch declaration reads "Using Card, since
   this display has no notch", and the Card indicator below the list names it among the
   displays drawing Card.
5. Now playing works through mediaremote-adapter on every supported version; if
   it is unavailable, the JXA fallback takes over; if neither is available, the
   availability check disables the feature without crashing. A recovered adapter
   is **re-adopted on its own** at a quiet boundary (a pause or a track change —
   never in the middle of a playing track); when the active source dies, the
   surface is discarded — the controls never point at a dead source.
6. The app runs as an accessory (LSUIElement) on Apple Silicon and Intel, on
   machines with and without a notch.
7. No Apple type (nor any private-API type) leaks above the Domain layer; every
   system integration is replaceable behind its protocol.
8. Without the Accessibility permission the app keeps running without crashing —
   without key capture and therefore without the brightness HUDs (key origin is
   the gate; volume still works) — and signals that state in the menu bar;
   granting the permission unlocks capture.
9. With the "reactive now playing" toggle **ON** (the default), a track change
   that arrives **playing** — a change that lands paused does not surface, and a
   paused app coming back is not news — or a play/pause originated outside the
   surface triggers a compact appearance of ~3 s; hovering during the appearance
   holds it (cancels the timer) and leaving hover resumes the tuck. With the
   toggle **OFF** (quiet mode) the surface never appears on its own: with media
   playing, click-to-invoke (the slit, on the notch) opens it **expanded** under
   the invoked linger (~5 s); closing is spatial — the pointer leaves, it
   collapses to compact and the linger guards it. Paused media is not invocable
   in either mode.
10. With suppression active and the screen locked, the volume/brightness keys
    produce the **native** OSD (suppression suspended); on unlock, suppression
    re-engages on its own if the preference is on — and the persisted preference
    never changes because of the lock.
11. In a Debug build there is no updater (menu item absent;
    `UpdaterModel.isSupported == false`); in Release, Sparkle compiles with
    `SUFeedURL` and `SUPublicEDKey` present in the Info.plist and **without**
    pre-set consent defaults (`SUEnableAutomaticChecks` /
    `SUAutomaticallyUpdate` absent).
12. With suppression active, an apply failure on one channel (say, the output
    device changing during a volume key) suspends **only that domain** — the
    others stay suppressed — re-engages on its own when the channel comes back,
    and does not change the persisted preference; a suspension that lasts appears
    in the menu bar with an action to re-enable it.
13. Level indicator: a clean, thumbless bar at rest in all three styles (a
    capsule on notch/card, 16 segments on classic); with the cursor over the
    HUD's surface the knob appears and **travels the inset track with the value**
    (thumb mapping — it responds across the whole scale, with **no dead zone at
    0% or 100%**; the fill's boundary always sits under the knob's body) — on the
    capsule only: classic, and card in Filled, have no knob, like the references
    they reproduce; the HUD does not dismiss until the cursor leaves (the revert
    re-arms on exit); the card and classic surfaces render identically whether
    the system is in light or dark mode.
14. Hover follows what the eye sees, on all three skins: the exit region tracks
    the rendered state/surface (a band beyond the visible limited to the named
    margins — never another state's silhouette); a cursor resting outside the
    visible surface never holds it, nor a HUD; leaving while dragging releases on
    mouse-up (a live drag never drops the hold); any finished hover re-arms the
    reactive linger at 1.5 s (calibration-in-test) and the invoked appearance
    keeps its full tail.
15. A brightness key with the pointer on an external display is **handed back
    whole** to the system (down, autorepeats and up), the local bar stands down,
    and whoever moves that screen gives its own feedback; with the pointer on the
    built-in panel, the key is Crema's. On a Mac with a single display, the key is
    Crema's with or without a pointer reading.
16. With BetterDisplay reporting OSD, a brightness key on a monitor it manages
    draws Crema's bar **on that monitor only**; dragging it moves that monitor and
    not the notebook. Without BetterDisplay (or with its OSD integration off),
    nothing arrives and the rest of the app operates identically.
17. A drag no actuator honoured returns the bar to the last level with evidence
    behind it, at the end of the gesture — never under the finger, never after
    the HUD is already gone. An honoured drag stays exactly where it was released.
18. With version N installed and N+1 published in the appcast, the app offers the
    update and applies it.
19. The first launch of a clean install opens the welcome tour (five steps;
    the player shows on the real screen, a sample when nothing plays, and a
    Mac with no built-in display is offered the switch that turns it on; the
    Accessibility step flips to Continue live when the grant lands, comes back
    to the front, and never advances on its own; a volume key on the key test
    raises Crema's HUD; the last step points an arrow at the menu bar icon).
    Finishing it — or closing the window — and relaunching shows nothing: the
    tour runs once per install, and the menu's Welcome Tour item reopens it
    from the first step. Closing it mid-step leaves no sample player and no
    arrow on screen. An install that already carries the Accessibility grant
    still sees it once; the menu's "Grant Accessibility Access…" button remains
    the manual path to the standalone permission window afterwards.
20. ~~The lock-screen card.~~ **Retired** (docs/DECISIONS.md:
    the-lock-screen-was-built-and-taken-out). The app draws nothing over the
    lock shield; with music playing and the screen locked, macOS looks exactly
    as it does without Crema installed. That is the only thing left to check
    here, and it is checked by there being nothing to see.
21. ~~The cover lookup.~~ **Retired.** Crema makes no artwork request of any
    kind.
22. On a display drawing Card, the indicator's position is picked in General
    from the Position pop-up — each place named beside a picture of it, the
    three rows split by dividers — and applies at once to every display drawing
    Card. Choosing a place shows the real volume HUD there once, at the current
    level and without changing it, on every display drawing Card and on no
    other, and it leaves on its own timer. At the top centre (the default) nothing changes: the HUD is the
    card itself, morphed. Anywhere else the HUD appears there, upright in the
    middle of a side and filling from the bottom, while the card stays at the top
    centre, readable and controllable; the cursor on the HUD holds the HUD, on the
    card it expands the card and leaves the HUD to its own timer; the card tucks
    after the HUD has gone, never under it. Notch and Classic draw their HUD where
    they always do, whatever the position.
23. A Card HUD placed along the bottom or on a side never sits under a shown
    Dock: with the Dock visible at the bottom it rests just above it, with the
    Dock on a side the places on that side clear it, and with the Dock hidden a
    bottom HUD rests near the bottom edge. Changing the Dock (hide, move, resize)
    moves the HUD on its next appearance without the card blinking.
24. With headphones, AirPods, AirPods Pro, AirPods Max, Beats headphones, an
    AirPlay speaker or a display's speakers as the output, the volume HUD shows
    that device's glyph in place of the speaker; the Mac's own speakers and any
    device it cannot name keep the speaker, and mute shows the slashed speaker on
    any device. Switching outputs shows nothing by itself.
25. Over a white page, Card and Classic stay dark and their glyph and level read
    clearly, and the filled Card HUD's light end has a clean edge: no grey line
    round it (docs/DECISIONS.md: surface-border-2026).
26. With BetterDisplay running and "Replace the system indicators" on, a
    brightness key BetterDisplay handles shows Crema's indicator and not
    BetterDisplay's, with nothing changed by hand in BetterDisplay. Quitting
    Crema, or turning the switch off, brings BetterDisplay's indicator back at the
    next press, and BetterDisplay's Settings show its switches as they were
    before Crema ran. The same holds after Crema is force quit and opened again.
