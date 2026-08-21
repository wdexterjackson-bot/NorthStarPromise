# 03 — Capture and Transfer

The capture subsystem is the product. Every other document describes something that can be regenerated;
this one describes the only thing that cannot. `NSPMedia` owns capture, segmentation, integrity, and recovery;
`NSPTransfer` owns the Watch↔iPhone contract, outbox, and reclamation; `NSPPolicy` owns preflight and consent;
`NSPPersistence` owns the container layout and durable writes; `NSPCore` owns the clocks, IDs, and state machines.

Behaviours marked ⚠️ are **spikes** — measure on hardware (`CLAUDE.md` § 7), then amend this document.

---

## 1. Design goals and the failure modes we engineer against

| Goal | Concrete meaning |
|---|---|
| G1 · Never lie about state | The UI shows `Recording` only after a durable header exists (I1). |
| G2 · Never lose more than one segment | Worst-case loss on hard kill is the open segment's un-fsync'd tail, bounded by the rotation period. |
| G3 · Always produce something playable | A damaged session yields `Availability.recoverable` with a disclosed missing tail, never `failed`. |
| G4 · Degrade loudly, not silently | Health problems warn; only three conditions stop a recording, and each writes a `sealedStop` event. |
| G5 · The recorder is independent | Capture must complete with the iPhone off, no network, no iCloud (I2). |
| G6 · Timelines are reproducible | Two devices' segments reconcile deterministically from sample counts, not clocks. |

Failure modes explicitly designed against, each mapping to an acceptance test in § 13:

1. **Optimistic acknowledgement** — the single worst bug class. Mitigated by the arm ordering in § 3.2.
2. **Silent short meeting** — a truncated tail that nobody discloses. Mitigated by manifest WAL + repair (§ 5).
3. **Timer drift** — duration derived from wall clock, breaking every `EvidenceSpan`. Mitigated by § 4.
4. **Premature reclamation** — Watch copy deleted on transfer *initiation*. Mitigated by § 9's three-clause rule.
5. **Duplicate segments** — a delayed `transferFile` re-queued without an idempotency key. Mitigated by § 9.
6. **Dead microphone** — session active, route present, samples all zero. Mitigated by health signals (§ 2.5).
7. **Two owners** — Watch and iPhone both recording the same room, producing two half-meetings (§ 11).
8. **Storage cliff** — the disk fills mid-write and the close protocol fails halfway (§ 3.5, § 6).

---

## 2. Audio session and capture engine (`NSPMedia.CaptureEngine`)

`CaptureEngine` is an `actor`. The render tap runs on the audio thread and communicates with the actor through a
single-producer/single-consumer lock-free ring buffer. **No `await`, no allocation, no logging, no `MainActor`
hop on the audio thread.**

### 2.1 Session configuration

| Platform | Category / mode | Options | Format target |
|---|---|---|---|
| watchOS | `.record`, mode `.default` ⚠️ (`.spokenAudio` availability is a spike) | `.allowBluetooth` off by default on Watch — the built-in mic is more reliable in-room | 16 kHz mono, AAC-LC @ 32 kbps |
| iOS | `.playAndRecord`, mode `.spokenAudio` (falls back to `.default`) | `.allowBluetooth`, `.allowBluetoothA2DP`, `.defaultToSpeaker`, `.mixWithOthers` **off** | 48 kHz mono default; user-selectable 48 kHz stereo "high quality" |
| iPadOS | as iOS | as iOS, plus multi-input selection when a USB/Lightning interface is attached | as iOS |

The Watch session is activated *before* the first segment header is written and deactivated only after the last
segment is sealed. Preferred IO buffer duration is 20 ms on iOS, 40 ms on Watch (fewer wakeups, measurably less
drain ⚠️). `AVAudioEngine` is the primary implementation; `AVAudioRecorder` is retained behind
`CaptureBackendProtocol` as a Watch fallback if the engine's background behaviour proves unstable (`NSP-002`).

### 2.2 Background, wrist-down, and the recording affordance

watchOS background capture requires the platform's sanctioned recording affordance — a recording audio session
plus `AudioRecordingIntent` with its mandated ongoing system presentation. ⚠️ **Exact per-version behaviour is
`NSP-002`, not an assumption.** The engine must therefore treat suspension as *possible at any time*: the design
already survives it, because the only unsaved state is the open segment's ring-buffer residue.

