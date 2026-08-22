# 01 — Architecture

Read `CLAUDE.md` § 3 for the layout summary. This document is the detail: technology choices, module
responsibilities, target configuration, and the flows that cross module boundaries.

---

## 1. Shape of the system

```
┌─────────────────────────────────────────────────────────────────────┐
│  APPLE CLIENTS                                                      │
│                                                                     │
│  watchOS app ──WatchConnectivity──▶ iOS app ◀──CloudKit──▶ iPadOS   │
│   (recorder)     control + files     (hub)     private DB    app     │
│      │                                  │                      │    │
│      └──── optional direct upload ──────┴──────────────────────┘    │
│                        │                                            │
└────────────────────────┼────────────────────────────────────────────┘
                         │  (only when ProcessingMode ≠ .localOnly)
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│  PROCESSING PLANE (optional, opt-in per meeting) — see docs/05      │
│  gateway · ASR · diarization · summarization · retrieval · outbox   │
└─────────────────────────────────────────────────────────────────────┘
```

Three properties define the shape:

1. **The Watch is a peer, not a sensor.** It has its own capture engine, its own manifest store, and its own
   recovery path. It degrades to "recording alone in a metal box" without loss.
2. **The iPhone is the hub, not a requirement.** It aggregates Watch segments, drives CloudKit sync, and hosts
   most processing. Its absence delays availability; it never destroys data.
3. **The processing plane is detachable.** The entire product must build, run, and pass tests with the backend
   unreachable and `ProcessingMode == .localOnly` forced on. This is a CI configuration (`make test LOCAL_ONLY=1`).

---

## 2. Technology choices

| Concern | Choice | Rationale / notes |
|---|---|---|
| UI | SwiftUI + Observation, `async/await`, Swift 6 strict concurrency | One design system, platform-specific navigation. `@Observable` view models, no Combine in new code. |
| Project generation | **XcodeGen** (`project.yml`) | The `.xcodeproj` is generated, never hand-edited, never a merge conflict. Run `make gen` after adding files. |
| Packages | Swift Package Manager, local path dependencies | Package tests run in seconds with no simulator. |
| Audio capture | `AVAudioSession` + `AVAudioEngine` (validated per platform in `NSP-002`) | `AVAudioRecorder` is simpler but gives less control over segment boundaries and level metering; prototype both on Watch. |
| Audio format | AAC-LC / HE-AAC in fragmented `.m4a` segments for Watch; user-selectable high-quality on iPhone/iPad | Speech-optimized, decodable per segment, ASR-friendly. Locked by `NSP-003` measurement. |
| Watch↔Phone | `WatchConnectivity` — `sendMessage` for control/state, `transferFile` for segments, `transferUserInfo` for manifest deltas and receipts | See `docs/03` for the exact contract. |
| Local persistence | **GRDB (SQLite)** with explicit migrations, WAL, and FTS5 | Chosen over SwiftData: explicit migrations, deterministic queries, FTS5 for search, testable without a simulator, and a stable story for large transcripts. |
| Media files | Plain files in the app container under Data Protection, referenced by the DB — **never blobs in SQLite** | Keeps the DB small and the media path debuggable. |
| Cloud sync | CloudKit private DB, custom record zones per workspace, `CKAsset` for media, `CKSyncEngine`-style change-token loop | Structured records, encrypted fields, sharing primitives. |
| Search | GRDB FTS5 for text + a local vector index for semantic retrieval; Core Spotlight for system search of non-excluded meetings | Authorization filter applied *before* retrieval. |
| System integration | App Intents (incl. `AudioRecordingIntent`), WidgetKit, ActivityKit Live Activities, Control Center control, Siri | Recording intents carry mandated ongoing-presentation behaviour — treat as a spike. |
| Security | Data Protection file classes, Keychain, CryptoKit | `.completeUnlessOpen` needed for files written while locked; threat-model per `docs/06`. |
| On-device ASR | `Speech` framework / `SpeechAnalyzer` where available, capability-detected | Provisional transcript + full local-only path. |
| On-device summarization | Apple's on-device model where available, capability-detected, behind `SummarizerProtocol` | Gates a higher minimum OS; must degrade to "transcript only, no summary" rather than silently going to cloud. |
| Backend | Python 3.12 + FastAPI, Postgres 16 + pgvector, S3-compatible object store, Redis + Celery workers, containerized | See `docs/05`. Chosen for ASR/LLM ecosystem maturity. Vapor was considered for language uniformity and rejected on ecosystem grounds. |
| Analytics | First-party, content-free, aggregate; explicit opt-in for content-bearing diagnostics | No transcript, no titles, no audio, ever (Invariant I5). |

