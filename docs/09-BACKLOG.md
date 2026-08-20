# 09 — Ticket Backlog

Work through this in order. Each ticket names its module, its dependencies, and acceptance criteria that are
verifiable rather than descriptive. Branch as `nsp-014-segment-rotation`; commit as `NSP-014: …`.

**Three ID namespaces — do not confuse them:**

| Namespace | Meaning | Where defined |
|---|---|---|
| `NSP-nnn` | A unit of work. This document. | Here |
| `CAP-nnn`, `TRN-nnn`, `SUM-nnn`, `NOT-nnn`, `ACT-nnn`, `SHR-nnn`, `SYN-nnn`, `PRV-nnn`, `DEL-nnn`, `INT-nnn`, `AI-nnn` | A **functional requirement** with an acceptance condition. | Appendix A below |
| `TC-CAP-nnn`, `TC-XFER-nnn` | A **test case**. | `docs/03` § 13 |
| `SEC-nnn`, `POL-nnn`, `CON-nnn`, `RED-nnn`, and the extended `PRV-/DEL-/SHR-/SYN-/INT-` numbers beyond those in Appendix A | **Privacy and security acceptance checks**, an extension of the requirement namespace. | `docs/06` § 12 |

Every ticket below carries the requirement(s) it satisfies. A requirement is closed only when all its tickets
are done **and** its acceptance condition passes on hardware.

---

# M0 — Foundations and spikes

| ID | Title | Module | Depends | Acceptance |
|---|---|---|---|---|
| NSP-001 | Repo skeleton, XcodeGen, Makefile | repo | — | `make bootstrap && make gen && make test` succeeds on a clean machine; all 11 packages exist and compile; `App/` targets build empty shells for iOS, iPadOS, watchOS. |
| NSP-002 | ⚠️ **Spike:** watchOS background recording | spike | NSP-001 | Physical-device report covering ≥2 Watch generations: 60- and 120-min recording wrist-down, screen off, backgrounded, phone powered off. Records which audio-session + recording-intent + ongoing-presentation combination survives, process suspension/termination behaviour, battery delta, and thermal state. Output: `docs/reports/hardware-<date>.md` + a recommended minimum OS floor. |
| NSP-003 | ⚠️ **Spike:** codec and segment length | spike | NSP-002 | Matrix of AAC-LC/HE-AAC × 16/24 kHz × 30/45/60 s measured for battery, bytes/min, transfer overhead, ASR WER delta, and worst-case repair loss window. Output: one recommended default with the tradeoff written down. |
| NSP-004 | ⚠️ **Spike:** WatchConnectivity behaviour | spike | NSP-001 | Measured `transferFile` latency distribution, queue behaviour after 24 h disconnection, delivery ordering, size limits, throttling, and unpair/re-pair semantics. |
| NSP-005 | ⚠️ **Spike:** on-device ASR and summarization availability | spike | NSP-001 | Availability by OS version / device class / language, quality sample, thermal behaviour over a 60-min meeting, and the degradation plan when unavailable. |
| NSP-006 | `NSPCore` domain types | NSPCore | NSP-001 | All entities in `docs/02` § 2 exist as `Sendable` value types with typed IDs; zero imports beyond Foundation; 100 % of enums exhaustively switched in tests. |
| NSP-007 | Meeting lifecycle state machine | NSPCore | NSP-006 | Exhaustive transition function; property test fuzzes 10 000 random command sequences and asserts every invariant in `docs/02` § 3; illegal transitions are unrepresentable or throw a typed error. |
| NSP-008 | CI pipeline + invariant gate scaffolding | repo | NSP-001 | `make check` runs in CI on every PR; the I1–I7 gate tests exist and fail-by-absence, so they turn green as subsystems land. |
| NSP-009 | `NSPTestSupport` foundation | NSPTestSupport | NSP-006 | Deterministic `Clock`, golden tone-burst audio generator, fixture meeting builder, and fakes for every protocol declared so far. |
| NSP-010 | Decision write-up from spikes | docs | NSP-002…005 | `docs/00` § 8 updated with locked minimum OS, codec, segment length, and supported-device matrix. Any spec contradicted by a spike is edited in the same PR. |

**M0 exit:** no M1 ticket may begin while an assumption in `docs/00` § 8 is still marked "working default".

---

# M1 — Vertical slice