Wrist-down and screen-off must not change capture behaviour at all. The UI layer may stop rendering, but
`CaptureEngine` never observes UI lifecycle. On iOS, the app declares the `audio` background mode and drives a
Live Activity; the Live Activity is a *view* of capture state and never a source of truth.

### 2.3 Route handling

Route changes are handled, logged as `TimelineEvent.routeChange(from:to:)`, and **never stop the recording**.

| Reason | Behaviour |
|---|---|
| `.newDeviceAvailable` (AirPods connect) | Rotate segment at the boundary, adopt new input if it is a microphone, emit `routeChange`, warn in UI for 5 s. |
| `.oldDeviceUnavailable` (AirPods leave) | Rotate, fall back to built-in mic, emit `routeChange` + `levelWarning(.inputLoss)` if no input for > 1.0 s. |
| `.categoryChange` / `.override` | Re-assert our category; if re-assertion fails twice, treat as interruption. |
| `.routeConfigurationChange` | Log only; no rotation. |

Rotating on route change keeps every segment homogeneous in format and channel count, which matters because
segments are immutable (I3) and must be independently decodable by ASR.

### 2.4 Interruption handling

`.began` → flush ring buffer, close the current segment through the full atomic protocol, transition
`Recording → Interrupted`, write `interruptionBegan(cause)`. `.ended` with `.shouldResume` → re-activate the
session, open the next segment, write `interruptionEnded`, return to `Recording`. Without `.shouldResume`, or if
re-activation fails 3× with exponential backoff (0.5 s / 2 s / 8 s), the meeting is sealed and left
`Availability.recoverable` with the gap disclosed. **The audio already written is never discarded.**

### 2.5 Health signals

Levels are sampled from the tap at 10 Hz on iOS and **2 Hz on Watch** (§ 7). Each signal is a `levelWarning`
`TimelineEvent` and a UI banner; none of them stops recording.

| Signal | Detection | Threshold | Effect |
|---|---|---|---|
| Silence | peak < −60 dBFS continuously | 20 s | Warn: "No sound detected — check the mic" |
| Abnormally low level | rolling 60 s RMS < −45 dBFS | 60 s | Warn once per 5 min: "Very quiet — move closer" |
| Clipping | ≥ 1 % of frames at \|sample\| ≥ 0.999 in a 5 s window | 1 window | Warn: "Audio is distorting" |
| Input loss | tap delivers no buffers | 1.0 s | Warn + attempt route re-acquisition; escalates to interruption at 5 s |
| Route change | session notification | immediate | Informational chip, auto-dismiss |

**What warns vs. what stops.** Only three conditions stop capture, and all three are a *sealed stop*: thermal
state `.critical`, battery below the hard floor (§ 7), and free storage below the reserve (§ 6). Everything
else — silence, clipping, low level, route churn, interruption, unreachable phone — warns and keeps recording.

### 2.6 Real-time noise suppression (three tiers)

| Tier | Mechanism | Status |
|---|---|---|
| 1 | `AVAudioEngine` input node's built-in voice processing (`setVoiceProcessingEnabled`), own AGC disabled | Shipped, always on (best-effort; failure is non-fatal) |
| 2 | `AudioDynamicsProcessor` — single-band AGC + downward expander (noise gate + expansion zone, RMS-classified per block) | Shipped, always on |
| 3 | `SpectralNoiseSuppressor` — FFT-based spectral subtraction (Wiener-style spectral gating with a spectral floor), Accelerate/vDSP, overlap-add STFT | ⚠️ Behind `FeatureFlag.tier3SpectralNoiseSuppression`, **default off** pending § 7's hardware validation (battery/CPU cost on Watch, real-room tuning) |

All three run on the audio render tap thread inside `AVAudioEngineCaptureBackend.startEngine` — same
no-allocation/no-logging/no-actor-hop rules as the rest of this section. When enabled, tier 3 runs *before*
tier 2 (denoise the raw signal, then normalize loudness on the result) and reuses tier 2's RMS-threshold
noise/speech classification (below `expanderThresholdDecibels`) to decide when to update its internal noise
spectral profile, rather than a separate voice-activity detector. Tier 3 inherently adds up to one STFT frame
(~20–40 ms depending on sample rate) of algorithmic latency between input and corresponding output — invisible
to a recorder with no live-monitoring path, but worth knowing before building one.

