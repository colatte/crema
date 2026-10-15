# System-contact inventory

> Every place Crema touches a resource that can die underneath it: what it
> touches, where in the code, and what happens when the resource goes away. It is
> the map to hold before changing anything on the fragile border. Each row names
> its site, and the site is the authority: re-read it before leaning on a row.
> Contract ids (`S…`, `MG…`, `W…`, `P…`) resolve in
> [CONTRACTS.md](https://github.com/colatte/crema/blob/main/docs/CONTRACTS.md);
> the debts a row names live in
> [KNOWN-GAPS.md](https://github.com/colatte/crema/blob/main/docs/KNOWN-GAPS.md).

## Private frameworks and the vendored bridge

| Contact | Where | When it fails |
|---|---|---|
| DisplayServices, opened with `dlopen`, symbols resolved with `dlsym` | `DisplayServicesBridge` | A nil symbol means the channel is unavailable, never a crash. The display ID is resolved per operation (docs/DECISIONS.md: J2-display-id-stale). |
| CoreBrightness's `KeyboardBrightnessClient`, opened with `dlopen` | `CoreBrightnessKeyboardBridge` | The keyboard ID is enumerated per operation (`copyKeyboardBacklightIDs` + `isKeyboardBuiltIn:`). The client instance is resolved once and no edge rebuilds it: a dead client reads nil, writes false, and the channel reports itself absent until relaunch (KNOWN-GAPS: the keyboard-backlight client). |
| The mediaremote-adapter's streaming Perl process | `MediaRemoteAdapterProcess`, `MediaRemoteAdapterNowPlayingSource` | EOF finishes the stream; `ChainedNowPlayingSource` re-selects and starts a new process. The child outlives a killed parent (KNOWN-GAPS: a process finishing is not its children finishing). |
| The adapter's one-shot probe and command channel | `MediaRemoteAdapterProbe`, `MediaRemoteAdapterCommandChannel` | Every one-shot child runs under `runChildProcess` (`ChildProcessDeadline`): on expiry it is terminated, escalated to SIGKILL and abandoned, never awaited. A failed command throws. |

## Now playing without the adapter

| Contact | Where | When it fails |
|---|---|---|
| `osascript` running JXA, for the read, the probe and the commands | `JXANowPlayingSource`, `JXACommandChannel` | The same `runChildProcess` deadline, 5 s on the interactive commands, so the Apple Event's own minutes-long ceiling is never the only bound. |
| Apple Events consent per player | `AppleEventsAutomationPermission` | A state read never prompts; only the user's click requests. A closed player reads as "not running", not as a refusal. |
| The chain's promotion back to the adapter | `ChainedNowPlayingSource` | While a lower-priority source runs, a probe polls the preferred one and arms a cutover at a quiet boundary (docs/DECISIONS.md: promotion-quiet-boundary). Every source death drops the snapshot (docs/DECISIONS.md: ghost-discard; S6). |

## Audio

| Contact | Where | When it fails |
|---|---|---|
| Default output device, volume and mute, read and written per operation | `CoreAudioSystemOutput`, `CoreAudioVolumeController` | The device is resolved inside the same off-pool hop as the write, so a write never addresses a device replaced in between. |
| Volume and mute listeners, re-subscribed on a device switch | `CoreAudioVolumeSource` | A `kAudioHardwarePropertyServiceRestarted` listener re-adds itself before the device listeners, so a coreaudiod restart re-registers everything in silence; a failed registration is logged. |
| The output route: transport type and the built-in device's data source | `OutputRouteClassifier` | A device it cannot name draws the speaker (docs/DECISIONS.md: the-output-glyph-names-only-what-it-knows). |

## Keys and the event tap

| Contact | Where | When it fails |
|---|---|---|
| The media-key event tap (`CFMachPort` + run-loop source) and its consumer | `CGEventTapMediaKeySource` | An invalidated port is reinstalled from scratch; a valid but disabled one is re-enabled with its consumer kept. Reached from the health poll and from the four preventive-reinstall edges, every mutation on the tap's own thread (docs/DECISIONS.md: preventive-reinstall). |
| Wake and topology edges: `screensDidWake`, `didWake`, `didChangeScreenParameters` | `AppCore.wireWakeReinstall`, `AppCore.wireScreenParameterReinstall` | Each edge reinstalls the tap, which can go deaf while `isValid`/`isEnabled` answer healthy. |
| The session's tap chain, `CGGetEventTapList` | `EventTapRegistry`, `MediaKeyChainReconciler` | Read only when the menu opens, since each read zeroes every tap's latency counters; Crema names who is ahead and never contests the position. |
| The pointer and the active display list, for the brightness key | `BrightnessKeyTargetReading` | Read fresh on every press; an answer that is not the built-in panel hands the whole key back. |
| Accessibility trust (`AXIsProcessTrusted`) | `AXAccessibilityPermission`, `AccessibilityPermissionMonitor` | Re-read on every use and polled every 2 s; without it only key capture falls, and a grant resumes it. |
| The native OSD's channels, written under suppression | `MediaKeyInterceptionOSDSuppressor`, `SystemOSDChannels` | A failed or hung apply suspends only its domain and hands its keys back; no failure writes a preference (docs/DECISIONS.md: per-domain-suspension, write-health-axis). |

## Session, screens and windows

| Contact | Where | When it fails |
|---|---|---|
| The lock state: `CGSessionCopyCurrentDictionary`, and `com.apple.screenIsLocked`/`Unlocked` registered with `.deliverImmediately` | `DistributedNotificationScreenLockSource` | An edge triggers an authoritative re-read, never a flip; settle re-reads and a periodic tail from construction catch a dropped or early edge (docs/DECISIONS.md: settle-rereads). `.deliverImmediately` opts out of the coalescing an inactive accessory app would otherwise get (`NSDistributedNotificationCenter.h`). |
| Display UUIDs and the panel roster | `ScreenTranslation`, `DisplayUUID` | UUIDs are read fresh on every `describeAll`; a display whose UUID does not resolve is dropped from the roster and logged. |
| One `NSPanel` per surface per display | `WindowManager`, `NSPanelPresentationPanel` | Rebuilt when the display's geometry, style or HUD placement changes (W4). |
| `NSEvent` monitors for hover and clicks | `SurfaceHoverMonitor`, `NSPanelPresentationPanel` | Armed only while a surface is visible on that display (W2). |
| The desktop picture (`NSWorkspace.desktopImageURL`) | `WorkspaceDesktopPictureSource` | Nil is an answer: the Settings tiles draw their own desk. |
| Low Power Mode (`isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChange`) | `ProcessInfoLowPowerModeSource` | Seeded synchronously at init; each edge triggers a re-read, never a flip. |

## The neighbour app

| Contact | Where | When it fails |
|---|---|---|
| BetterDisplay's `.osd` and `.response` distributed notifications, registered by selector with `.deliverImmediately` | `BetterDisplayOSDSource`, `BetterDisplayCommandChannel`, `DistributedPayloadRelay` | Without BetterDisplay nothing arrives and the source sits inert. A held answer would read as silence, so the response side delivers immediately; a request with no answer within its deadline falls back to the system actuator, and when that cannot write either the bar rolls back (docs/DECISIONS.md: the-bar-never-outruns-the-screen). No sender identity (KNOWN-GAPS: BetterDisplay's channel). |

## The app's own lifecycle

| Contact | Where | When it fails |
|---|---|---|
| Login item (`SMAppService`) | `LoginItem` | Nothing is persisted on failure; a registration macOS revoked is reported in the menu, never re-registered silently (docs/DECISIONS.md: login-item-intent). |
| Sparkle (Release builds only) | `UpdaterModel` | The framework's own timeouts; no live resource held. |
| The Privacy panes, opened by URL | `AppCore` | A renamed pane opens nothing (KNOWN-GAPS: the Privacy panes). |
| `UserDefaults` | `Preferences` | No failure path writes a preference (docs/DECISIONS.md: J5-raio-global); an unknown stored value degrades to the default (P4). |