### Deliberately rejected

- **iCloud Drive as the coordination layer** — a folder of mutable files is a weak transaction and conflict
  model for segmented media, per-field permissions, and multi-device edits. It remains an *export* destination.
- **A single long Watch audio file streamed to the phone** — makes wrist-only recording fictional.
- **SwiftData as the primary store** — migration and query opacity are unacceptable for a corpus the user cannot
  afford to lose.
- **Full CRDT co-editing in v1** — operation-log merge per note block is sufficient and far cheaper; revisit if
  simultaneous multi-user editing becomes a real workflow.

---

## 3. Module responsibilities

### `NSPCore`
Domain value types (`Meeting`, `Segment`, `TimelineEvent`, `TranscriptTurn`, `NoteBlock`, `Insight`, `Action`,
`Decision`, `EvidenceSpan`, `Policy`), typed IDs, `Clock` and `MonotonicClock` protocols, `FeatureFlags`,
error taxonomy, `Result`-carrying operation types. **No I/O. No imports beyond Foundation.** Everything is
`Sendable`.

### `NSPPersistence`
GRDB stack, schema migrations (append-only, numbered, reversible), repositories per aggregate, FTS5 index
maintenance, vector index, tombstones, and the crash-safe write helpers. Owns the on-disk container layout
(`docs/02` § 5). Exposes repositories as protocols so tests use in-memory stores.

### `NSPMedia`
- `CaptureEngine` (actor): audio session configuration, route handling, interruption handling, level metering.
- `Segmenter`: rotation policy, atomic close (temp name → close → checksum → rename), header/footer writing.
- `ManifestWriter`: durable append of segment records and timeline events; double-buffered so a crash mid-write
  never corrupts the previous good manifest.
- `IntegrityChecker`: SHA-256 per segment, stream-level hash, playable-boundary repair for a truncated tail.
- `TimelineReconciler`: converts sample offsets + pause/interruption gaps into a canonical meeting timeline.
- `PlaybackEngine`: gapless playback across segments, seek by canonical time, rate 0.5×–3×, skip silence.

### `NSPTransfer`
`WatchConnectivity` session management, an outbox with idempotency keys, receipt tracking, duplicate and
out-of-order delivery handling, reclamation policy (Watch copy deleted only after verified receipt + retention
grace), and the reachability-aware preview channel.

### `NSPSync`
CloudKit zone setup, record mapping, `CKAsset` upload/download with content-addressed dedupe, change-token
loop, conflict merge (field-level for metadata, operation-log for note blocks), partial-availability state,
quota and account-state error surfacing, key-reset handling.

### `NSPIntelligence`
Protocols — `TranscriberProtocol`, `DiarizerProtocol`, `SummarizerProtocol`, `RetrieverProtocol`,
`EmbedderProtocol` — plus on-device implementations, a `MockX` for each in `NSPTestSupport`, evidence binding
and verification (`EvidenceResolver`, `EntailmentChecker`), prompt/template versioning, correction memory, and
the alignment job that maps provisional artifacts to canonical timestamps. Also home to `DashboardComposer`
(assembles `DashboardModel` from live repositories) and, added 2026-08-22, `RelationshipGraph` — one shared
"everything tied to this Person/Thread/Project" read layer every screen queries through instead of writing its
own joins — and `WeeklyBriefComposer`, the Monday-morning digest built on top of it.

