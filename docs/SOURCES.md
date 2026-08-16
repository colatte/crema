# The Sources layer — the system edge

> The mechanism behind the rules CLAUDE.md states in one line each. Every point
> of contact with the system lives in `Crema/Sources/`, and each rule below was
> paid for once — by a probe, a measurement, or a bug that shipped. Read this
> before changing anything that talks to macOS, to a private framework or to a
> neighbouring app; the rule in CLAUDE.md tells you what to do, this file tells
> you why the obvious alternative does not work.

## The shape of a source

- Every point of contact with the system sits behind a (mockable) protocol — including the integration with another app, which is just one more source: `BetterDisplayOSDSource` conforms to `SystemHUDSource` like any other.
- **Layout of `Sources/`**: the protocols and the generic composite sources (merge, sampling) live at the **root**; each subdirectory is a technology with the concrete implementations (the now-playing chain — `ChainedNowPlayingSource` — lives in `NowPlaying/`, alongside the sources it chains). The interesting edge logic is extracted pure and testable — the Reconciler/Translation/Conversion pattern (`ScreenLockReconciler`, `AdapterPayloadTranslation`, `VolumeConversion`) — and the thin edge keeps only the system contact.
- An event source exposes `updates: AsyncStream<DomainType>` + `isAvailable() async -> Bool`. Translation (the MediaRemote dict; the BetterDisplay JSON) happens **inside the source**, at the edge — never above it. The now-playing source also receives the `noteSeek`/`noteSeekFailed` hints (default no-op in an extension): the seek command travels a separate channel with no way back, so a source that extrapolates position locally re-anchors through them (docs/DECISIONS.md: scrub-grace).
- The Coordinator receives the sources **injected through the protocols**; it never references a concrete implementation. The mocks implement the same protocols and live in `CremaTests/Mocks/`.
- Failure at runtime: the stream ends (`finish`) and the consumer re-evaluates availability (rebuilds the fallback chain). **Unavailability is state, not a fatal error** — reserve `throws` for one-shot operations (e.g. firing a command), not for the event flow.
- **End of stream = unavailability, with no unrepresentable ghost**: when the media source ends, the Coordinator discards the snapshot and disarms click-invoke. A failover mid-chain (adapter → JXA) carries the same obligation — never leave a snapshot with armed controls that no living source can represent.

## OSD suppression is lock-aware

With the screen locked or the session off the console, suppression is **suspended** without touching the user's preference; on unlock, it re-engages if (and only if) the preference is on (`SuppressionLockController` over `ScreenLockSource`); the lock's `setEngaged(false)` cancels the probes and clears per-domain suspension — the re-engage is born healthy. Reason: there is no public path to draw over the lock shield — proven by hardware probes (docs/LOCKSCREEN-INVESTIGATION.md) — so suppressing there would leave the user with no feedback at all.

In the source, a notification edge **never flips the state by itself**: each edge triggers an authoritative re-read of `CGSessionCopyCurrentDictionary` — and, because the notification can arrive before the dict reflects the change (the edge reads a stale session, the reconciler deduplicates, and the state would wedge), there are **settle re-reads** until a settled reading emits the missed transition. The **periodic tail** runs **from construction** — real parity with the tap's health-check, which verifies from `init` — and each edge merely puts a **short backoff** in front of it for the common sub-second skew. Arming the tail at launch (not only on the first edge) closes the `[launch, first edge)` window: if the session's first lock notification is dropped (`DistributedNotificationCenter` is best-effort, with no redundancy for a plain lock), the tail still catches the flip instead of wedging at `safe` over the lock shield with no edge left to correct it (docs/DECISIONS.md: settle-rereads — the lesson is that finite backoff closes the skew only probabilistically; the tail from init makes it deterministic).

## An apply failure suspends per domain, never globally

A failing apply suspends only the channel that failed (volume / screen brightness / keyboard brightness; mute rides with volume) — its keys go back to the system (native feedback) while the other domains stay suppressed; a read-only probe with backoff (1→16 s, then 30 s) re-engages silently on recovery, and only a lasting suspension with the channel present shows up in the menu (probes with no device — an AirPods swap — and key-kicked probes never escalate). The consumption decision is synchronous, per key, and consistent between key-down and key-up (`SuppressionDecider`). **No failure path writes a preference.**

Escalation has a **write-health axis of its own** (`unconfirmedApplyFailures` per domain), **orthogonal** to probe suspension: the probe re-engages the domain optimistically (clearing the suspension), but the write-health counter **survives** that re-engage and only resets in three situations — a **verified apply** (`confirmWriteHealthy`, the passive cleaner), a **`setEngaged` flip** (lock/toggle, which is born healthy) or the **user's explicit retry** (the only path that clears without a verified apply). That is why a domain that writes and fails in a loop — alive enough to pass the read-only probe, but with the write dead — still escalates to lasting suspension instead of flapping through re-engages forever (docs/DECISIONS.md: write-health-axis — the lesson is that an axis that reset on the probe's re-engage would mask the real write failure).