**Status as of 2026-08-20:** real work so far did not follow this epic order — it went iPhone-first and
breadth-first instead of the intended "thin slice across all three devices" shape. Built and real: Epic A
mostly (persistence/policy foundation), Epic D's iPhone half (`NSP-037`/`NSP-038`-equivalent Today/Library/
Meeting-detail/Notes/Audio, plus more than the slice specified — a full Actions dashboard and calendar-event
creation, both nominally M5/later work, already exist on iPhone). **Not started:** all of Epic B (Watch
capture — the Watch app is still the placeholder from `NSP-001`), Epic C (transfer), Epic E (transcription/
summary — `NSPIntelligence` is protocol-only), most of Epic F (`NSP-047` typed notes is real; `NSP-048`–`051`
are not — actions on iPhone today are user-created, not AI-extracted from anything). iPad (`NSP-039`'s intended
scope, "read-only meeting view") instead got a first interactive shell — see `docs/09-BACKLOG.md` M4's status
note below, which is more advanced than `NSP-039` but in a different shape than this ticket describes. Don't
trust individual ticket checkmarks against this table without verifying against the actual code — none of these
tickets were formally closed as work landed; this note is the accurate high-level picture.

## Epic A — Persistence and policy foundation

| ID | Title | Module | Depends | Acceptance | Req |
|---|---|---|---|---|---|
| NSP-011 | GRDB stack + migration 001 | NSPPersistence | NSP-006 | Schema v1 per `docs/02` § 5; FK on, WAL on; migration is reversible; in-memory store available for tests. | — |
| NSP-012 | Repositories for Meeting/Segment/TimelineEvent | NSPPersistence | NSP-011 | Protocol-fronted; CRUD + query paths covered; no `try?` anywhere in the module. | — |
| NSP-013 | Container layout + Data Protection classes | NSPPersistence | NSP-011 | Directory layout matches `docs/02` § 4; a locked-device test proves segment files remain writable under `.completeUnlessOpen` and the DB is `.complete`. | PRV-001 |
| NSP-014 | Manifest writer with WAL and double buffering | NSPMedia | NSP-013 | Append + fsync per event; seal writes `.tmp` → fsync → `.bak` rotation → rename; a kill injected at any of the 40 instrumented points leaves a manifest that validates. | CAP-003 |
| NSP-015 | `NSPPolicy` core + `ProcessingMode` | NSPPolicy | NSP-006 | Mode frozen at Arming; `Policy` snapshot persisted per meeting; mode cannot be mutated after Arming by any API path (test). | PRV-001 |
| NSP-016 | `NetworkGate` and `ProcessingGrant` | NSPPolicy | NSP-015 | Every content-bearing egress requires a grant; `.localOnly` yields no grant; every grant issuance writes an `AuditEvent`. | PRV-001 |
| NSP-017 | Egress architecture lint | NSPPolicy | NSP-016 | Build fails if `URLSession` or any CloudKit type (`CKContainer`, `CKDatabase`) is imported outside the allowlisted modules; `LocalOnly` build configuration compiles out `NSPBackendClient` entirely. | PRV-001 |

## Epic B — Watch capture

| ID | Title | Module | Depends | Acceptance | Req |
|---|---|---|---|---|---|
| NSP-018 | Audio session configuration (watchOS) | NSPMedia | NSP-002 | Session configured per spike findings; activation failures produce typed errors; route and interruption notifications observed. | CAP-001 |
| NSP-019 | `CaptureEngine` actor | NSPMedia | NSP-018 | Actor-isolated; audio tap writes through a lock-free ring buffer; no `await` and no `MainActor` on the audio path (enforced by a source-scan test). | CAP-001 |
| NSP-020 | Segmenter and rotation policy | NSPMedia | NSP-019, NSP-014 | Rotates on interval and on pause/interrupt/stop/thermal/battery/storage; atomic close protocol exactly as in `docs/03` § 3; `TC-CAP-005` green. | CAP-003 |
| NSP-021 | Integrity: per-segment and stream SHA-256 | NSPMedia | NSP-020 | Hash computed after close, before rename; recorded in manifest; mismatch is a typed, surfaced error, never a silent skip. | CAP-003 |
| NSP-022 | Durable-acknowledgement start path | NSPMedia, Watch | NSP-020, NSP-015 | `TC-CAP-002` green: a filesystem spy fails the test if `Recording` is observed before segment 0's header is fsync'd. Start → ack ≤ 2 s p95 on hardware. | CAP-001 |
| NSP-023 | Pause / resume / stop | NSPMedia | NSP-020 | Pause closes the segment and records a gap; resume opens the next; stop seals the manifest; `TC-CAP-005` green. | CAP-002 |
| NSP-024 | Markers from Watch | NSPMedia | NSP-023 | Marker lands at a sample-aligned offset; haptic + visual confirmation; marker survives crash before stop. | CAP-005 |
| NSP-025 | Timeline reconciler (sample math) | NSPMedia | NSP-023 | Canonical duration = Σ samples + Σ recorded gaps; `TC-CAP-006` golden-tone drift < 250 ms at 60 min; `TC-CAP-013` proves no `Date()`/`Timer` in timeline code. | CAP-003 |
| NSP-026 | Watch UI: Ready / Recording / Paused / Finalizing | Watch, NSPDesignSystem | NSP-022 | States match `docs/07` § 3; Stop requires a short confirmation and no hidden gesture; every state announced to VoiceOver; status never colour-only. | CAP-001 |
| NSP-027 | Watch local store | NSPPersistence (Watch) | NSP-011 | Minimal file-backed meeting index on Watch; survives app termination; no dependency on the phone. | CAP-001 |