---

## 3. The segmenter (`NSPMedia.Segmenter`)

### 3.1 Rotation policy

Nominal rotation is **45 s** on Watch and **60 s** on iPhone/iPad, tuned within the 30–60 s band from
`00-PRODUCT-BRIEF` § 8. The tradeoff: shorter segments shrink the worst-case unflushed loss window and let
transfers start sooner, but each rotation costs a file create, an fsync, a SHA-256 pass, a manifest append, and a
`transferFile` with its own protocol overhead. At 45 s a 60-minute meeting is 80 segments — enough to keep the
loss window under a minute, few enough that the WatchConnectivity queue stays sane. Rotation is **sample-driven**
(`samplesWritten ≥ rotationSamples`), evaluated on buffer boundaries, so rotation points are reproducible.

Forced rotation also occurs on: pause, resume, interruption begin, stop, route change, format change, thermal
escalation to `.serious`, and storage crossing the warn threshold.

### 3.2 The atomic close protocol

```
1. writer.finishWriting()                  // encoder flushes trailer into .tmp-NNNNNN.m4a
2. fd.fsync()                              // bytes are on stable storage, not in the page cache
3. sha = SHA256(file)                      // hash the exact bytes that survived the fsync
4. rename(.tmp-NNNNNN.m4a → NNNNNN.m4a)    // atomic; final name means "complete and hashed"
5. manifest.wal.append(segmentRecord); wal.fsync()
6. NSPPersistence.insert(Segment, transferState: .local)
7. NSPTransfer.enqueue(segmentID)          // only now may the outbox see it
```

Order is load-bearing:

- **fsync before hash** — hashing a page-cached file yields a checksum for bytes that may never reach the disk;
  the hash must describe the durable artifact.
- **hash before rename** — the final filename is the *claim* that the file is complete and verified. A crash
  between 2 and 4 leaves a `.tmp` file, which recovery knows how to interrogate. There is no filename that means
  "closed but unhashed", so recovery never has to guess.
- **rename before manifest** — rename is atomic, so the manifest can never reference a name that does not exist.
  A crash between 4 and 5 leaves an orphan final-named segment, which recovery adopts by re-hashing.
- **manifest before enqueue** — a segment must be durable locally before it can be transferred (I2). The outbox
  never sees bytes that the manifest does not know about.
- **WAL append, not manifest rewrite** — appending + fsync is one small write; rewriting `manifest.json` on every
  rotation would put the whole session's record at risk 80 times per hour. Full seal happens once, at stop.

Segments are opened by writing the header and fsyncing it *before* the first audio frame, so an armed-but-empty
segment is still a valid, zero-length-audio file rather than a zero-byte stub.

### 3.3 Rotation under lifecycle events

| Event | Segmenter behaviour | Timeline |
|---|---|---|
| Pause (user) | Full close protocol; do not open a successor until resume | `pause` at current `sampleOffset` |
| Resume | Open segment `n+1`; `startSample` continues from the pre-pause total (gap is explicit, not implied) | `resume` |
| Interruption begin | Full close; if the OS suspends us before step 2, the `.tmp` survives for repair | `interruptionBegan(cause)` |
| Stop (user) | Close, then seal the manifest (§ 3.4) | `stop` |
| Thermal `.serious` | Rotate, drop Watch bitrate one step, warn | `thermal(.serious)` |
| Thermal `.critical` | **Sealed stop** | `thermal(.critical)` + `sealedStop(.thermal)` |
| Battery critical | **Sealed stop** | `batteryWarning` then `sealedStop(.battery)` |
| Storage warn | Rotate, warn, shorten rotation to 30 s | `storageWarning` |
| Storage critical | **Sealed stop** | `sealedStop(.storage)` |

A **sealed stop** is a normal stop that the user did not ask for: it runs the full close and seal, marks the
meeting `Finalizing → SavedRaw`, and records the reason so the UI can explain it. It is never a crash path.

### 3.4 Sealing

Seal follows `02-DATA-MODEL` § 4 exactly: write `manifest.json.tmp` (containing every segment record, timeline
event, health rollup, and `streamSHA256` over the ordered segment hashes), fsync, copy the current
`manifest.json` to `manifest.json.bak`, rename tmp over `manifest.json`, fsync the directory, then truncate
`manifest.wal`. `ManifestWriter` is double-buffered precisely so a crash mid-seal always leaves one valid
manifest.