## The brightness key acts on the display under the pointer

The rule is pure (`BrightnessKeyTargeting`, over the cursor and the bounds), the app reads and writes the built-in panel and no other, so only `.builtIn` is swallowed — any other answer hands the whole key back to whoever can move that screen (a display utility behind us in the chain, or macOS), each with its own feedback. A consumed key owes feedback, and consuming to change a screen the user is not looking at pays that debt in the wrong currency.

Five properties, each one a case that cost a decision:

1. **No fallback to the built-in** — that fallback *is* the bug, and it is what spares clamshell a branch of its own.
2. **A single display answers for itself**, pointer or no pointer — a failed read must not turn off the keys on the Mac that has exactly one panel.
3. **One coordinate space only** — `CGEvent(source:)?.location` and `CGDisplayBounds` are both CoreGraphics' global space, so there is no flip whose sign could be gotten wrong, and the bounds are half-open on both axes, the way CoreGraphics tiles.
4. **The ACTIVE list, never the panel roster** — the roster drops a display without an `NSScreenNumber` and collapses a mirror into a single `NSScreen`; targeting through one list while the menu speaks through the other is how a true sentence ends up describing the opposite behaviour. Read fresh on every keypress, because a snapshot would cost a lock, an invalidation edge and a window in which the key targets a display that has already left.
5. **Mirroring gives the tiebreak to the built-in**, otherwise list order decides.

The verdict is latched for the whole press in BOTH directions (`SuppressionDecider`): a pointer crossing screens under a held key must not turn a passed-through keypress into a swallowed one, which would leave downs without an up in the system. The handed-back key **makes the local bar stand down** (`onHandedBackToTheSystem` → `standDown()`, the same seam the absent capability also uses), otherwise the tap keeps observing, the poll reads the panel macOS just moved, and the app draws a second bar over the native indicator (docs/DECISIONS.md: brightness-key-follows-the-pointer).

## Real state behind an IPC boundary cannot be audited by a local health-check

The media-key event tap can go `enabled`-but-deaf when the WindowServer reroutes delivery (display sleep/wake, hotplug), and the local `isValid`/`isEnabled` keep lying "alive" — the health-check poll cannot reach this class. The defence is to reinstall the tap preventively on **every physical edge** that may have reconfigured delivery: the **4 triggers** are `screensDidWake`, `didWake`, the unlock edge (`onUnlocked`) and the display-topology change (`didChangeScreenParameters` — the 4th; a hotplug without sleep fires neither wake nor lock).

`reinstallTap()` is convergent, idempotent and permission-gated (create-after-uninstall, no orphan port), so calling it too often never hurts — and **every port mutation** (install/uninstall/setEnabled) runs on the tap's own thread: edge delivery arrives on `.main`, and the health-check poll **detects off the main thread and hops to it only when there is something to change** (`AXIsProcessTrusted` and `tapCreate` are blocking IPC — a healthy tick costs the main thread nothing), so no mutation races a delivered event nor holds, across the round-trip, the lock the callback also takes (docs/DECISIONS.md: tap-mutation-on-its-own-thread, preventive-reinstall and J7-estado-do-outro-lado — the lesson is that truth living beyond XPC/WindowServer is covered by unconditional action on the edge, not by a local read).

## A key that goes missing may be position in the chain, not a sick tap

Session taps are chained and whoever **inserts last receives first** (`.headInsertEventTap`), so a brightness app that comes up at login alongside Crema can end up ahead and eat its keys — with the tap alive and delivering the others (volume gets through, brightness does not). Before suspecting your own port, ask who is ahead of it: `CGGetEventTapList` is the only view of the chain from **outside** the process, read only when the menu opens (each read zeroes the min/max latencies of every tap in the system — never in a poll).

Crema **does not contest the position** — re-inserting in a loop is an arm-wrestle decided by whoever moved last, and going to `kCGHIDEventTap` always wins but steals the keys from every third party that legitimately wants them; it **names** who is ahead and errs toward silence (a listen-only tap, a disabled tap, one with a disjoint mask, a chain without our tap, and a nameless competitor produce no warning — a missing line costs a diagnostic, a false line accuses the neighbour). See docs/DECISIONS.md: media-key-chain-contention.

## Neighbour-app integration, and the four rules that took probing to discover

`Sources/External/`, docs/DECISIONS.md: betterdisplay-osd-source.

1. **Exact name, never a wildcard** — macOS does not deliver `DistributedNotificationCenter` observation with a `nil` name, so a wildcard listener is deaf by construction.
2. **One prefix only** — BetterDisplay publishes the same event under the current name and the legacy one, and subscribing to both doubles everything.
3. **The payload may not be in `userInfo`** — theirs comes as a JSON string in the `object`.
4. **The scale is the neighbour's** — `value`/`maxValue` (measured: 0–64), so only the ratio is portable.