## Epic C — Transfer

| ID | Title | Module | Depends | Acceptance | Req |
|---|---|---|---|---|---|
| NSP-028 | `WCSession` lifecycle and state channel | NSPTransfer | NSP-004 | Activation, reachability, and state messages per the contract table in `docs/03` § 8; state messages never gate capture. | CAP-004 |
| NSP-029 | Transfer outbox with idempotency keys | NSPTransfer | NSP-028, NSP-021 | Key = `segmentID`; `TC-XFER-001` green (3× out-of-order delivery ⇒ exactly one row, one receipt). | CAP-003 |
| NSP-030 | Receiver: durable move + hash verify + receipt | NSPTransfer (Phone) | NSP-029 | File moved into the container synchronously before acknowledgement; `TC-XFER-003` green (hash mismatch quarantines, does not insert, re-enqueues once). | CAP-003 |
| NSP-031 | Transfer state machine + retry/backoff | NSPTransfer | NSP-030 | `TransferState` transitions per `docs/02` § 2; `TC-XFER-004` green (150 segments queued over 24 h all deliver, in order, zero duplicates). | CAP-003 |
| NSP-032 | Cross-device active-state mirroring | NSPTransfer | NSP-028 | `CAP-004`: no device ever displays a false recording/stopped state; the source device is always labelled. | CAP-004 |

## Epic D — iPhone hub, sync, and playback

| ID | Title | Module | Depends | Acceptance | Req |
|---|---|---|---|---|---|
| NSP-033 | Playback engine across segments | NSPMedia | NSP-025 | Gapless playback, seek by canonical time ≤ 300 ms for cached segments, rates 0.5×–3×. | TRN-001 |
| NSP-034 | CloudKit zone bootstrap + record mapping | NSPSync | NSP-011, NSP-016 | Private DB, custom zone per workspace; Meeting/Segment/TranscriptTurn records; `.localOnly` meetings produce **zero** CloudKit writes (test). | SYN-001 |
| NSP-035 | `CKAsset` upload with content-addressed dedupe | NSPSync | NSP-034 | Duplicate upload of the same hash collapses; upload resumes after interruption. | SYN-001 |
| NSP-036 | Change-token sync loop + partial availability | NSPSync | NSP-034 | Meeting opens as `.partial` listing the exact missing segments and the device that last held them. | SYN-001 |
| NSP-037 | iPhone Today + active session + Live Activity | Phone | NSP-032 | Live Activity reflects the true source device; tapping it opens the session; recording indicator always visible. | CAP-004 |
| NSP-038 | iPhone meeting detail with tabs | Phone | NSP-033 | Overview / Transcript / Audio / Actions / Notes / Processing log per `docs/07` § 4; opens from local store ≤ 1 s p95. | — |
| NSP-039 | iPad read-only meeting view | Phone (iPad idiom) | NSP-036 | Shows "Recording on Watch; live view unavailable until device or cloud connection", then progressively fills. Never implies a direct Watch link. | SYN-001 |

## Epic E — Transcription and summary (thin)

| ID | Title | Module | Depends | Acceptance | Req |
|---|---|---|---|---|---|
| NSP-040 | Intelligence protocol surface + mocks | NSPIntelligence | NSP-006 | All protocols in `docs/04` § 2 declared; every egress-capable method takes a `ProcessingGrant`; a mock exists for each. | — |
| NSP-041 | On-device transcription (single language) | NSPIntelligence | NSP-040, NSP-005 | Word-level timings persisted; capability-detected; unavailable ⇒ explicit "transcript unavailable on this device" state, never a silent cloud fallback. | TRN-001 |
| NSP-042 | Transcript UI + tap-to-audio | Phone | NSP-041, NSP-033 | Tap any word or turn seeks to the correct audio; provisional text renders visibly differently; revisions do not jump scroll position. | TRN-001 |
| NSP-043 | FTS5 transcript search | NSPPersistence | NSP-041 | Search returns ranked results with jump-to-audio; meetings with `excludedFromMemory` or `deletedAt` are excluded by trigger, not by query-time filtering. | — |
| NSP-044 | `EvidenceSpan` resolver | NSPIntelligence | NSP-041 | Every span resolves to playable audio + readable transcript, or is reported stale; stale evidence is surfaced, never dropped. | SUM-001 |
| NSP-045 | Flash Recap + Executive Summary generation | NSPIntelligence | NSP-044 | Model emits spans, not prose citations; every bullet carries ≥1 span or is labelled `.aiSuggests`; provenance recorded. | SUM-001 |
| NSP-046 | Entailment check + claim downgrade | NSPIntelligence | NSP-045 | A claim whose cited span does not support it is downgraded to `.aiSuggests`; a synthetic hallucination fixture is caught by the test. | SUM-001 |

