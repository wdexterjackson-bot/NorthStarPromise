# 02 — Data Model, File Formats, and Storage Layout

This is the contract every other module depends on. Change it only through a numbered migration and an update
to this document in the same PR.

---

## 1. Principles

1. **IDs are immutable and client-minted.** UUIDv7 (time-ordered) so inserts are index-friendly and IDs sort by
   creation. Typed wrappers (`MeetingID`, `SegmentID`, …) in `NSPCore` — never raw `UUID` in a signature.
2. **Media lives in files; the database holds metadata and pointers.** No audio or ink blobs in SQLite.
3. **Segments are content-addressed and immutable** (Invariant I3). Dedupe by SHA-256.
4. **Derived artifacts are versioned, never overwritten.** Transcript revisions, summary versions, and insight
   generations accumulate; the UI shows the current one and can diff.
5. **Every generated row carries provenance**: model ID, model version, prompt/template version, generation
   timestamp, confidence, and evidence.
6. **Deletion is a state, then a job.** Soft delete → tombstone → purge across device, cloud, and processor,
   each producing a receipt.

---

## 2. Core entities

### Meeting

| Field | Type | Notes |
|---|---|---|
| `meetingID` | `MeetingID` | UUIDv7, minted by the capturing device |
| `workspaceID` | `WorkspaceID` | Determines CloudKit zone and access scope |
| `title` | `String` | May originate from a calendar event — treat as sensitive (`isTitleSensitive`) |
| `calendarEventID` | `String?` | Local calendar identifier only; never synced to third parties |
| `captureMode` | `CaptureMode` | `.watch, .phone, .pad, .import, .onlineAssistant, .dialer` |
| `originDeviceID` | `DeviceID` | The microphone owner — the authoritative device |
| `startedAt` / `endedAt` | `Date` | Wall clock, display only. **Never used for timeline math.** |
| `canonicalDuration` | `SampleDuration` | Derived from sample counts + reconciled gaps |
| `lifecycleState` | `MeetingState` | See § 3 |
| `policyID` | `PolicyID` | Points at the frozen policy snapshot in force for this meeting |
| `processingMode` | `ProcessingMode` | `.localOnly, .onDevicePreferred, .cloudAllowed` — frozen at Arming |
| `consentRecordID` | `ConsentRecordID?` | Method + timestamp; explicitly not a legal certification |
| `availability` | `Availability` | `.complete, .partial(missing: [SegmentRef]), .recoverable, .failed` |
| `excludedFromMemory` | `Bool` | Keeps it in the library but out of search/retrieval/index |
| `createdAt` / `updatedAt` / `deletedAt` | `Date?` | `deletedAt` non-nil ⇒ soft-deleted |

### Segment

| Field | Type | Notes |
|---|---|---|
| `segmentID` | `SegmentID` | |
| `meetingID` | `MeetingID` | |
| `deviceID` | `DeviceID` | Which device produced it |
| `sequence` | `Int` | Monotonic per device, gapless; a gap means a lost segment and must be surfaced |
| `codec` / `sampleRate` / `channels` / `bitRate` | | Recorded exactly as configured, not assumed |
| `startSample` | `Int64` | Offset from meeting sample zero **for that device** |
| `sampleCount` | `Int64` | Authoritative duration |
| `sha256` | `Data` | Computed after close, before rename |
| `localURL` | `URL?` | Nil once reclaimed |
| `cloudAssetRef` | `String?` | CKAsset record reference |
| `transferState` | `TransferState` | `.local, .queued, .inFlight, .receivedUnverified, .verified, .reclaimed, .failed(reason)` |
| `isRepairedTail` | `Bool` | True if the segment was recovered with a truncated playable boundary |

### TimelineEvent

Append-only log that makes the timeline explainable.

| Field | Type | Notes |
|---|---|---|
| `eventID`, `meetingID`, `deviceID` | | |
| `type` | `TimelineEventType` | `.start, .pause, .resume, .interruptionBegan(cause), .interruptionEnded, .routeChange(from,to), .marker(kind), .levelWarning(kind), .thermal(state), .batteryWarning, .storageWarning, .sealedStop(reason), .stop` |
| `sampleOffset` | `Int64` | Monotonic; the only ordering key that matters |
| `wallClock` | `Date` | Display and cross-device anchoring only |
| `payload` | `JSON` | Type-specific |