And three scoping rules, all with the same why — **with the neighbour's OSD off, Crema's bar is the user's only feedback**:

- Only emit a target the app can **name** — a displayID that does not resolve to a UUID is discarded, because a bar for a nameless screen has nowhere to appear and nowhere to send the drag back to (`BetterDisplayOSDTranslation`). The earlier gate, "only what can be actuated", died when the neighbour's channel started writing to externals — today `externalDisplayUnsupported` exists only in the system actuators.
- **Discard instead of guessing** — a payload without `maxValue` gets no invented scale; a payload with `lock` does not become a normal bar.
- When the neighbour reports, **the local key source stands down** (`standDown()` spends the origin gate's window **and marks as already-spoken the reads the key requested that are still in flight** — the read executes off the requester's thread, so ordering alone no longer protects the keypress) — otherwise, with suppression off, a merely *observed* key arms the local poll and the two sources draw for the same keypress, with the wrong read arriving last.

**Integration feedback is by evidence, never by presence**: the neighbour's app running does not prove its integration is on — only a delivered payload proves it, and the claim dies when the app terminates. The menu confirms when it is receiving and, when the neighbour is right there and mute, says **what to do**. The claim is **observable, with a guarded write**: it flips while the Settings window is open (it is read from an already-built body), and a `false` over `false` — the neighbour quitting with the integration off, the common case — invalidates no view. Neighbour-app identity is compared by **bundle ID**, never by localized name.

## A HUD that names a display appears only on it

The app has a single state and one panel per screen, so every panel used to draw every HUD — harmless while nothing named a display, wrong the instant something did (the external monitor's bar drawn on the notebook is control over a screen the user is not looking at, and the drag would darken the neighbouring screen in silence). The decision lives in `WindowManager.effectiveState`, which is already the per-display policy seam; a panel that is not the owner treats the state as `.hidden`, which also disarms hover there.

The HUD **does not name a UUID, it names a role** (`SystemHUD.Target`: `.noDisplay` / `.builtIn` / `.display(uuid)`) and whoever holds the panel roster resolves it: the producer says only what it knows (`BrightnessBackend.target` is a constant of the technology — the screen bridge governs the built-in panel and no other; the backlight belongs to no screen), and the `WindowManager` asks its own roster which panel is the internal one (`isInternal`), never matching a UUID from the ACTIVE display list against the roster — the two lists disagree by design, and every disagreement would become "bar on no screen at all".

The **volume** and **keyboard brightness** HUDs (`.noDisplay`) stay on every screen on purpose: no screen owns them, and scoping them would move feedback nobody asked to move. The `.builtIn` role **fails open**: with no internal panel in the roster (mirroring collapsed, screen dropped), the bar goes back to appearing on all screens — a consumed key always produces feedback — while a NAMED display that vanished still appears nowhere. Actuation reads `commandDisplay`, where `.builtIn` and `.noDisplay` become `nil` (docs/DECISIONS.md: hud-target-is-a-role, hud-belongs-to-its-display).

## The bar and the write speak the same scale

The `SystemHUD` carries the **authority** that produced it, and the drag goes back to that authority — drawing the neighbour's *combined* level while writing hardware brightness would move the screen somewhere else (measured: 0.625 × 0.504 on the same screen). Five consequences that hold for any actuator living in another process:

1. **Publish the level before writing** — the slider has no local value, so without an immediate echo the bar freezes under the finger while the round-trip runs.
2. **Coalesce latest-wins**, one write in flight — a drag fires per frame, and a round-trip per frame is a flood that resolves out of order.
3. **Failure degrades, it does not die** — fall back to the system actuator within the same drag, stop asking until the neighbour reports again (evidence, never a timer), and never retry mid-gesture.
4. **A drag no actuator honoured rolls back** — publishing before writing promises that every shown level will be honoured; when neither the neighbour nor the fallback writes, the bar returns to the last level with evidence (a read that arrived on its own, or a confirmed write) at the END of the gesture, which the view reports — "the hand let go" cannot be deduced from the numbers, and a quiescence guess would make the fill jump under a finger that merely paused.
5. **A queued level carries the display it belongs to** — coalescing outlives the call that resolved the target (a write drains the frames that arrived after it), so a bare number in the queue leaves with the id of whoever was driving: the neighbour darkens a screen nobody is dragging, in silence, because the bar that asked is on another panel. For the same reason each call echoes only what reached the wire **for the display IT named** — the drain's last frame may belong to another bar, and echoing it would publish on this one a level that nothing wrote to it (docs/DECISIONS.md: the-bar-never-outruns-the-screen).