### 3.5 Storage failure mid-protocol

Every step is a typed `throws`. `ENOSPC` at any step triggers: abandon the current `.tmp` (leave it for
recovery), emit `storageWarning`, attempt a sealed stop with the segments already durable. **No `try?` anywhere
in this path** (`CLAUDE.md` § 5.6).

---

## 4. Timeline math

The canonical clock is a **monotonic sample counter per device**, incremented by the frame count of every buffer
the tap delivers, starting at 0 at `start`. `MonotonicClock` in `NSPCore` is the injectable abstraction; `Date()`
and `Timer` are forbidden in `NSPMedia` (they are wall-clock, wrong under NTP steps, DST, user clock edits, and
timer coalescing — a 60-minute `Timer`-derived duration drifts by seconds, which desynchronizes every
`EvidenceSpan`).

- `Segment.startSample` = sum of `sampleCount` of all prior segments **on that device**, plus the recorded gap
  samples. `Meeting.canonicalDuration` = Σ `sampleCount` + Σ gap durations. `startedAt`/`endedAt` remain
  wall-clock and are display-only.
- **Gaps are first-class.** A pause or interruption produces a `pause`/`interruptionBegan` event at offset `x`
  and a `resume`/`interruptionEnded` event at offset `x + g`, where `g` is measured from the wall-clock delta at
  the boundary (the only legitimate use of wall clock) and stored explicitly. Playback and evidence resolution
  treat `[x, x+g)` as silence with a visible marker. Gaps are never interpolated and never collapsed.
- **Multi-device anchoring.** Each contributing device has a `DeviceAnchor { deviceID, sampleZeroWallClock,
  sampleRate }`. `TimelineReconciler` maps device-local samples to canonical samples via the anchor, then refines
  the offset by cross-correlating the first 30 s of overlapping audio when both devices captured the same room
  (correlation window ±3 s, accepted only above a confidence floor; otherwise the wall-clock anchor stands and
  the meeting is marked `anchorEstimated`). The `originDeviceID` device defines canonical time; others are
  offset onto it.
- **Drift budget: < 250 ms median absolute error at 60 minutes**, verified with golden audio containing known
  tone bursts (`NSPTestSupport`). Sample-count arithmetic is exact; the budget exists to bound
  cross-device anchoring and clock-domain differences between hardware sample rates.

---

## 5. Crash and kill recovery

Runs on every launch of Watch and iPhone, before any UI that lists meetings.

```
func recover() throws -> [RecoveryOutcome] {
  for dir in container.meetingDirectories() {
    var manifest = try? Manifest.load(dir/"manifest.json")
    if manifest == nil || !manifest!.validates() {
      manifest = try? Manifest.load(dir/"manifest.json.bak")     // double buffer
    }
    guard var m = manifest else { outcomes.append(.orphanDirectory(dir)); continue }
    if m.integrity.sealed && dir.wal.isEmpty { outcomes.append(.clean(m)); continue }

    m.apply(try WAL.replay(dir/"manifest.wal"))                  // idempotent by segmentID

    for file in dir.segments.finalNamed where !m.knows(file) {    // crash between rename & WAL append
      m.adopt(Segment(file, sha256: SHA256(file), sequence: file.sequence))
    }
    for tmp in dir.segments.tmpNamed {                            // crash before close completed
      switch IntegrityChecker.repairPlayableBoundary(tmp) {
        case .repaired(let url, let frames, let lostTail):
          let sha = SHA256(url); fsync(url)
          rename(url, to: dir.segments/nextFinalName)
          m.adopt(Segment(..., sha256: sha, isRepairedTail: true))
          m.note(missingTail: lostTail)
        case .unusable:
          quarantine(tmp)                                         // never deleted; moved to derived/quarantine
          m.note(missingTail: .unknownUpTo(rotationPeriod))
      }
    }
    m.recomputeDurationFromSampleCounts()
    m.availability = m.hasMissingTail ? .recoverable : .complete
    try m.seal()                                                  // same seal protocol as § 3.4
    try NSPPersistence.upsert(m)
    outcomes.append(.recovered(m, missingTail: m.missingTail))
  }
}
```

