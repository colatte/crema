# Acceptance criteria

> The observable definition of "the app is correct". Each item describes
> behaviour a person can check on a running Crema — not an intention and not a
> plan: everything below describes the app as it ships today. Where a criterion
> names something not yet built, it says so in place.
>
> Provenance: distilled from the author's working specification, which lives in
> `docs/internal/` (gitignored, local-only). It is published here because it is
> the only list that says what "working" means, and a reader outside that folder
> had no way to check the app against it. Items 20–21 were added on 2026-08-07
> with the lock-screen surface; both are opt-in and both ship off, so a default
> install satisfies them by doing nothing. The specification stays the source; if
> the two ever disagree, this file is the one that has drifted.

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
   sized by that style. That list is offered only where there is a per-display
   answer to give: more than one screen, or a sole display that is not the
   built-in one, or a display already carrying an override; a lone built-in panel
   with no override shows no list at all, the way System Settings offers no
   Arrange with one display. Picking a style for one display moves only that
   display; picking that display's "Follow all displays (…)" item returns it to
   the declaration at once, and declaring for all displays (General's leading
   section, or the menu bar's Style submenu) replaces every per-display style. On
   a display without a notch, Notch is offered greyed out: it cannot be picked,
   and a pick that reached the store anyway writes nothing — that display keeps
   the style it had. The per-display "Show now
   playing here" toggle is honoured live, on by default for the built-in display.
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
    the Accessibility step advances on its own when the grant lands). Finishing
    it — or closing the window — and relaunching shows nothing: the tour runs
    once per install. An install that already carries the Accessibility grant
    still sees it once; the menu's "Grant Accessibility Access…" button remains
    the manual path to the standalone permission window afterwards.
20. With "Show now playing on the lock screen" on and music playing, locking the
    screen shows the card bottom-centre over the wallpaper, on the main display
    only; clicking it hands the cover the whole screen and clicking again puts it
    back; unlocking removes it. With the preference off — which is how it ships —
    the lock screen is untouched. With Reduce Motion or with Low Power Mode on,
    the blurred backdrop does not drift; it also settles on its own after a few
    minutes. On a macOS where the private space API does not resolve, Settings
    says so in a sentence instead of offering a switch that would do nothing.
21. With the cover lookup off — which is how it ships — the lock screen draws only
    the artwork the player published, and Crema makes no network request. With it
    on, a larger cover replaces it when one is found; when none is (no match, no
    network), the surface is unchanged and nothing blanks. Skipping to a track
    whose cover has not been fetched yet never shows the previous track's.
