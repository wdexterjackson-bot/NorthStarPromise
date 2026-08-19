# Hardware validation report — NSP-002 (watchOS background recording spike)

Copy this file to `hardware-<YYYY-MM-DD>.md` for each run. Per `CLAUDE.md` §7, this can only be
verified on physical devices — a green simulator build proves nothing about whether recording
survives wrist-down/screen-off/backgrounded/phone-off conditions.

**Do not edit `docs/03-CAPTURE-AND-TRANSFER.md` or `docs/00-PRODUCT-BRIEF.md` §8 until this report
is filled in.** If a result below contradicts the spec's working defaults, change the spec in the
same PR that adds this report (`CLAUDE.md` §7: "If a spike result contradicts a spec, change the
spec. Do not build on a hope.").

---

## How to run the spike harness

1. Open `NorthStar.xcodeproj`, select the `NorthStarWatch` scheme, and run it on a **physical**
   paired Apple Watch (Xcode → Window → Devices and Simulators → pair over Wi-Fi so you can
   disconnect the cable and walk away).
2. From the Watch app's root screen, tap **Spike** (top-right) to open `SpikeRecordingView`
   (`App/Watch/Spike/SpikeRecordingView.swift`). This is throwaway measurement code — it is
   deliberately not part of `NSPMedia` and will be deleted once `NSP-018`/`NSP-019` land.
3. Pick a recording-affordance strategy (the picker at the top) and tap **Start**. The screen
   shows elapsed time, and battery/thermal state are logged every 10 s.
4. Lower your wrist / let the screen sleep. Background the Watch app if possible (press the Side
   button once, or start another app). For the "phone powered off" runs, power off the paired
   iPhone entirely before starting.
5. Let it run for the target duration (60 or 120 minutes). Do not touch the Watch.
6. Return, tap **Stop**, then **Export log** — this opens the share sheet with the run's log as
   plain text (one timestamped line per 10 s tick plus start/stop/session-delegate events).
   AirDrop it to your Mac or paste it into a file, and save it under `raw-logs/` next to this
   report as `spike-log-<timestamp>.txt`.
7. Fill in every row of the results table below from that log plus your own observation (did the
   complication/Live Activity/anything show a wrong state, did the recording actually contain
   audio when you play it back afterward, etc.).

Repeat across **at least two Watch generations** (`CLAUDE.md` §7 / `NSP-002` acceptance) and
across the three recording-affordance strategies the picker offers:

| Strategy | What it configures |
|---|---|
| `A — plain record session` | `AVAudioSession(.record, .default)`, no extended runtime session |
| `B — extended runtime session` | Same audio session + `WKExtendedRuntimeSession` started alongside |
| `C — AudioRecordingIntent` | Starts capture via the platform's sanctioned `AudioRecordingIntent` / ongoing recording presentation, per `docs/03` §2.2 — verify its exact API shape directly in Xcode before trusting this run; the harness only logs a reminder for this strategy |

---

## Results

### Run metadata

| Field | Value |
|---|---|
| Date | |
| Watch model / generation | |
| watchOS build | |
| Paired iPhone model | |
| iOS build | |
| Xcode version | |

### 60-minute runs

| Strategy | Wrist down / screen off | App backgrounded | Phone powered off | Survived full 60 min? | Process suspended or terminated? | Battery delta (%) | Thermal peak | Notes |
|---|---|---|---|---|---|---|---|---|
| A | | | | | | | | |
| B | | | | | | | | |
| C | | | | | | | | |

### 120-minute runs

| Strategy | Wrist down / screen off | App backgrounded | Phone powered off | Survived full 120 min? | Process suspended or terminated? | Battery delta (%) | Thermal peak | Notes |
|---|---|---|---|---|---|---|---|---|
| A | | | | | | | | |
| B | | | | | | | | |
| C | | | | | | | | |

### Playback verification

For each run above: does the exported `.m4a` actually contain continuous audio for the claimed
duration, or are there silent gaps / truncation? (Play it back — don't just trust the elapsed-time
counter.)

| Run | Playable end-to-end? | Audible gaps (timestamp + estimated duration) |
|---|---|---|

---

## Conclusion (fill in last)

- **Recommended recording-affordance strategy:** A / B / C — why.
- **Process suspension/termination behaviour observed:**
- **Recommended minimum OS floor:** (only raise from the current `docs/00` §8 working default if
  a strategy needs it to survive)
- **Battery cost is acceptable / not acceptable because:**
- **Spec sections this report invalidates, if any (edit in the same PR):**

Once this is filled in and the recommendation is locked, update `docs/00-PRODUCT-BRIEF.md` §8 and
close `NSP-002` per `docs/09-BACKLOG.md` (`NSP-010` — "Decision write-up from spikes").