`repairPlayableBoundary` parses the container's frame index, discards any trailing partial frame or unfinalized
trailer, and rewrites a valid trailer into a **new** file — the original `.tmp` is never mutated in place (I3).
Recovered meetings enter the library as `Availability.recoverable` and the UI **must** state the estimated
missing tail ("up to 45 s at the end may be missing") rather than presenting a silently shorter meeting.
Recovery is idempotent: running it twice produces identical state and no duplicate `Segment` rows.

---

## 6. Preflight (`NSPPolicy.preflight`)

Runs before `Arming`, must complete in < 300 ms, and returns `[PreflightFinding]` each with
`severity ∈ {info, warn, block}`.

| Check | Warn | Block |
|---|---|---|
| Free storage vs. estimate | < 2× estimate for 60 min | < 10 min of recording headroom **or** < 200 MB reserve |
| Battery (Watch) | < 20 % | < 10 % |
| Battery (phone/pad) | < 15 % | < 5 % |
| Low Power Mode | active (transfer will be slower) | — |
| Microphone permission | — | not `.granted` |
| Thermal state | `.serious` | `.critical` |
| Consent / announcement policy | announcement required and not yet acknowledged | jurisdiction/workspace policy forbids capture |
| Another device already recording | — | see § 11 arbitration |

Storage estimate = `bitRate/8 × plannedSeconds × 1.15` (container + manifest overhead), with `plannedSeconds`
from the linked calendar event or a 60-minute default.

**Override rule:** every `warn` is overridable with one explicit tap, and the override is recorded as a
`TimelineEvent` and an `AuditEvent`. **No `block` is ever overridable** — blocks exist only where proceeding
would produce unusable or unlawful output. Permission and consent blocks route to a fix-it action, not a dead end.

---

## 7. Battery and capacity on Watch

| Lever | Decision | Tradeoff |
|---|---|---|
| Codec | AAC-LC 32 kbps mono @ 16 kHz (≈ 14 MB/hour) ⚠️ confirm ASR WER delta in `NSP-003` | HE-AAC halves size but adds encoder latency and hurts diarization |
| Degraded codec | 24 kbps on thermal `.serious` or battery < 15 % | Slight WER loss, meaningful drain reduction |
| Waveform | **Never rendered continuously.** UI shows a 5-bar level meter updated at 2 Hz; full peaks are generated post-hoc into `derived/` | Continuous waveform is the single largest avoidable drain on Watch |
| Health sampling | 2 Hz, computed from already-available tap buffers; no extra DSP passes | Detection latency of a few hundred ms is irrelevant at these thresholds |
| Display | No always-on custom rendering; rely on the system's ongoing recording presentation | |
| Remaining time | `remaining = (freeBytes − reserve) / rollingBitrate`, where `rollingBitrate` is the EWMA (α = 0.2) of the last 10 sealed segments' bytes/sample | Uses measured bytes, so VBR and codec downgrades are reflected automatically |
| Hard floors | Sealed stop at battery ≤ 4 % or thermal `.critical` | Guarantees the seal completes rather than dying mid-write |

Remaining record time is surfaced only when below 30 minutes, to avoid a constantly-updating (and
constantly-waking) label.

---

## 8. The WatchConnectivity contract (`NSPTransfer`)

Transport choice per payload. **`sendMessage` is best-effort and requires reachability; `transferUserInfo` and
`transferFile` are reliable but opportunistic and may deliver minutes later.** Nothing on the capture path ever
blocks on any of them (I2).

| Payload | Direction | API | Reliability | Notes |
|---|---|---|---|---|
| `RecordingState` | W→P | `sendMessage` (fallback `updateApplicationContext`) | Best-effort | Drives phone UI + Live Activity; dropped freely |
| `ControlCommand` (pause/resume/stop) | P→W | `sendMessage` with reply handler | Best-effort, **must be idempotent** | No reply within 3 s ⇒ UI shows "not delivered", never assumes success |
| `SegmentFile` | W→P | `transferFile` | Reliable | `metadata` carries the full segment record |
| `ManifestDelta` | W→P | `transferUserInfo` | Reliable, FIFO | Timeline events + segment records |
| `TransferReceipt` | P→W | `transferUserInfo` | Reliable | Drives reclamation |
| `PreviewFrame` | W→P | `sendMessage(_:replyHandler:nil)` | Best-effort, droppable | § 10 |
| `PolicySnapshot` | P→W | `updateApplicationContext` | Latest-wins | Consent + processing mode |