### TranscriptTurn

| Field | Type | Notes |
|---|---|---|
| `turnID`, `meetingID` | | |
| `revision` | `Int` | Provisional revisions are negative; canonical starts at 1 |
| `isProvisional` | `Bool` | Provisional text must render visibly differently |
| `speakerClusterID` | `String?` | From diarization |
| `personID` | `PersonID?` | Resolved identity. **Never inferred without evidence.** |
| `tokens` | `[Token]` | `{text, startSample, endSample, confidence, languageTag}` |
| `languageSpans` | `[LanguageSpan]` | Bilingual meetings preserve original-language spans |
| `segmentRefs` | `[SegmentID]` | Which audio backs this turn |
| `editState` | `EditState` | `.machine, .userEdited(revisionOf:), .userConfirmed` |

Word-level timing is mandatory: tap-to-audio, evidence links, and redaction all depend on it.

### NoteBlock

| Field | Type | Notes |
|---|---|---|
| `blockID`, `meetingID`, `authorID` | | |
| `type` | `NoteBlockType` | `.richText, .checklist, .decision, .action, .quote, .question, .code, .table, .sketch, .photo, .linkPreview, .file, .transcriptExcerpt` |
| `content` | `BlockContent` | Text runs, or an ink/photo asset reference |
| `creationRange` | `SampleRange` | Start→end sample offsets during which the block was authored — this is what makes tap-to-replay work |
| `privacy` | `BlockPrivacy` | `.shared, .privateToAuthor` — private is the default for margin notes and is excluded from all shares |
| `mergeState` | `MergeState` | `.standalone, .proposedForRecap(diffID), .mergedIntoRecap(insightID)` |
| `opLog` | `[Operation]` | Ordered operations for conflict-resilient merge |

**AI never mutates a `NoteBlock`.** It may propose a merge, which produces a diff the user approves.

### Insight (summaries and generated content)

| Field | Type | Notes |
|---|---|---|
| `insightID`, `meetingID` | | |
| `layer` | `InsightLayer` | `.flashRecap, .executiveSummary, .detailedNotes, .chapter, .takeaway, .risk, .openQuestion` |
| `text` | `String` | |
| `claimKind` | `ClaimKind` | `.said, .agreed, .aiSuggests` — **these are different things and must never collapse** |
| `evidence` | `[EvidenceSpan]` | Empty ⇒ `claimKind` must be `.aiSuggests` |
| `confidence` | `Double` | |
| `provenance` | `Provenance` | `{modelID, modelVersion, promptVersion, templateID, templateVersion, generatedAt, processingPlane}` |
| `approvalState` | `ApprovalState` | `.draft, .edited, .approved, .locked` — locked blocks survive regeneration untouched |
| `supersedes` | `InsightID?` | Version chain |

### EvidenceSpan

```swift
struct EvidenceSpan: Sendable, Hashable {
    let meetingID: MeetingID
    let turnIDs: [TranscriptTurnID]     // transcript anchor
    let sampleRange: SampleRange        // audio anchor (canonical timeline)
    let quotedText: String              // snapshot, so evidence survives a later transcript edit
    let transcriptRevision: Int         // which revision produced quotedText
}
```

An evidence span must resolve to playable audio and readable transcript **or** be reported as stale. Stale
evidence is shown as such; it never silently disappears.

### Action / Decision

| Field | Action | Decision |
|---|---|---|
| Text | Verb-first, editable, retains original extracted phrase | Decision statement |
| Owner | Participant/contact/member; `.unresolved` if ambiguous | Approver |
| Date | Explicit / inferred (visibly labelled) / absent | Decided-at |
| Status | `Proposed → Confirmed → Sent → InProgress → Done / Dismissed` | `Proposed → Approved → Superseded` |
| Extra | Dependencies, destination, export receipts | Rationale, alternatives considered, `supersedes` |
| Evidence | ≥ 1 span, **required to leave `Proposed`** | ≥ 1 span |
| Audit | Creator, confirmer, edit history, export attempts and responses | Same |