### `NSPBackendClient`
Typed client for the processing plane. Every method takes a `ProcessingGrant` obtained from `NSPPolicy`; there
is no way to call it without one. Handles upload of ephemeral processing copies, job polling, and deletion
receipts.

### `NSPPolicy`
The choke point. `ProcessingMode` per meeting, consent records, retention rules, redaction, access control,
audit ledger, and **`NetworkGate`** — the single type through which any content-bearing egress must pass. Its
test suite includes a network-content audit (`docs/10` § "Invariant gates").

### `NSPActions`
Action and decision ledgers, lifecycle (`Proposed → Confirmed → Sent → In progress → Done/Dismissed`), owner
and due-date resolution with inference labelling, and the integration outbox (idempotent, receipted, retryable,
auditable) for Reminders, Calendar, and third-party connectors.

### `NSPDesignSystem`
Colour/typography/spacing tokens, status indicators that are never colour-only, haptic vocabulary, Live Activity
and complication views, accessibility helpers, and the shared recording-state components used identically on
Watch, phone, and pad.

### `NSPTestSupport`
Fakes for every protocol, deterministic clocks, generated golden audio with known tones for timestamp
verification, WatchConnectivity simulator (delay/duplicate/out-of-order/drop), CloudKit fake, property-test
generators for the capture state machine, and fixture meetings.

---

## 4. Targets (`project.yml`)

| Target | Platform | Contains |
|---|---|---|
| `NorthStarPhone` | iOS 18+ / iPadOS 18+ ⚠️ floor pending `NSP-002` | `@main`, SwiftUI scenes, navigation, view models |
| `NorthStarWatch` | watchOS 11+ ⚠️ | Watch app, complications entry, capture UI |
| `NorthStarWidgets` | iOS + watchOS | WidgetKit widgets, Live Activity, complications |
| `NorthStarIntents` | iOS + watchOS | App Intents incl. `AudioRecordingIntent`, Shortcuts, Siri |
| `NorthStarShareExtension` | iOS | Import audio/video via share sheet |
| `*Tests` | per target | Simulator-bound tests only (UI, integration, snapshot) |

**Capabilities:** App Groups (`group.com.northstarpromise.shared`) for widget/extension state, iCloud/CloudKit,
Background Modes (audio, background processing), Push (CloudKit subscriptions), Keychain sharing.

**Configurations:** `Debug`, `Release`, and `LocalOnly` — a build configuration that compiles out
`NSPBackendClient` entirely, used to prove the local path has no cloud dependency.

---

## 5. Key cross-module flows

### 5.1 Watch start → durable acknowledgement (the two-second path)

```
User taps Record on Watch
  → WatchCaptureViewModel.start()
  → NSPPolicy.preflight(): consent state, storage estimate, battery threshold  (may warn, user may override)
  → NSPCore: mint MeetingID (UUIDv7), DeviceID, captureMode = .watch
  → NSPPersistence(Watch): insert meeting row  [durable]
  → NSPMedia.CaptureEngine.arm(): configure + activate recording audio session
  → NSPMedia.Segmenter.openSegment(0): write header, fsync              [durable]
  → NSPMedia.ManifestWriter.seal(header)                                 [durable]
  → ONLY NOW: UI → Recording, haptic fires, complication updates
  → NSPTransfer.sendState(.started)  (best-effort, non-blocking, never gates the above)
```

If any step before the durable write fails, the UI goes to `Failed` with a specific cause and a retry — it never
shows `Recording`.

### 5.2 Segment lifecycle

```
Segmenter rotates every N seconds (30–60, tuned) or on pause/interruption/stop
  → close writer → fsync → SHA-256 → rename temp→final → manifest append [durable]
  → NSPTransfer.enqueue(segment, idempotencyKey: segmentID)
  → WCSession.transferFile (opportunistic; may deliver much later)
  → iPhone: didReceive file → move into container synchronously → verify hash
      → NSPPersistence insert → send receipt via transferUserInfo
  → Watch: receipt received → mark transferred → eligible for reclamation
      only after (receipt verified) ∧ (CloudKit policy satisfied ∨ local iPhone copy confirmed)
      ∧ (retention grace elapsed)
```