```swift
struct SegmentTransferMetadata: Codable, Sendable {   // transferFile metadata dictionary
    let schemaVersion: Int          // 1
    let idempotencyKey: String      // == segmentID.uuidString
    let meetingID: String
    let segmentID: String
    let deviceID: String
    let sequence: Int
    let startSample: Int64
    let sampleCount: Int64
    let sha256: String              // lowercase hex
    let codec: String, sampleRate: Int, channels: Int, bitRate: Int
    let isRepairedTail: Bool
    let capturedAtWall: String      // ISO-8601, display only
}
```

```jsonc
// TransferReceipt — transferUserInfo, P→W
{ "schemaVersion": 1, "type": "receipt", "segmentID": "…", "idempotencyKey": "…",
  "status": "verified",              // "verified" | "hashMismatch" | "rejected"
  "receivedSHA256": "…", "storedAt": "2026-08-19T15:07:02Z",
  "cloudState": "uploaded",          // "uploaded" | "pending" | "notApplicable"
  "receiverDeviceID": "phone-9F3C" }
```

Operational rules:

- **Size and throttling.** `sendMessage` payloads are kept under 8 KB; a 45 s segment at 32 kbps is ≈ 180 KB,
  comfortably inside `transferFile`. The system throttles aggressively when the Watch is on battery or the app is
  backgrounded — the outbox must tolerate queue depths in the hundreds and delivery latencies of hours.
- **Activation.** `WCSession.activate()` on both sides at launch; nothing is enqueued before
  `activationState == .activated`. Handle `sessionDidBecomeInactive` / `sessionDidDeactivate` on iPhone by
  re-activating immediately (Watch switch).
- **Reachability.** Only gates `sendMessage` and preview. Segment transfer never checks reachability.
- **Multi-Watch.** iPhone pairs with several Watches but only one is current. Segments are keyed by
  `deviceID`, so a second Watch's segments coexist; the phone must never assume a single Watch peer.
- **Re-pair / unpair.** On re-pair, the Watch's outbox re-enqueues everything not marked `.verified`.
  Idempotency keys make redelivery harmless. **Unpairing never deletes Watch-side audio** — the Watch keeps its
  copy and offers export.

---

## 9. The transfer outbox

Every outbound item carries `idempotencyKey = segmentID` (for control messages,
`commandID + meetingID + revision`). Receivers dedupe by key before doing any work, so duplicate,
out-of-order, and hours-late deliveries are all no-ops after the first success.

```
TransferState (02-DATA-MODEL § 2):

 .local ──enqueue──▶ .queued ──WCSession accepts──▶ .inFlight
                        ▲                              │ didFinish(error: nil)
                        │ backoff                      ▼
                        └──── .failed(reason) ◀── .receivedUnverified
                                   ▲                   │ receipt: status == verified
                                   │ hashMismatch      ▼
                                   └───────────────  .verified
                                                       │ reclamation predicate
                                                       ▼
                                                   .reclaimed   (localURL = nil)
```

Receiver side: `didReceive(file:)` **synchronously** moves the file into the container (the inbox URL is deleted
on return), then hashes it. Hash match ⇒ insert `Segment` (`.receivedUnverified` → `.verified`), send receipt.
Hash mismatch ⇒ quarantine, receipt `hashMismatch`, Watch re-enqueues once with a fresh attempt count.

Backoff on `.failed`: 5 s, 30 s, 2 min, 10 min, 1 h, capped at 6 h, with ±20 % jitter; attempts are unbounded
because the correct behaviour after a week of separation is still "deliver it".

**Reclamation rule — the Watch copy of a segment is deleted only when all three hold:**

```
verifiedReceipt(segment)                                   // receiver hashed it and agrees
∧ ( cloudPolicySatisfied(segment)                          // CKAsset uploaded, or policy == .localOnly
  ∨ localPhoneCopyConfirmed(segment) )                     // receipt.storedAt in phone container
∧ (now − receipt.storedAt) ≥ retentionGrace                // default 24 h, user-configurable 0–7 days
```

Reclamation additionally requires Watch free storage below the comfort threshold *or* the grace period having
elapsed with the meeting finalized. On reclaim, `localURL` becomes nil, `sha256` and `sampleCount` remain, so the
timeline stays complete and the segment is re-requestable from the phone or CloudKit.