### Supporting entities

`Person` (name, aliases, voice enrollment ref, contact link, workspace scope) · `Workspace` ·
`Policy` (retention, processing scope, announcement requirement, domain/location rules) ·
`ConsentRecord` (method, timestamp, participants acknowledged) ·
`AuditEvent` (actor, action, object, payload hash, result, timestamp) ·
`GlossaryEntry` (term, pronunciation hints, scope, learned-vs-user-entered, inspectable and deletable) ·
`ShareGrant` (recipient, role, scope, expiry, passcode hash, download policy, revocation state) ·
`IntegrationReceipt` (destination, external ID, idempotency key, request hash, response, retry history).

---

## 3. Meeting lifecycle state machine

Implement in `NSPCore` as an explicit type with an exhaustive transition function. Property tests fuzz random
command sequences against the invariants below.

| State | Allowed transitions | Must be durable before entering |
|---|---|---|
| `Ready` | → `Arming` | Meeting ID, device ID, capture mode, storage check |
| `Arming` | → `Recording`, `Failed` | Audio route, permission, **segment 0 header**, consent snapshot, frozen policy |
| `Recording` | → `Paused`, `Finalizing`, `Interrupted` | Segment frames, rolling manifest, markers, health samples |
| `Paused` | → `Recording`, `Finalizing` | Closed segment checksum, pause timestamp + reason |
| `Interrupted` | → `Recording`, `Finalizing`, `Recoverable` | Interruption type, last durable frame, retry state |
| `Finalizing` | → `Processing`, `SavedRaw` | All segments closed + checksummed, duration reconciled, transfer queue sealed |
| `Processing` | → `ReadyForReview`, `PartialFailure` | Transcript revisions, summary job versions, provenance |
| `ReadyForReview` | → `Approved`, `Edited`, `Shared` | User edits, correction memory, action confirmations |
| `Archived` / `Deleted` | → `Restored`, `Purged` | Retention clock, tombstone, deletion receipts |

**Invariants the property tests assert:**

- No transition into `Recording` without a durable open segment.
- `Pause`→`Resume`×N produces N+1 ordered segments and never overwrites a file.
- Total canonical duration == Σ segment sample counts, and gaps are exactly the recorded pause/interruption spans.
- Any crash injected at any point leaves the meeting recoverable with a *disclosed* missing tail — never a
  silently short meeting, never a corrupt manifest.
- Idempotency: replaying any transfer or job message produces no duplicate rows.

---

## 4. On-disk layout (per device)

```
<AppContainer>/Meetings/<meetingID>/
├── manifest.json          current sealed manifest
├── manifest.json.bak      previous sealed manifest (double-buffered)
├── manifest.wal           append-only event log since last seal
├── segments/
│   ├── 000000.m4a         immutable, named by sequence, hash in manifest
│   ├── 000001.m4a
│   └── .tmp-000002.m4a    in-flight; recovery inspects and repairs or discards these
├── ink/                   PencilKit drawing assets, referenced by NoteBlock
├── attachments/           photos, scans, imported files
└── derived/               waveform peaks, chapter thumbnails — regenerable, never authoritative
```

Data Protection class: `.completeUnlessOpen` for files written while the device may be locked (required for
wrist-down recording); `.complete` for the database and everything else. Verify with a locked-device test.

### Manifest format (`manifest.json`)

```jsonc
{
  "version": 1,
  "meetingID": "0190f3...",
  "deviceID": "watch-A1B2",
  "captureMode": "watch",
  "audioFormat": { "codec": "aac-lc", "sampleRate": 16000, "channels": 1, "bitRate": 32000 },
  "createdAt": "2026-08-19T14:02:11Z",
  "sealedAt": "2026-08-19T15:04:52Z",
  "segments": [
    { "sequence": 0, "segmentID": "…", "file": "segments/000000.m4a",
      "startSample": 0, "sampleCount": 960000, "sha256": "…", "closedAt": "…" }
  ],
  "timeline": [
    { "type": "start",  "sampleOffset": 0,       "wallClock": "…" },
    { "type": "marker", "sampleOffset": 4128000, "wallClock": "…", "payload": {"kind": "important"} },
    { "type": "pause",  "sampleOffset": 9600000, "wallClock": "…", "payload": {"reason": "user"} }
  ],
  "health": { "interruptions": 1, "routeChanges": 2, "lowLevelWarnings": 0, "thermalPeak": "fair" },
  "streamSHA256": "…",
  "integrity": { "sealed": true, "repairedTail": false }
}
```