## Epic F — Notes, actions, export

| ID | Title | Module | Depends | Acceptance | Req |
|---|---|---|---|---|---|
| NSP-047 | Typed note blocks with `creationRange` | NSPPersistence, Phone | NSP-011 | Blocks record the sample range during which they were authored; private blocks default to excluded from shares. | NOT-001 |
| NSP-048 | Action extraction into `Proposed` | NSPActions | NSP-045 | Proposed actions carry evidence; unresolved owner/date are visibly labelled as inferred or absent. | ACT-001, SUM-001 |
| NSP-049 | Action confirmation gate | NSPActions | NSP-048 | An action cannot leave `Proposed` without evidence and explicit human confirmation of the payload (I6 test). | ACT-001 |
| NSP-050 | Reminders export via idempotent outbox | NSPActions | NSP-049 | Key = `actionID + destination + revision`; replaying the export creates no duplicate; receipt and `AuditEvent` stored. | INT-002 |
| NSP-051 | Markdown + JSON export with share preview | NSPActions, Phone | NSP-045, NSP-047 | Preview is generated by the same code path as the export; private blocks absent by default; export is deterministic for a fixed package. | SHR-001 |
| NSP-052 | Local-only network audit test | NSPPolicy | NSP-016, NSP-034, NSP-041 | App runs the full slice in `.localOnly` behind a recording proxy; assertion: zero meeting-content bytes egress, including analytics and crash reporting. | PRV-001 |

---

# M2 — Capture hardening and recovery

| ID | Title | Module | Acceptance | Req |
|---|---|---|---|---|
| NSP-053 | Fault-injection harness | NSPTestSupport | Injects crash, kill, `ENOSPC`, thermal, permission revocation, WC delay/drop/duplicate, CloudKit errors at seeded points. | CAP-003 |
| NSP-054 | Recovery scan and WAL replay | NSPMedia | `TC-CAP-003` green across 100 random kill offsets; every run ends `.complete` or `.recoverable`, never `.failed`. | CAP-003 |
| NSP-055 | Playable-boundary repair for truncated tails | NSPMedia | `TC-CAP-008` green; `isRepairedTail == true`; original `.tmp` never mutated. | CAP-003 |
| NSP-056 | Idempotent recovery | NSPMedia | `TC-CAP-004` green: three consecutive recoveries yield byte-identical manifests. | CAP-003 |
| NSP-057 | Preflight: storage, battery, permission, consent | NSPPolicy, Watch | `TC-CAP-012` green: warns are overridable and audited, blocks are not overridable by any API path. | CAP-001 |
| NSP-058 | Remaining-record-time estimation | NSPMedia | Estimate from rolling bitrate and free bytes; conservative; never over-promises by more than 5 %. | CAP-001 |
| NSP-059 | Sealed stop on thermal/battery/storage critical | NSPMedia | `TC-CAP-010` green: playable sealed manifest + `sealedStop(reason)` event + haptic warning + final transfer attempt. | CAP-003 |
| NSP-060 | Health signals without stopping | NSPMedia | `TC-CAP-009` green: silence, clipping, input loss, low level, route change each emit exactly one event and do not stop capture. | CAP-003 |
| NSP-061 | Reclamation policy | NSPTransfer | `TC-XFER-002` green: reclamation only when verified receipt ∧ (cloud policy satisfied ∨ local copy confirmed) ∧ grace elapsed. | CAP-003 |
| NSP-062 | Unpair / re-pair / multi-Watch | NSPTransfer | `TC-XFER-007` green: re-enqueues only unverified segments; deletes nothing on the Watch. | CAP-003 |
| NSP-063 | Microphone-owner lease and arbitration | NSPTransfer, Phone | `TC-XFER-006` green: starting a phone recording during a Watch recording offers the four canonical choices (Keep recording on Watch / Take over on iPhone / Record separately / Cancel) per `docs/03` § 11; never silently switches microphone. | CAP-004 |
| NSP-064 | Route change and interruption handling | NSPMedia | AirPods mid-meeting, incoming call, Siri, Low Power Mode: banner surfaced, segment boundary preserved, cause recorded. | CAP-003 |
| NSP-065 | Live preview channel | NSPTransfer | `TC-XFER-005` green: preview frames never written to `segments/`, never in the manifest, never produce a non-provisional turn. UI labels preview distinctly. | CAP-004 |
| NSP-066 | Import audio/video with provenance | NSPMedia | `TC-CAP-014` green: original timestamp source correctly classified; `startedAt` never fabricated. | — |
| NSP-067 | Watch complication + Smart Stack | Widgets | Shows state + timer while active, quick Record while idle; deep-links via App Intent. | CAP-001 |
| NSP-068 | Lock Screen + Home Screen widgets | Widgets | Start recording within 2 s of tap; state accurate within one refresh cycle. | CAP-001 |
| NSP-069 | Control Center control + Action button | Intents | Recording starts and reaches durable ack; system indicator visible. | CAP-001 |
| NSP-070 | Siri and Shortcuts intents | Intents | "Start a meeting", "Mark this moment", "Stop recording"; each is idempotent. | CAP-005 |
| NSP-071 | Calendar-derived titles | Phone | Title suggested from the current event; sensitive-title setting substitutes "Meeting" on Watch and Lock Screen. | INT-001 |
| NSP-072 | Soak suite | NSPTestSupport | 8-hour import, thousands of segments, week-long transfer queue, run nightly. | — |