---

## 10. Live preview channel

"Real-time on your phone" means: **a courtesy view of what the Watch is hearing, when both devices are reachable
and the phone app is foregrounded.** It is a progressive enhancement (`CLAUDE.md` § 6).

- Preview frames are 8 kHz, 8–12 kbps Opus-or-AAC chunks of ~2 s, sent with `sendMessage` and **dropped, never
  queued**, when unreachable. Preview stops entirely when the phone app backgrounds.
- Preview frames are **never** written to `segments/`, never hashed, never referenced by the manifest, and never
  used for canonical transcription. They may feed a provisional transcript, which is stored with
  `TranscriptTurn.isProvisional = true` and negative `revision`, and is replaced when real segments arrive.
- The phone UI must distinguish preview from saved with a persistent, non-colour-only indicator: a "Live preview —
  saved copy on Watch" label plus the count of segments actually received and verified. A user must never be able
  to conclude from the phone screen that audio is saved on the phone when it is not (I1).
- Preview is disabled automatically in Low Power Mode, on thermal `.serious`, and when `ProcessingMode ==
  .localOnly` would route it anywhere off-device.

---

## 11. Multi-device arbitration

**One microphone owner per account at a time.** Ownership is a lease: `{ meetingID, deviceID, expiresAt }`
propagated via `updateApplicationContext` (Watch↔phone) and CloudKit (phone↔pad), renewed every 30 s.

| Scenario | Rule |
|---|---|
| Watch recording, user taps Record on iPhone | Phone preflight returns `block` with the reason and the four canonical choices: **Keep recording on Watch** (default — opens the Watch meeting on the phone so it can be controlled from there), **Take over on iPhone** (Watch performs a sealed stop; the phone starts a *new* meeting linked as a continuation), **Record separately** (explicit second `Meeting`, warned, later offered as a merge candidate), or **Cancel**. Never a silent second recorder. |
| Watch recording, phone unreachable, user taps Record on phone | Phone cannot see the lease. It starts, and on reconnect the two meetings are surfaced as **duplicate candidates** with a merge UI. Audio from neither is ever auto-deleted (`01-ARCHITECTURE` § 7). |
| AirPods connect mid-meeting | Segment rotates; input follows the new route; `routeChange` recorded; a 5 s banner names the new input. Recording continues. |
| Incoming call | Interruption path (§ 2.4). If the user takes the call on the phone while the **Watch** owns the mic, the Watch keeps recording — the phone's call does not touch the Watch's session. If the phone owns the mic, capture interrupts and resumes after the call. **We never record call audio.** |
| iPad opened during a Watch recording | iPad shows the meeting as live and read-only, with an explicit "relayed via iPhone — may lag" note; it cannot pause/stop the Watch (no Watch↔iPad path) and cannot start its own recording without taking over. |
| Two phones on one account | Lease conflict resolved by earliest `startedAt`; the loser is offered "record separately". |