**Write protocol:** append events to `manifest.wal` (fsync each append) → on seal, write `manifest.json.tmp`,
fsync, rename over `manifest.json` after copying the old one to `.bak`, then truncate the WAL. Recovery reads
`manifest.json`, replays `manifest.wal`, and falls back to `.bak` if the primary fails validation.

---

## 5. SQLite schema (GRDB)

Tables mirror the entities above:
`meeting`, `segment`, `timeline_event`, `transcript_turn`, `transcript_token`, `note_block`, `note_operation`,
`insight`, `evidence_span`, `action_item`, `decision`, `person`, `speaker_cluster`, `glossary_entry`,
`policy`, `consent_record`, `share_grant`, `integration_receipt`, `audit_event`, `sync_state`, `tombstone`,
`embedding` (vector), and FTS5 virtual tables `fts_transcript`, `fts_notes`, `fts_insight`.

Conventions:
- Migrations are numbered, append-only, and reversible: `Migrations/001_initial.swift`, `002_…`. Never edit a
  shipped migration.
- Every table has `created_at`, `updated_at`, `revision` (integer, bumped on write), and where syncable,
  `cloud_record_change_tag`.
- Foreign keys on, WAL mode on, `synchronous = FULL` on the capture device during an active recording.
- FTS triggers exclude any meeting where `excluded_from_memory = 1` or `deleted_at IS NOT NULL`.
- The `embedding` table and any retrieval query **must join through the access filter** — authorization before
  retrieval, never after generation.

---

## 6. CloudKit mapping

| Local | CloudKit |
|---|---|
| Workspace | Custom record zone `ws-<workspaceID>` in the **private** database |
| Meeting | `CD_Meeting` record; sensitive fields (title, notes text) use encrypted fields |
| Segment | `CD_Segment` record + `CKAsset` for the audio file; asset dedupe by `sha256` |
| TranscriptTurn | `CD_TranscriptTurn`, batched; large transcripts as a compressed `CKAsset` with an index record |
| NoteBlock | `CD_NoteBlock` + ink/photo `CKAsset` |
| Insight / Action / Decision | One record type each |
| ShareGrant | CloudKit sharing (`CKShare`) for Apple-native recipients; service links handled outside CloudKit |

Sync rules:
- Change tokens per zone; incremental fetch; subscription-driven push.
- Metadata merges field-by-field using `revision` vectors; note blocks merge by operation log.
- Assets are immutable and content-addressed — a duplicate upload collapses to the existing asset.
- A meeting is usable before all assets arrive: show `Partial` with the exact missing segments and the device
  that last held them.
- Surface iCloud quota, signed-out, and encrypted-data-reset conditions as explicit, actionable states.
- `ProcessingMode == .localOnly` ⇒ **no CloudKit writes at all** for that meeting, including metadata.

---

## 7. Export schema

Every export is a deterministic function of the meeting package, versioned as `exportSchemaVersion`.

| Format | Contents |
|---|---|
| Markdown / plain text | Recap layers, notes, actions, decisions, optional transcript |
| PDF / DOCX | Formatted recap with evidence footnotes |
| SRT / VTT | Captions from canonical transcript |
| JSON | Full package per this schema, including provenance and evidence |
| CSV | Actions and decisions with owners, dates, status, evidence references |
| M4A | Concatenated canonical audio (redactions applied where requested) |
| ZIP evidence bundle | JSON + audio + attachments + redaction certificate + audit excerpt |

Redacted exports remove both the text and the corresponding audio interval, and may include a redaction
certificate. The share preview must enumerate exactly what leaves the workspace — it is generated from the same
code path as the export itself, never described separately.