---

# M3 — Intelligence depth and cloud plane

**Status as of 2026-08-20:** none of M3 is built — `NSPIntelligence` is still protocol definitions and
fixture-backed mocks only (confirmed by direct source inspection this date), with nothing in `App/Phone`
calling into it. The product-direction request that prompted the `docs/04` § 3.2/3.3 additions (name-in-address
heuristic, closest-device-is-you default, a post-processing "Name Participants" review screen with a
configurable voice-clip length and a Contacts picker) sits entirely on top of `NSP-075`/`NSP-076` — real
diarization has to exist before any of that can be real rather than mocked. Read `docs/04-INTELLIGENCE.md`
§ 3.2/3.3 before starting this milestone; it also documents a hard platform limitation discovered the same
date — EventKit has no public API to add attendees to a calendar event, so "add named participants to the
calendar event" needs a product decision (drop it / hand off an `.ics` file / do it server-side through a real
calendar connector) before any of NSP-125's calendar export work touches attendees.

| ID | Title | Module | Acceptance | Req |
|---|---|---|---|---|
| NSP-073 | Canonical batch transcription pass | NSPIntelligence | Word timings, punctuation, language spans, confidence; supersedes provisional revisions without losing them. | TRN-001 |
| NSP-074 | Alignment job | NSPIntelligence | Provisional words, markers, ink, photos, and summaries all map onto canonical timestamps; drift within budget. | TRN-001 |
| NSP-075 | Diarization + speaker clusters | NSPIntelligence | DER measured against the reference set; clusters stable across the meeting. | TRN-001 |
| NSP-076 | Speaker resolution and naming | NSPIntelligence | Roster, self-voice enrollment, manual labels; names never invented without evidence (test with an unnamed-speaker fixture). | TRN-001 |
| NSP-077 | Rename scopes with preview | Phone | "This turn" / "from here" / "all matching voice", each previewed before commit and undoable. | TRN-002 |
| NSP-078 | Transcript editing with revision history | NSPPersistence | Original preserved; provenance retained; `TRN-002` acceptance met. | TRN-002 |
| NSP-079 | Confidence surfacing and priority flags | Phone | Low-confidence names, numbers, dates, and commitments flagged first; heatmap optional. | TRN-001 |
| NSP-080 | Custom vocabulary and domain packs | NSPIntelligence | Entity accuracy ≥ 98 % after confirmed glossary on the eval set. | TRN-001 |
| NSP-081 | Multilingual and bilingual transcription | NSPIntelligence | Language spans preserved; translation is a separate reversible view; original never replaced. | TRN-003 |
| NSP-082 | Detailed Notes, chapters, takeaways, risks | NSPIntelligence | Each layer per `docs/04` § 5, each bullet evidence-bound. | SUM-001 |
| NSP-083 | Template library | NSPIntelligence | The eleven templates in `docs/04` § 6 render; template + version recorded in provenance. | SUM-002 |
| NSP-084 | Custom templates | NSPIntelligence | User-defined sections; validation prevents a template from requesting ungrounded claims. | SUM-002 |
| NSP-085 | Section regeneration with locked blocks | NSPIntelligence | `SUM-002` acceptance: locked and approved sections are byte-identical after regeneration. | SUM-002 |
| NSP-086 | Length / tone / audience controls | NSPIntelligence | Evidence set is unchanged across variants; only presentation differs. | SUM-002 |
| NSP-087 | Correction memory with inspect-and-forget | NSPIntelligence | Scoped to the selected workspace; every learned entry is listable and individually deletable. | — |
| NSP-088 | Prompt architecture + injection defence | NSPIntelligence | I7 gate green: a transcript containing injected instructions produces no tool call and no privileged behaviour change. | — |
| NSP-089 | Vector index + hybrid retrieval | NSPPersistence | FTS5 + vector fusion; authorization filter applied before retrieval (test proves no cross-workspace leakage). | AI-001 |
| NSP-090 | Ask — single meeting | Phone | Answers cite meeting, date, speaker, timestamp; synthesis is labelled as such. | AI-001 |
| NSP-091 | Ask — cross-meeting with scope selector | Phone | Scope selector is mandatory; comparisons across meetings; superseded/conflicting decisions detected. | AI-001 |
| NSP-092 | Saved questions → recurring briefs | Phone | Distribution remains approval-first; no automatic sending. | AI-001 |
| NSP-093 | Live Lens | Phone | Cards appear only above the confidence/relevance threshold, show a source, disappear without action, disable per meeting or workspace. | — |
| NSP-094 | Backend: gateway, auth, grants | Backend | `/v1` endpoints per `docs/05` § 4; idempotency keys on all mutating routes; contract tests green. | — |
| NSP-095 | Backend: ASR + diarization workers | Backend | Batch job latency SLO met; artifacts versioned with pinned model IDs. | — |
| NSP-096 | Backend: ephemeral copies + deletion receipts | Backend | TTL enforced; signed deletion receipt returned and stored client-side; orphan sweeper covers abandoned jobs. | DEL-001 |
| NSP-097 | Backend: streaming ASR over WebSocket | Backend | Preview reconciles with the canonical pass on the client without duplicated turns. | TRN-001 |
| NSP-098 | `Tools/evals` in CI with release gates | Tools | WER/DER, entity accuracy, evidence coverage, hallucination rate; a regression blocks merge. | SUM-001 |