**Remote control from the Watch.** When the *phone* owns the mic (not the Watch), the Watch app shows Pause/
Marker/Stop for that session instead of its own Ready screen — the reverse direction from the row above, and
the Watch's one additional role beyond standalone recording (`docs/00`'s "not a remote" differentiator is about
what records the audio, not about this control surface). Commands travel over the same `updateApplicationContext`
channel as the ownership lease, so they carry the lease's reachability characteristics: best-effort, not
guaranteed instant, and the Watch UI reflects actual confirmed state (e.g. `Paused`) only after the phone acks,
never optimistically (I1's spirit applies to state *display* here even though no audio is at stake). **This
does not extend to iPad**: there is no Watch↔iPad WatchConnectivity path (`CLAUDE.md` § 6), and relaying watch
commands through the phone or through CloudKit would add enough latency to make Pause/Stop unreliable for their
purpose — an iPad-driven recording is controlled from the iPad (and, if the iPhone is also present, from the
iPhone), never from the Watch.

---

## 12. Import path

Imports (`CaptureMode.import`) come from the share extension, Files, or Photos. Audio is transcoded to the
canonical segment format **into new segment files** (never in place), segmented on the same 60 s boundary, hashed,
and manifested — an imported meeting is indistinguishable downstream from a recorded one. Video keeps the original
file in `attachments/` and derives an audio track for segments.

Provenance is mandatory: `importedFrom` (filename, UTI, source app), `originalSHA256` of the source file,
`originalDurationSamples`, and `originalTimestampSource ∈ {embeddedMetadata, fileCreationDate, userProvided,
unknown}`. `Meeting.startedAt` uses the embedded recording date where present, otherwise file creation date,
otherwise the import time — **and the source is always displayed**, because an imported meeting with an invented
date will silently corrupt chronology and calendar matching. `originDeviceID` is the importing device, flagged
`isOriginal = false`.

---

## 13. Acceptance tests

Each is directly implementable as a test function; `TC-CAP-*` are in `NSPMediaTests`, `TC-XFER-*` in `NSPTransferTests`,
using `NSPTestSupport` fakes (deterministic clock, golden tone audio, WC simulator with delay/duplicate/drop).

| ID | Test |
|---|---|
| TC-CAP-001 | 60-min synthetic Watch capture with the phone absent produces a sealed manifest whose Σ `sampleCount` equals the injected sample count exactly. |
| TC-CAP-002 | `Recording` state is never observed before segment 0's header is fsync'd — asserted by a filesystem spy that fails the test if state changes first (I1). |
| TC-CAP-003 | Kill injected at each of the 7 steps of § 3.2, and at 100 random offsets: every run recovers to `.complete` or `.recoverable`, never `.failed`, and the disclosed missing tail ≥ actual lost audio. |
| TC-CAP-004 | Recovery is idempotent — running it 3× yields byte-identical manifests and no duplicate `Segment` rows. |
| TC-CAP-005 | `pause`/`resume` × N produces N+1 segments, no file overwritten, and canonical duration = Σ samples + Σ recorded gaps. |
| TC-CAP-006 | Golden tone burst at t = 3599 s resolves within **250 ms** of its true canonical offset after 60 min with 3 pauses and 2 interruptions. |
| TC-CAP-007 | Cross-device anchoring: Watch + phone capturing the same golden audio reconcile to < 250 ms median offset error. |
| TC-CAP-008 | A truncated `.tmp` with a partial final frame repairs to a playable file, `isRepairedTail == true`, original never mutated. |
| TC-CAP-009 | Route change, silence, clipping, and low-level injections each emit exactly one `TimelineEvent` and **do not** stop capture. |
| TC-CAP-010 | Thermal `.critical` / battery-critical / storage-critical each produce a sealed stop with a playable, sealed manifest and a `sealedStop(reason)` event. |
| TC-CAP-011 | `ENOSPC` injected at each close step leaves a recoverable meeting and never a manifest referencing a missing file. |
| TC-CAP-012 | Preflight: each `warn` is overridable and logs an `AuditEvent`; each `block` cannot be overridden by any API path. |
| TC-CAP-013 | No `Date()` or `Timer` reachable from `NSPMedia` timeline code — enforced by a source-scanning lint test. |
| TC-CAP-014 | Import with embedded date, without embedded date, and with a corrupt date each set `originalTimestampSource` correctly and never fabricate `startedAt`. |
| TC-XFER-001 | A segment delivered 3× out of order creates exactly one `Segment` row and one receipt. |
| TC-XFER-002 | Reclamation does not occur with receipt-only, with receipt + cloud but grace not elapsed, or with grace elapsed but no verified receipt; it occurs when all three clauses hold. |
| TC-XFER-003 | Hash mismatch on receipt quarantines the file, does not insert a `Segment`, and triggers exactly one re-enqueue. |
| TC-XFER-004 | 150 segments queued during 24 h of disconnection all deliver after reconnect, in-order by `sequence`, with zero duplicates. |
| TC-XFER-005 | Preview frames are never written to `segments/`, never appear in the manifest, and never produce a non-provisional `TranscriptTurn`. |
| TC-XFER-006 | Starting a phone recording while the Watch holds the lease yields a `block` finding with the four canonical choices (Keep recording on Watch / Take over on iPhone / Record separately / Cancel), and "Record separately" creates a second `Meeting`, never mutating the first. |
| TC-XFER-007 | Unpair → re-pair re-enqueues only non-`.verified` segments and deletes nothing on the Watch. |
| TC-XFER-008 | With `ProcessingMode == .localOnly`, no transfer, preview, or receipt path performs a CloudKit or network write (I5 gate). |