### 5.3 Processing

```
Meeting finalized on hub device
  → NSPPolicy.processingGrant(for: meeting)     // .localOnly → skip cloud entirely
  → NSPIntelligence.transcribe(): on-device pass always available
  → if grant allows: NSPBackendClient.submitBatch(assets, grant)
      → higher-accuracy canonical transcript + diarization returns
  → AlignmentJob: map provisional words, markers, ink strokes, photos → canonical timestamps
  → Summarizer produces layered outputs, each bullet carrying EvidenceSpans
  → EntailmentChecker verifies each claim against its cited span; failures downgrade to `suggestion`
  → Artifacts stored versioned with model/prompt/template version + confidence
  → NSPSync uploads records/assets per policy
```

### 5.4 Action export

```
User reviews proposed actions (all inferred fields visibly labelled)
  → user confirms owner/date/destination      ← required; ambiguity blocks export (Invariant I6)
  → NSPActions.outbox.enqueue(action, idempotencyKey: actionID + destination + revision)
  → connector executes; receipt stored; retry is safe and creates no duplicate
  → AuditEvent recorded: who confirmed, what payload, what response
```

---

## 6. Concurrency model

- `CaptureEngine` is an `actor`; the audio render/tap path is on the audio thread and communicates through a
  lock-free ring buffer. **Never `await` on the audio thread, never touch `MainActor` from it.**
- `TransferCoordinator`, `SyncCoordinator`, and `IntelligenceScheduler` are actors with serial job queues and
  explicit backoff.
- View models are `@MainActor @Observable`.
- Swift 6 strict concurrency is enabled repo-wide. Suppressions require a comment explaining why and a ticket.

## 7. Error and failure strategy

| Failure | User experience | Recovery |
|---|---|---|
| iPhone unreachable | Watch shows "Saved on Watch" with segment count | Queued transfers retry automatically; manual retry available |
| Cloud unavailable / quota full | Local meeting complete; cloud badge warns with the exact reason | Backoff, storage guidance, export, local-only mode |
| AI job fails | Raw audio + transcript remain; the failed section is labelled, not hidden | Retry with different model/region; partial outputs versioned |
| Missing segment | Timeline shows the exact gap and the device that last held it | Search pending stores on Watch/iPhone; request retransfer |
| Clock drift between devices | No visible reordering | Sample offsets + per-device anchors, aligned post-hoc |
| Duplicate meeting start | One primary plus a linked duplicate candidate | Idempotency key + merge UI; never auto-delete audio |
| App crash mid-recording | Next launch offers the recovered meeting with disclosed missing tail | Manifest scan + playable-boundary repair |

Rules: every failure has a user-visible state name, a cause, and an action. No spinner without a timeout. No
error that only appears in a log. No `try?` in the capture, transfer, sync, or policy paths.

---

## 8. Performance budgets

| Path | Budget |
|---|---|
| Watch Start → durable ack | ≤ 2 s p95 |
| Meeting opens from local store | ≤ 1 s p95 |
| Seek within a cached segment | ≤ 300 ms |
| Transcript scroll | 60 fps with a 3-hour transcript (windowed rendering required) |
| Watch memory during recording | Stay well inside the watchOS extension budget; no full-waveform retention |
| Cold app launch | ≤ 1.5 s to Today screen |
| Library query | Paged; must not load full transcripts — 100 K meetings per account is the design target |

## 9. Build and CI

`make check` = lint + package tests + simulator tests + invariant gates + AI evals.

CI matrix: latest and previous supported OS simulators for iOS and watchOS; a `LocalOnly` configuration build;
a nightly soak job (8-hour import, thousands of segments, week-long transfer queue). Physical-device validation
is a manual gate per `CLAUDE.md` § 7 and is required for milestone sign-off.
