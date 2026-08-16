# Open investigation — a media key occasionally takes a while to be detected

> **STATUS: OPEN, NO FIX.** Recorded 2026-07-28 from a field report by the
> author, still **without data**: "a key occasionally takes a while to be
> detected", profile unknown. No code change is born of this entry until a field
> timestamp arrives — touching the tap and suppressor paths in the dark is
> exactly the class of guess the earlier audits taught this project not to make.
> Tracked as T11.5 in [PLAN.md](../PLAN.md).

## The symptom, as reported

Occasionally a media key (volume or brightness) "lags": the effect — the HUD, or the value change, or both — arrives late. The frequency, the context (after idle? after wake? with suppression on?) and *what* exactly lags are all still uncharacterised.

## The three candidate profiles, and the code path of each

The first datum to extract from the field is WHICH of these three the symptom is. Their causes are disjoint.

1. **Late HUD, value on time** — the system applied the volume or brightness immediately (the audio changes at once) but Crema's HUD appeared late. Suspects: the OBSERVATION path — Core Audio's echo (listener → yield → Coordinator) or, for brightness, the 0.5 s poll plus the `KeyOriginBrightnessGate` window (a `sample()` that has not yet seen the applied value waits for the next poll: a structural latency of up to about one beat, documented). With suppression off, that is the design; the question is whether the reported delay exceeds the beat.
2. **Late value (with suppression on)** — the key was consumed and the APPLY took a while (a write raced against the 2 s deadline; a `coreaudiod` stall; a transient `noOutputDevice`). The HUD arrives together with the verified apply, so both are late. Suspects: the suppressor's `enqueue` queue, the write/read deadline, or a channel in recovery with the probe re-engaging.
3. **First key after idle** — only the FIRST key after a quiet period lags (or dies) and the following ones flow. Suspects: a partially enabled-but-deaf tap (the J7 family — the preventive reinstall covers wake, unlock and topology, but a reroute that fires none of the 4 triggers would sit there until the next edge), the health-check's re-enable (a 2 s poll: a silent disable costs up to 2 s before the revive), or the process being app-napped.

## What the author needs to capture (the datum that decides)

- **A timestamp** of the physical press (or a screen recording with a clock) plus Crema's subsystem log over the same interval. **Note**: the discriminating line ("media key observed") is at **debug** level — it does not persist in the unified log by default, so a retrospective `log show` will NOT have it. Capture **live, before reproducing**:

  ```bash
  log stream --level debug --predicate 'subsystem BEGINSWITH "com.colatte.crema"'
  ```

  (or Console.app → Action → Include Debug Messages).

- An honest inventory of what each category logs today: `MediaKeys` — "media key observed" (debug) plus the tap's install/reinstall/heal; `OSD` — engage/disengage, apply and read failures, suspension and probe (**no** line for a successful apply — if profile 2 turns out to be the suspect, that instrumentation has to be born in the fix's round); `Volume` — a listener registration failure (error) plus the debug lines `volume read failed … skipping the boundary refresh/emit` (`CoreAudioVolumeSource`), which discriminate profile 1; `NowPlaying` — the chain's selection and failover. The distance between the press and the first "observed" line separates profile 3 (nothing reaches the tap) from profiles 1 and 2 (it reaches, and the delay is downstream).
- Context: suppression on or off; how long the machine was idle before the key; whether a lock, wake, display change or audio-device change happened nearby; and whether the native HUD appeared in place of Crema's.

## Closing rule

With a timestamp that discriminates the profile, open the corresponding fix round (1: observation and the gate; 2: apply and the channel; 3: the tap and delivery — the J7 family, possibly a 5th reinstall trigger or idle telemetry). Without data, this entry stays open and no path is touched.
