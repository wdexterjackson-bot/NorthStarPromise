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

The Library holds four kinds of top-level container: **Meeting**, **BrainDump**, **Note**, and **Project**
(a grouping of meetings). A Meeting, a BrainDump, and a standalone Note are three genuinely separate tracks —
not one entity with a flag. A BrainDump is a recording that is explicitly **not** a meeting (no attendees, no
calendar linkage, no single project); a Note is a subcomponent of a meeting **or** a standalone component, and
is never a meeting itself even once it carries a recording. Today's AI processing pipeline
(`IntelligenceCoordinator`) only runs against Meetings — a BrainDump/Note is captured durably but not yet
transcribed or summarized; that's tracked as `NSP-154`, not silently deferred.

All three still share one durable capture pipeline — `MeetingContainer` (on-disk layout), `CaptureEngine`/
`Segmenter` (recording), and the polymorphic `Segment`/`TranscriptTurn`/`NoteBlock`/`TimelineEvent` tables below
— rather than three parallel copies of that machinery. What makes each an independent top-level entity, not a
disguised Meeting, is that each has its own table, its own id space, and its own lifecycle — never a shared row
with a "kind" column.

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
| `colorSlot` | `Int` | 0–5, chosen at creation via `AddAgendaItemFormView`'s color picker — a Thread's own color wins over this when the meeting has one (`PadAgendaRowView.railColor`) |
| `kind` | `MeetingKind` | `.recorded, .notesOnly` — `.notesOnly` is a `.ready`-lifecycle shell with no audio expected until an import happens. A third case, `.reminder`, existed briefly and was collapsed into a plain freestanding `Action` 2026-08-22 ("The Spine" recommendation) since a reminder living as a phantom Meeting never showed up on a Person's page, in Needs You, or in any relationship query |
| `recurrenceRuleID` | `RecurrenceRuleID?` | Set when this meeting is one occurrence (usually the series' first, promoted) of a recurring series — see **RecurrenceRule** below |
| `createdAt` / `updatedAt` / `deletedAt` | `Date?` | `deletedAt` non-nil ⇒ soft-deleted |

A meeting has no `threadID` column of its own — thread membership is many-to-many; see **Thread** below.

### BrainDump

A real, durable audio recording that is explicitly not a meeting — captured through the same pipeline a
Meeting uses, minus everything meeting-only (no attendees, no `calendarEventID`, no thread of its own — its
individual extracted action items/decisions can each join a thread once `NSP-154` lands, but the BrainDump
itself never does).

| Field | Type | Notes |
|---|---|---|
| `brainDumpID` | `BrainDumpID` | UUIDv7 |
| `workspaceID` | `WorkspaceID` | |
| `originDeviceID` | `DeviceID` | |
| `startedAt` / `endedAt` | `Date` / `Date?` | |
| `canonicalDuration` | `SampleDuration` | |
| `lifecycleState` | `MeetingState` | Reuses `Meeting`'s lifecycle enum — the states involved (arming, recording, processing…) describe *capturing audio*, not being a meeting |
| `policyID` / `processingMode` | | Same rules as `Meeting`; `processingMode` frozen at Arming (I5) |
| `consentRecordID` | `ConsentRecordID?` | |
| `createdAt` / `updatedAt` / `deletedAt` | | |

### Note

The lightest of the three — audio is genuinely optional. A standalone Note starts as text/ink only;
`originDeviceID`/`consentRecordID` stay `nil` until (if ever) the user attaches a recording, at which point
they're set exactly like a Meeting's are.

| Field | Type | Notes |
|---|---|---|
| `noteID` | `NoteID` | UUIDv7 |
| `workspaceID` | `WorkspaceID` | |
| `title` | `String` | User-set; no calendar linkage |
| `originDeviceID` | `DeviceID?` | `nil` until a recording is attached |
| `consentRecordID` | `ConsentRecordID?` | `nil` until a recording is attached |
| `startedAt` / `endedAt` | `Date` / `Date?` | |
| `canonicalDuration` | `SampleDuration` | `.zero` (sample rate 1, not 0 — see § 5's precondition note) until a recording exists |
| `lifecycleState` | `MeetingState` | Same reuse as `BrainDump` |
| `policyID` / `processingMode` | | |
| `createdAt` / `updatedAt` / `deletedAt` | | |

### ScheduledRecording

A pre-scheduled recording (manual or calendar-imported) with a mandatory Start/Skip local notification —
docs/07 § 2.1. Not a `Meeting` until Start is tapped; `meetingID` is set at that point and the schedule's own
row is kept for history (`.started`/`.completed`), not deleted.

| Field | Type | Notes |
|---|---|---|
| `scheduledRecordingID` | `ScheduledRecordingID` | |
| `workspaceID` | `WorkspaceID` | |
| `title` / `scheduledStart` / `scheduledStop` | `String` / `Date` / `Date` | Display/scheduling metadata only — never timeline math |
| `status` | `ScheduledRecordingStatus` | `.pending, .notified, .started, .missed, .completed, .skipped, .cancelled` |
| `alertStyle` | `ScheduledRecordingAlertStyle` | `.sound, .vibrateOnly, .silent` |
| `notifyLeadTime` | `TimeInterval` | Seconds before `scheduledStart` the reminder fires; `0` = at start time |
| `calendarEventID` | `String?` | Set only when created via calendar import |
| `meetingID` | `MeetingID?` | Set once Start promotes this into a real `Meeting` |
| `projectID` | `ProjectID?` | Applied to the resulting `Meeting` at promotion |
| `colorSlot` | `Int` | Same 0–5 rail-color slot `Meeting.colorSlot` uses |
| `recurrenceRuleID` | `RecurrenceRuleID?` | Set when this item is one occurrence of a recurring series |
| `createdAt` / `updatedAt` | | |

### RecurrenceRule / RecurrenceException

Added 2026-08-22 for Outlook-parity recurring events on `Meeting`/`ScheduledRecording` (docs/09, NSP-157–160).
The standard rule-plus-exceptions model every real calendar app uses — future occurrences are never
materialized as real rows; a pure, `Clock`-free `RecurrenceExpander.occurrences(of:seriesStart:in:calendar:)`
expands a rule into concrete dates within a bounded display window only. A `Meeting`/`ScheduledRecording` only
becomes real the moment an occurrence is actually started, exactly like a non-recurring item.

```swift
enum RecurrenceFrequency: Sendable, Hashable, Codable {
    case daily(interval: Int, everyWeekday: Bool = false)
    case weekly(interval: Int, days: Set<Weekday>)
    case monthly(interval: Int, pattern: MonthlyPattern)   // .dayOfMonth(N) or .relativeWeekday(ordinal, weekday)
    case yearly(month: Int, pattern: MonthlyPattern)
}
enum RecurrenceEnd: Sendable, Hashable, Codable {
    case never
    case afterOccurrences(Int)
    case onDate(Date)
}
```

| Field | RecurrenceRule | RecurrenceException |
|---|---|---|
| ID | `recurrenceRuleID` | `recurrenceExceptionID` |
| Links to | `workspaceID` | `recurrenceRuleID` (cascade delete) |
| Pattern | `frequency: RecurrenceFrequency`, `end: RecurrenceEnd` | `originalOccurrenceDate: Date` — the virtual occurrence this exception replaces |
| Kind | — | `.modified` (paired with an `overrideMeetingID`/`overrideScheduledRecordingID`) or `.cancelled` (just excludes the date) |
| Scope edit semantics | "This occurrence" writes an exception; "This and following" truncates this rule's `end` (does **not** auto-create a continuation rule — a disclosed v1 simplification); "All occurrences" edits the rule/master row directly | — |

### Segment / TranscriptTurn / NoteBlock / TimelineEvent — polymorphic ownership

These four tables no longer carry a hard `meetingID` foreign key. Each instead carries an **owner**, encoded
as two columns — an id column (still named `meeting_id` for existing-column continuity) and an `owner_kind`
column (`'meeting'`, `'brainDump'`, or `'note'`) — mirrored in Swift as one shared type:

```swift
enum ContentOwnerRef: Sendable, Hashable, Codable {
    case meeting(MeetingID)
    case brainDump(BrainDumpID)
    case note(NoteID)
}
```

A single column can't hold a real SQL foreign key to three different parent tables, so these four tables
**deliberately have no FK on their owner column** — integrity is enforced at the app layer instead: each
owner's own delete path (`MeetingRepository.delete`, `BrainDumpRepository.delete`, `NoteRepository.delete`)
explicitly deletes its owned segments/transcript turns/note blocks/timeline events first
(`OwnedContentCleanup`), rather than relying on `ON DELETE CASCADE`. Every other child table these four have —
`transcript_token`, `note_operation`, `evidence_span`, etc. — is unaffected and still cascades normally off
`turn_id`/`block_id`.

**Follow-up work, not silently dropped:** FTS indexing (`fts_notes`) and full-text search still only run
against `owner_kind = 'meeting'` rows — a BrainDump/Note note block is stored durably but not yet searchable.
Real indexing for those two owner kinds is tracked, not assumed away.

#### Segment

| Field | Type | Notes |
|---|---|---|
| `segmentID` | `SegmentID` | |
| `owner` | `ContentOwnerRef` | Which Meeting/BrainDump/Note this segment belongs to |
| `deviceID` | `DeviceID` | Which device produced it |
| `sequence` | `Int` | Monotonic per device, gapless; a gap means a lost segment and must be surfaced |
| `codec` / `sampleRate` / `channels` / `bitRate` | | Recorded exactly as configured, not assumed |
| `startSample` | `Int64` | Offset from the owner's sample zero **for that device** |
| `sampleCount` | `Int64` | Authoritative duration |
| `sha256` | `Data` | Computed after close, before rename |
| `localURL` | `URL?` | Nil once reclaimed |
| `cloudAssetRef` | `String?` | CKAsset record reference |
| `transferState` | `TransferState` | `.local, .queued, .inFlight, .receivedUnverified, .verified, .reclaimed, .failed(reason)` |
| `isRepairedTail` | `Bool` | True if the segment was recovered with a truncated playable boundary |

#### TimelineEvent

Append-only log that makes the timeline explainable.

| Field | Type | Notes |
|---|---|---|
| `eventID`, `owner`, `deviceID` | | |
| `type` | `TimelineEventType` | `.start, .pause, .resume, .interruptionBegan(cause), .interruptionEnded, .routeChange(from,to), .marker(kind), .levelWarning(kind), .thermal(state), .batteryWarning, .storageWarning, .sealedStop(reason), .stop` |
| `sampleOffset` | `Int64` | Monotonic; the only ordering key that matters |
| `wallClock` | `Date` | Display and cross-device anchoring only |
| `payload` | `JSON` | Type-specific |

#### TranscriptTurn

| Field | Type | Notes |
|---|---|---|
| `turnID`, `owner` | | |
| `revision` | `Int` | Provisional revisions are negative; canonical starts at 1 |
| `isProvisional` | `Bool` | Provisional text must render visibly differently |
| `speakerClusterID` | `String?` | From diarization |
| `personID` | `PersonID?` | Resolved identity. **Never inferred without evidence.** |
| `tokens` | `[Token]` | `{text, startSample, endSample, confidence, languageTag}` |
| `languageSpans` | `[LanguageSpan]` | Bilingual meetings preserve original-language spans |
| `segmentRefs` | `[SegmentID]` | Which audio backs this turn |
| `editState` | `EditState` | `.machine, .userEdited(revisionOf:), .userConfirmed` |

Word-level timing is mandatory: tap-to-audio, evidence links, and redaction all depend on it.

#### NoteBlock

| Field | Type | Notes |
|---|---|---|
| `blockID`, `owner`, `authorID` | | |
| `type` | `NoteBlockType` | `.richText, .checklist, .decision, .action, .quote, .question, .code, .table, .sketch, .photo, .linkPreview, .file, .transcriptExcerpt` |
| `content` | `BlockContent` | Text runs, or an ink/photo asset reference |
| `creationRange` | `SampleRange` | Start→end sample offsets during which the block was authored — this is what makes tap-to-replay work |
| `privacy` | `BlockPrivacy` | `.shared, .privateToAuthor` — private is the default for margin notes and is excluded from all shares |
| `mergeState` | `MergeState` | `.standalone, .proposedForRecap(diffID), .mergedIntoRecap(insightID)` |
| `opLog` | `[Operation]` | Ordered operations for conflict-resilient merge |

**AI never mutates a `NoteBlock`.** It may propose a merge, which produces a diff the user approves.

### Thread

A storyline that floats in and through several meetings, notes, and action items at once — more than a single
action item, but not itself a meeting or a project. Signing a vendor contract extension might thread through
several 1:1s, a procurement meeting, and vendor emails; none of those containers "is" the thread, they're each
just touched by it.

| Field | Type | Notes |
|---|---|---|
| `threadID` | `NSPThreadID` | |
| `workspaceID` | `WorkspaceID` | |
| `title` / `threadDescription` | `String` / `String?` | |
| `kind` | `ThreadKind` | |
| `colorSlot` | `Int` | 0–5, computed once at creation, never recomputed |
| `status` | `NSPThreadStatus` | `.onTrack, .decisionDue, .atRisk, .dormant, .closed` — `.closed` is the only user-set value; every other value is recomputed from open actions/decisions whenever a thread is loaded |
| `lastTouchedAt` | `Date` | |
| `createdAt` / `updatedAt` | | |

A meeting joins **zero, one, or several** threads at once via the `meeting_thread` join table (§ 5) — not a
single `threadID` column on `Meeting`. Independent of `Project` membership; a meeting may have both, either, or
neither. `Action`/`Decision` can each carry their own `threadID` too, independent of whichever thread(s) their
meeting belongs to (see below) — a freestanding action with no meeting at all can still thread.

A Thread also tracks **people** directly, independent of meeting attendance — the `thread_participant` join
table (`ThreadID`↔`PersonID`, added 2026-08-22, People plan phase 2), set via `ThreadDetailView`'s "Edit
People." `Project` has the identical `project_person` join for the same reason. Both are read through
`RelationshipGraph` (docs/04) rather than a bespoke per-screen query.

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
| `workspaceID` | Real column — an Action's own workspace, not derived via a meeting join (needed so a freestanding action still surfaces in workspace-wide queries) | Derived via its (always-required) meeting's `workspaceID` |
| `meetingID` | **Optional.** `nil` ⇒ a freestanding action — one the user can act on themselves, not tied to a specific recording (the user's own distinction: an action item is something they control directly, unlike a `Thread`, which needs coordinated effort across meetings/emails/people) | Required — a decision is always made *in* a specific meeting, never freestanding |
| `threadID` | `NSPThreadID?` — independent of `meetingID`: a freestanding action can carry a thread with no meeting at all, and a meeting-tied action can belong to a thread its meeting doesn't (or vice versa) | `NSPThreadID?` — same independence, but always alongside a real `meetingID` |
| `counterpartyID` | `PersonID?` — who this commitment is with, so People's "what do I owe this person" is a real filtered query, not a guess from meeting attendees | — |
| Text | Verb-first, editable, retains original extracted phrase | Decision statement |
| Owner | Participant/contact/member; `.unresolved` if ambiguous | Approver |
| Date | Explicit / inferred (visibly labelled) / absent | Decided-at |
| Status | `Proposed → Confirmed → Sent → InProgress → Done / Dismissed` | `Proposed → Approved → Superseded` |
| Extra | Dependencies, destination, export receipts | Rationale, alternatives considered, `supersedes` |
| Evidence | ≥ 1 span, **required to leave `Proposed`** — a freestanding action typically has none: a span needs a real meeting's transcript to quote from (I4), which it doesn't have | ≥ 1 span |
| Audit | Creator, confirmer, edit history, export attempts and responses | Same |

### Supporting entities

`Person` (name, aliases, voice enrollment ref, contact link, workspace scope, plus two 2026-08-22 additions:
`tags: [String]` — freeform relationship labels ("Direct report", "Board", "Vendor"), deliberately not an enum
since an executive's roster doesn't fit one fixed taxonomy, and `notes: String?` — freeform context the user
writes directly, never AI-generated) · `Workspace` ·
`Policy` (retention, processing scope, announcement requirement, domain/location rules) ·
`ConsentRecord` (method, timestamp, participants acknowledged) ·
`AuditEvent` (actor, action, object, payload hash, result, timestamp) ·
`GlossaryEntry` (term, pronunciation hints, scope, learned-vs-user-entered, inspectable and deletable) ·
`ShareGrant` (recipient, role, scope, expiry, passcode hash, download policy, revocation state) ·
`IntegrationReceipt` (destination, external ID, idempotency key, request hash, response, retry history).

---

## 3. Meeting lifecycle state machine

`MeetingState` — despite the name, this is the lifecycle enum `BrainDump` and `Note` reuse too (§ 2): the
states below describe the process of *capturing audio*, not being a meeting specifically, so a second parallel
enum would just be the same cases twice. Implement in `NSPCore` as an explicit type with an exhaustive
transition function. Property tests fuzz random command sequences against the invariants below.

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
<AppContainer>/BrainDumps/<brainDumpID>/
<AppContainer>/Notes/<noteID>/
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

One root folder per owner kind — `Meetings/`, `BrainDumps/`, `Notes/` — never merged into one, so a folder
under `Meetings/` always resolves to a real `meeting` row. Every owner kind gets the identical internal layout
above; `MeetingContainer` (the type that computes these paths) is named for the common case but is the same
type for all three, keyed by the same `ContentOwnerRef` § 2 describes.

Data Protection class: `.completeUnlessOpen` for files written while the device may be locked (required for
wrist-down recording); `.complete` for the database and everything else. Verify with a locked-device test.

### Manifest format (`manifest.json`)

```jsonc
{
  "version": 1,
  "owner": { "meeting": "0190f3..." },
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
`meeting`, `brain_dump`, `note`, `thread`, `meeting_thread` (join table — a meeting may belong to several
threads at once), `project`, `meeting_project` (join table), `segment`, `timeline_event`, `transcript_turn`,
`transcript_token`, `note_block`, `note_operation`, `insight`, `evidence_span`, `action_item`, `decision`,
`person`, `speaker_cluster`, `glossary_entry`, `policy`, `consent_record`, `share_grant`,
`integration_receipt`, `audit_event`, `sync_state`, `tombstone`, `embedding` (vector), and FTS5 virtual tables
`fts_transcript`, `fts_notes`, `fts_insight`.

`segment`, `timeline_event`, `transcript_turn`, and `note_block` each carry a `meeting_id` column (legacy
name, holds any owner's id) plus an `owner_kind` column (`'meeting'` / `'brainDump'` / `'note'`) instead of a
real foreign key — § 2's `ContentOwnerRef` note explains why. `action_item.meeting_id` is nullable (a
freestanding action); `action_item.workspace_id` is a real column, not derived through the meeting join.
`SampleDuration.init(sampleCount:sampleRate:)` has a hard `precondition(sampleRate > 0)` — a zero-duration
value is always `SampleDuration.zero` (`sampleRate: 1`), never a literal `0`; a `BrainDump`/`Note` row with no
recording yet must use that same default, not a raw `0`.

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

`BrainDump`, `Note`, and `Thread` have no row here yet, and the `Insight`/`Action`/`Decision` row above is
aspirational, not yet implemented — `NSPSync`'s zones and `ZoneSyncEngine` only actually sync `Meeting`/
`Segment`/`TranscriptTurn` today (`CloudKitRecordMapper`'s own doc comment). `Segment`/`TranscriptTurn` sync
only ever carries a `Meeting` owner so far, though it already encodes the real `ownerKind` so wiring up
`BrainDump`/`Note` sync later is additive, not another migration of already-synced records.

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