---

# M4 — iPad canvas and Pencil

**Status as of 2026-08-20, updated (v2)** (see `docs/07-UX-SPEC.md` § 5 for the full normative spec, written
against a reference mockup at `~/Downloads/IMG_0121.PNG`): the iPad shell exists and is real —
`App/Phone/RootView.swift` picks `PadRootView` vs. the iPhone `TabView` by device idiom at runtime (this is a
universal app, not a separate target); `App/Phone/iPad/PadRootView.swift` is a working 3-column
`NavigationSplitView` (sidebar of the five areas → content → meeting detail). `App/Phone/iPad/
PadRecordingCanvas.swift` now has the dark header + tool palette (`PadCanvasHeader`; Pointer/Text/Pen real,
the rest honestly disabled), an editable title band, the red margin rule, and **real PencilKit ink**
(`PadInkCanvas`, `NSP-100`) persisted as a `.sketch` `NoteBlock` referencing an asset file in the meeting
container's `ink/` directory — plus the v1 typed-line editor, each ruled line still a real `.richText`
`NoteBlock` anchored to a real sample offset (`Segmenter`/`CaptureEngine`/`RecordingSession
.currentSampleOffset()`, read-only, don't touch segment or timeline state). **Still not built:** `NSP-101`
stroke-group timestamping (ink is one page-wide layer with no margin stamp of its own yet — the biggest
remaining gap); photo insertion; multi-page; pre-recording availability with `--:--` stamps (needs a "start a
draft meeting before recording" entry flow that doesn't exist — a product decision, not just engineering).
Not yet visually verified in Simulator beyond build/lint/test passing — this environment has no UI-automation
path to tap "Start Recording" and navigate into the canvas for a live screenshot; verify on a real device or
via manual Simulator interaction before trusting the visual result matches the mockup.

| ID | Title | Module | Acceptance | Req |
|---|---|---|---|---|
| NSP-099 | Split canvas / transcript workspace | Phone (iPad) | Resizable; state restored per meeting and tab. | NOT-002 |
| NSP-100 | PencilKit ink capture | Phone (iPad) | Ink stored as an asset referenced by a `NoteBlock`; never rasterized destructively. | NOT-002 |
| NSP-101 | Stroke-group timestamping | Phone (iPad) | Every stroke group carries a `creationRange` on the canonical timeline. | NOT-002 |
| NSP-102 | Tap-a-stroke-to-seek | Phone (iPad) | `NOT-002` acceptance: seek lands within the documented tolerance; reverse direction (transcript → nearby notes) also works. | NOT-002 |
| NSP-103 | Full content block set | Phone (iPad) | All thirteen block types in `docs/02` § 2 render and edit. | NOT-001 |
| NSP-104 | Handwriting recognition and search | Phone (iPad) | Search matches handwriting; converting to text preserves the original ink. | — |
| NSP-105 | Private margin notes | Phone (iPad) | Excluded from every share and export path by default; the exclusion is enforced in the export code, not the UI. | NOT-001, SHR-001 |
| NSP-106 | Merge-into-recap with approved diff | NSPIntelligence, Phone | AI proposes placement, user approves a diff; a test proves no code path mutates a `NoteBlock` without user approval. | NOT-001 |
| NSP-107 | Whiteboard/document capture + perspective correction + OCR | Phone (iPad) | Detected regions remain editable artifacts; OCR text is searchable and timestamped. | — |
| NSP-108 | Stage Manager and multiwindow | Phone (iPad) | Only one microphone owner per account; explicit handoff between windows. | CAP-004 |
| NSP-109 | Keyboard shortcuts | Phone (iPad) | Marker, action, decision, pause/resume, seek, search — all discoverable in the shortcuts overlay. | — |
| NSP-110 | External display presentation mode | Phone (iPad) | Selected notes only; transcript and private content provably not exposed (snapshot test). | SHR-001 |
| NSP-111 | Handoff and deep links | Phone | Opens the same meeting and active tab across devices. | — |
| NSP-112 | Note operation log merge | NSPSync | Concurrent offline edits on two devices converge with no lost blocks; `SYN-001` concurrent-edit test green. | SYN-001 |

---

# M5 — Follow-through, sharing, integrations

| ID | Title | Module | Acceptance | Req |
|---|---|---|---|---|
| NSP-113 | Action dashboard | Phone | Mine / assigned by me / due / overdue / exported; paged, never loads full transcripts. | ACT-001 |
| NSP-114 | Owner and due-date detection | NSPIntelligence | Inference visibly labelled; ambiguity blocks automated external write. | ACT-001 |
| NSP-115 | Dependencies and status lifecycle | NSPActions | Full `Proposed → … → Done/Dismissed` with audit at each hop. | ACT-001 |
| NSP-116 | Decision ledger | NSPActions | Rationale, alternatives, approver, supersession chain, evidence. | SUM-001 |
| NSP-117 | Unanswered-question queue | NSPActions | Attribution to the asking participant; dismiss and resolve states. | — |
| NSP-118 | Follow-up draft generation | NSPIntelligence | Drafts stay drafts; sending requires confirmation unless a logged automation rule explicitly allows it. | ACT-001 |
| NSP-119 | Share links with roles and expiry | Backend, Phone | Expiry and revocation enforced server-side; access logged. | SHR-001 |
| NSP-120 | Passcode and download controls | Backend | Passcode hashed; download/forward policy enforced at fetch time, not in the UI. | SHR-001 |
| NSP-121 | Section / action-only / soundbite sharing | Phone | Recipient preview equals the delivered payload byte-for-byte (test). | SHR-001 |
| NSP-122 | Comments, mentions, collaborative highlights | Backend, Phone | Scoped to the share grant; private notes never exposed. | SHR-001 |
| NSP-123 | PDF and DOCX export | Phone | Evidence footnotes included; deterministic output for a fixed package. | SHR-001 |
| NSP-124 | SRT/VTT, CSV, M4A, ZIP evidence bundle | Phone | Bundle contains JSON + audio + attachments + redaction certificate + audit excerpt. | SHR-001 |
| NSP-125 | Calendar export | NSPActions | Idempotent; duplicate-safe on retry. | INT-002 |
| NSP-126 | OAuth broker + connector interface | Backend | Least privilege; scope preview before authorization; tokens never reach the client. | INT-002 |
| NSP-127 | Connector: Slack | Backend | Channel/location preview; idempotent post; receipt stored. | INT-002 |
| NSP-128 | Connector: Notion | Backend | Field mapping; dedupe key; conflict state surfaced. | INT-002 |
| NSP-129 | Connector: Linear | Backend | Task created once under retry; external ID recorded. | INT-002 |
| NSP-130 | Public API + signed webhooks (beta) | Backend | Versioned event model; signature verification documented; service accounts audited. | — |

---

# M6 — Privacy, enterprise, launch readiness

| ID | Title | Module | Acceptance | Req |
|---|---|---|---|---|
| NSP-131 | Retention policy engine | NSPPolicy | Per-workspace and per-meeting retention; jobs run on device and server; clock changes cannot skip a purge. | DEL-001 |
| NSP-132 | Delete raw audio after approval | NSPPolicy | Approved notes survive; audio removal converges across device, cloud, and processor with receipts. | DEL-001 |
| NSP-133 | Soft delete → tombstone → purge pipeline | NSPPersistence, NSPSync | `DEL-001` acceptance: all device, cloud, and processor states converge to a purge receipt. | DEL-001 |
| NSP-134 | Verifiable deletion workflow (user-facing) | Phone | The user can see, per meeting, what was deleted where and when. | DEL-001 |
| NSP-135 | Text + time-aligned audio redaction | NSPMedia, NSPIntelligence | Redacted interval is unplayable in the redacted artifact; original access is separately controlled. | — |
| NSP-136 | Redaction certificate + irreversible export | Phone | Certificate lists redacted ranges without revealing content. | — |
| NSP-137 | Enterprise SSO / SCIM / RBAC | Backend | Provisioning and de-provisioning tested; de-provisioned users lose retrieval access immediately. | — |
| NSP-138 | Workspace policy engine | NSPPolicy, Backend | Required announcement, blocked domains/locations, forced local-only, retention floors — all enforced client-side and server-side. | PRV-001 |
| NSP-139 | Admin audit views | Backend | Recording start/stop, consent, view, share, export, integration writes, policy changes. | — |
| NSP-140 | Consent tooling completion | Phone, Watch | Audible announcement, consent checklist, attendee confirmation, invite disclosure; `ConsentRecord` never asserts legal compliance. | — |
| NSP-141 | Abuse reporting and covert-capture defence | Phone | Persistent indicators verified on every surface; reporting path documented. | — |
| NSP-142 | Accessibility completion pass | all UI | Full VoiceOver workflows on all three platforms, Dynamic Type including Watch, non-colour status, haptic equivalence, captions. | — |
| NSP-143 | Localization + RTL | all UI | String catalogs, no concatenated sentences, RTL layout verified; transcription-language availability is independent of UI locale. | — |
| NSP-144 | Performance and battery sign-off | all | Published support matrix numbers reproduced on hardware per Watch generation. | — |
| NSP-145 | iCloud quota, logout, and key-reset flows | NSPSync | Each surfaces an actionable state; local recoverability preserved or clearly explained. | SYN-001 |
| NSP-146 | Security review + threat-model tests | all | Every row of the `docs/06` threat table has a passing proving test; external pen test completed. | — |
| NSP-147 | App Review materials | docs | Recording intent, background behaviour, privacy indicators, and user value documented with screenshots. | — |
| NSP-148 | Release gate run | all | Every item in `docs/10` § 8 green on hardware, results recorded in `docs/reports/`. | all |

---

# Appendix A — Functional requirements

Carried forward from the product design. Each is closed by the tickets that reference it above.

| ID | Priority | Requirement | Acceptance |
|---|---|---|---|
| CAP-001 | P0 | Start recording from Watch while the iPhone is unreachable. | First durable audio written locally before any confirmation. |
| CAP-002 | P0 | Pause / resume / stop from the Watch. | State and timeline reconcile after reconnect. |
| CAP-003 | P0 | Segment and recover recordings. | Crash test recovers all closed segments and discloses the partial tail. |
| CAP-004 | P0 | Mirror active state across devices. | No device displays a false stopped/recording state; the source device is labelled. |
| CAP-005 | P1 | Highlight / marker from the Watch. | Marker appears at a sample-aligned timestamp. |
| TRN-001 | P0 | Timestamped transcript with speaker turns. | Tapping a turn seeks the correct audio. |
| TRN-002 | P0 | Edit speaker and text without destroying the original. | Revision history and provenance retained. |
| TRN-003 | P1 | Multilingual and bilingual meetings. | Language spans preserved; translation is a separate view. |
| SUM-001 | P0 | Generate recap, decisions, actions, questions. | Every action and decision has evidence or is labelled a suggestion. |
| SUM-002 | P1 | Custom templates and section regeneration. | Locked sections remain unchanged. |
| NOT-001 | P0 | Typed notes and private notes. | Private blocks excluded from shares by default. |
| NOT-002 | P1 | Pencil / audio synchronization on iPad. | Tapping a stroke group seeks within tolerance. |
| ACT-001 | P0 | Confirm action fields before send. | Ambiguity blocks the automated external write. |
| SHR-001 | P0 | Granular share preview and revocation. | Preview equals the recipient-visible payload. |
| SYN-001 | P0 | Offline-first CloudKit synchronization. | No data loss in the concurrent-edit and reconnect test. |
| PRV-001 | P0 | Per-meeting local / on-device / cloud processing mode. | Network inspection confirms local-only sends no content. |
| DEL-001 | P0 | Retention and verifiable deletion. | All device, cloud, and processor states converge to a purge receipt. |
| INT-001 | P1 | Calendar context and launch. | Permission is granular; private calendar fields minimized. |
| INT-002 | P1 | Task and collaboration exports. | Idempotent retry creates no duplicate task. |
| AI-001 | P1 | Ask across current or multiple meetings with citations. | Authorization and source-coverage tests pass. |

---

# Appendix B — Suggested first week

For a single engineer starting cold, in this order:

1. `NSP-001` — get `make check` green on an empty repo. Everything else depends on this being fast.
2. `NSP-006` and `NSP-007` — the domain types and the state machine. Pure Swift, no I/O, heavily tested. This
   is where the product's rules become code.
3. `NSP-009` — the test support foundation, especially the golden tone-burst generator. You will use it for the
   next six months.
4. In parallel, get `NSP-002` onto real hardware. It is the long pole and it can invalidate the plan.

Do not start `NSP-011` (persistence) before `NSP-007` is green. The schema follows the domain, not the reverse.
