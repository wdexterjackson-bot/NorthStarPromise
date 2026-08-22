# 06 — Privacy, Security, Consent, Retention, and Redaction

Specification for **`NSPPolicy`** and the product's privacy posture. This is the enforcement design for
Invariant **I5** (*local-only means local-only*) and a major consumer of **I6** and **I7**.

Nothing here is aspirational: every clause is compiled, tested, or a named manual gate. If a statement cannot
become a test or a gate, it does not belong in this document.

> **Legal framing discipline.** This product ships *tools*, not *conclusions*. No surface — code comment, UI
> string, export, or certificate — may assert that a recording is lawful, that consent is sufficient, or that
> the product satisfies a named regulation. Anything reading as a legal conclusion **requires counsel review**
> before it ships; the default phrasing is "recording laws vary by jurisdiction and you are responsible for
> compliance."

---

## 1. The privacy model in one page

**Local-first** means four concrete things, not a marketing adjective:

1. The **canonical copy** of audio, manifest, transcript, notes, and insights lives in the app container on the
   user's device (I2). Cloud and relay copies are derivatives, destroyable without data loss.
2. The product **builds, records, transcribes, summarizes, searches, and exports** with the backend
   unreachable. CI proves it via the `LocalOnly` configuration (`make test LOCAL_ONLY=1`).
3. Any departure of content from the device is **per-meeting, opt-in, frozen before capture starts, and
   verifiable by network inspection** — a user with a proxy sees exactly what the mode promised.
4. Cloud processing copies are **ephemeral** and produce a **deletion receipt** the user can read.

### 1.1 The three ProcessingModes

`ProcessingMode` lives in `NSPCore`, is stored on `Meeting`, and is **frozen at `Arming`** (`docs/02` § 3) into
an immutable `Policy` snapshot referenced by `Meeting.policyID`. Later workspace-policy changes never
retroactively loosen a meeting. Post-Arming **loosening is rejected** (`.localOnly → .cloudAllowed`);
tightening is allowed and takes effect immediately, cancelling in-flight jobs and enqueuing a receipted purge.

| | `.localOnly` | `.onDevicePreferred` | `.cloudAllowed` |
|---|---|---|---|
| Audio bytes leave the device | **Never** | Never | Yes, as an ephemeral processing copy |
| Transcript / notes / insight text leave | **Never** | Never | Yes |
| Title, attendee names, calendar data leave | **Never** | Never | Yes (title only if `isTitleSensitive == false` or explicitly confirmed) |
| CloudKit private-DB writes for this meeting | **None at all**, including metadata | Yes | Yes |
| WatchConnectivity relay to the paired iPhone | Allowed (same trust domain, user's own devices) | Allowed | Allowed |
| On-device ASR / summarization | Yes | Yes | Yes |
| Cloud ASR / summarization | **Forbidden** | Forbidden; degrades to "transcript only, no summary" | Yes, with grant |
| Content in analytics or crash reports | **Never** | Never | Never (§ 10 applies to all modes) |
| Share links (service-hosted) | Forbidden | Forbidden | Yes |
| Export to a local file / AirDrop / Files | Allowed (user-initiated, I6-confirmed) | Allowed | Allowed |

Byte-for-byte reading of `.localOnly`: the only permitted egress is (a) WatchConnectivity frames to the paired
iPhone on the same iCloud account, and (b) a user-initiated, explicitly confirmed export written to a
destination chosen in a system picker. Everything else — CloudKit, backend, analytics, crash reporter,
Spotlight donation, any remote fetch carrying a title — is refused at the gate.

`.onDevicePreferred` **never silently escalates.** If the on-device summarizer is unavailable, the UI states
"Summary unavailable on this device" and offers a per-meeting upgrade that requires explicit confirmation *and*
creates a new meeting policy revision with an audit event.

---

## 2. `NetworkGate` — the single choke point

Every content-bearing egress call passes through `NetworkGate`. It consults the frozen per-meeting policy,
emits an audit event, and is the **only** type that can mint a `ProcessingGrant`, which has no public
initializer.

```swift
public enum ProcessingMode: String, Codable, Sendable {
    case localOnly, onDevicePreferred, cloudAllowed
}

/// What a caller wants to send. Declared, not inferred.
public enum EgressPurpose: Sendable {
    case transcription, diarization, summarization, retrievalIndex
    case cloudKitSync, shareLink, integrationWrite(destination: IntegrationDestination)
    case diagnosticsBundle
}

public struct EgressRequest: Sendable {
    public let meetingID: MeetingID
    public let purpose: EgressPurpose
    public let classes: Set<ContentClass>   // .audio, .transcript, .notes, .title, .attendees, .attachments, .derivedEmbedding
    public let byteCount: Int
    public let payloadSHA256: Data          // logged; the payload itself is never logged
    public let destination: EgressDestination
}

/// Unforgeable capability. Only NetworkGate can produce one. `internal init` + no Codable conformance.
/// THIS IS THE SINGLE AUTHORITATIVE DEFINITION. `docs/04` and `docs/05` refer to it; they do not redefine it.
public struct ProcessingGrant: Sendable {
    public let grantID: GrantID
    public let meetingID: MeetingID
    public let policyID: PolicyID           // the frozen policy snapshot this grant was issued under
    public let mode: ProcessingMode
    public let allowedClasses: Set<ContentClass>
    public let capabilities: Set<ProcessingCapability>  // .streamingASR, .batchASR, .diarization,
                                                        // .summarization, .embedding, .entailment
    public let expiresAt: Date
    public let region: ProcessingRegion
    public let retentionSeconds: Int        // processor-side max; drives the deletion receipt
    public let auditEventID: AuditEventID   // issuing a grant is itself audited
    internal init(...)                      // deliberately not public
}

public enum EgressDecision: Sendable {
    case allowed(ProcessingGrant)
    case denied(EgressDenial)               // .localOnlyMeeting, .classNotPermitted(ContentClass),
                                            // .noConsentRecord, .workspacePolicyBlocked(reason),
                                            // .regionUnavailable, .userConfirmationRequired
}

public protocol NetworkGate: Sendable {
    /// The ONLY entry point to the network for content. Emits an AuditEvent for allow and deny alike.
    func authorize(_ request: EgressRequest) async -> EgressDecision
    /// Revokes outstanding grants for a meeting and enqueues processor purge with receipts.
    func revokeAll(for meetingID: MeetingID, reason: RevocationReason) async throws
}
```

Every `NSPBackendClient` method takes a `ProcessingGrant` (`docs/01` § 3). `NSPSync` takes one per zone write.
`NSPActions`' integration outbox takes one per destination write, on top of its I6 confirmation. Analytics has
no path to a grant at all — it can only emit the content-free events in § 10.

### 2.1 How the codebase proves "there is no other way out"

Three independent mechanisms; any one failing fails CI.

| Mechanism | What it is | Where |
|---|---|---|
| **`LocalOnly` build configuration** | Compiles `NSPBackendClient` out of the graph entirely. The app must still build, record, transcribe, summarize on-device, search, and export. A stray backend reference becomes a **link error**, not a runtime bug. | `project.yml`, `make test LOCAL_ONLY=1` |
| **Architecture lint** | `Tools/lint/egress-audit.swift` fails the build if `URLSession`, `NWConnection`, `CKContainer`, or any third-party HTTP symbol appears outside the allowlist `{NSPBackendClient, NSPSync, NSPPolicy}`. Allowlist additions require a doc change in the same PR plus CODEOWNERS review. | `make lint` |
| **Network-content audit (`PRV-001`)** | Runs a fixture meeting in each mode end-to-end against a process-level HTTP/CloudKit interceptor. Every request body, header, URL, and query is scanned for high-entropy canaries planted in the fixture's audio filename, title, attendee names, transcript tokens, and note text. `.localOnly` expects **zero** requests; other modes require a valid `grantID` and only that grant's classes. Also asserts no canary reaches the analytics sink, crash payloads, Spotlight donations, or the diagnostic bundle. | `docs/10` § Invariant gates |

---

## 3. Consent experience

### 3.1 First-run education

A non-skippable first-launch screen stating in plain language: recording laws vary by jurisdiction and by who
is in the room; the user is responsible for obtaining any required permission; the app provides tools to
announce and record acknowledgement but **cannot determine what is legal for a given meeting**. It links to a
help article, not legal advice. It presents **no jurisdiction detection, no "one-party/two-party" map, no
green/red compliance indicator** — those are legal conclusions and are out of scope. Copy requires counsel
review before release.

### 3.2 Pre-recording options

Configurable per workspace and per meeting; surfaced in the Arming sheet and compactly on the Watch.

| Option | Behaviour |
|---|---|
| **Audible announcement** | A spoken/played announcement on the capturing device before segment 0 opens. Recorded into the audio itself so the announcement is part of the evidence. |
| **On-screen consent checklist** | Checkboxes the recorder confirms (announced verbally / invite disclosed / all attendees present agreed). |
| **Attendee confirmation** | Pass-the-device or per-attendee tap on iPad; captures names acknowledged. |
| **Calendar invite disclosure** | Inserts a disclosure line into the event body; records that it was inserted and when. |

Workspace policy may **require** announcement (Arming blocks until it completes) and may **block** recording by
calendar domain (external participants from listed domains) or coarse geofence. Blocks surface a named state
and an admin contact — never a silent failure. Location checks use the coarsest authorization that works and
never store precise coordinates in the meeting record.

### 3.3 Indicators and haptics

Recording is never covert (`docs/00` § 5). On every device with an active session: the platform recording
indicator, plus an in-app persistent indicator that is **not colour-only** (icon + text + motion), a Live
Activity / Dynamic Island presence on iPhone, and a Watch complication state. Watch haptics fire on
**start / pause / resume / stop** with four distinguishable patterns from the `NSPDesignSystem` haptic
vocabulary; per I1 the start haptic fires only *after* the durable write. Silencing indicators is not a
setting, and no experiment may weaken them (§ 10).

### 3.4 `ConsentRecord`

```swift
public struct ConsentRecord: Sendable, Codable {
    public let consentRecordID: ConsentRecordID
    public let meetingID: MeetingID
    public let method: Set<ConsentMethod>       // .audibleAnnouncement, .onScreenChecklist,
                                                // .attendeeConfirmation, .calendarInviteDisclosure, .none
    public let capturedAt: Date
    public let participantsAcknowledged: [ParticipantAcknowledgement]  // display name + how + when
    public let announcementSampleRange: SampleRange?   // where the announcement lives in the audio
    public let recorderDeviceID: DeviceID
}
```

**A `ConsentRecord` is a record of what the user did. It is not a certification of legal compliance**, and both
the type's doc comment and the UI string say exactly that. Method `.none` is a legitimate value and must not be
styled as an error.

### 3.5 Ambient Mode (added 2026-08-22, "Overheard" recommendation; consent model simplified 2026-08-22)

Ambient Mode is treated the same as recording a meeting, not as a separate consent surface with its own
onboarding — it has no bounded meeting and no participant roster, so §§ 3.1–3.4's per-meeting `ConsentRecord`
doesn't apply, but the same underlying announcement mechanism does:

- **Audible announcement reuses `Policy.announcementRequired`** — the identical workspace setting § 3.2's
  "Audible announcement" row already governs for recorded meetings. When it's on, "Recording in Process" plays
  on every Ambient session start and every duration-limit renewal; when it's off, a session starts the same way
  starting a meeting recording does. No Ambient-specific announcement setting exists.
- **Default off, opt-in.** `Policy.ambientModeEnabled` gates the feature at the workspace level; a live
  session's own duration is capped (`Policy.ambientSessionDurationMinutes`, 30–150 minutes) with an explicit
  "Continue Ambient Mode?" reprompt at the limit — never a silently-forgotten, indefinitely-running session.
- **Nothing is ever auto-added.** Every extraction lands in the Ambient Suggestions inbox as a `.pending`
  `AmbientSuggestion`; accepting it creates a real, freestanding `Action` only after a human confirms it (I6's
  spirit, extended to this feature's own version of "the world changing").
- `FeatureFlag.ambientMode` is on (`docs/09-BACKLOG.md` NSP-161–165) — broad availability was gated on a legal
  review of consent-recording statutes, which the user confirmed complete 2026-08-22.

---

## 4. Encryption and key management

| Data | Protection class | Why |
|---|---|---|
| `segments/*.m4a`, `manifest.json`, `manifest.wal` | `.completeUnlessOpen` | Written while the device may be locked. Wrist-down recording with the screen off *requires* creating and appending to files while locked; `.complete` would fail the write and violate I1. Files open at Arming and stay open for the session. |
| SQLite DB + WAL, ink, attachments, staged exports | `.complete` | No need to write while locked. |
| Derived caches (waveform peaks, thumbnails) | `.completeUnlessOpen` | Regenerable; convenience only. |
| App Group state for widgets / Live Activity | `.completeUnlessOpen`, **metadata only** | Never transcript, never title text. |

`SEC-001` writes a segment with the device locked and asserts both success and that the DB write correctly
defers. Keychain holds backend tokens, share-link secrets, and envelope keys with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; no item syncs to iCloud unless it must reach another device, in
which case `...AfterFirstUnlock` plus explicit review.

**CloudKit:** sensitive fields (`title`, note text, transcript assets, insight text) use CloudKit **encrypted
fields** — end-to-end encrypted under the user's iCloud keys, unreadable by us. Structural fields (IDs, sample
counts, hashes, revisions) stay queryable.

**Application-layer envelope encryption** (high-sensitivity tier, feature-flagged; `docs/00` § 8 open
decision): a per-meeting AES-GCM content key wrapped by a workspace key in the Keychain (CryptoKit). Tradeoffs,
stated so they are chosen rather than discovered — server-side search becomes impossible (retrieval stays fully
local), cloud processing becomes impossible (such meetings are effectively `.localOnly`), CloudKit sharing
cannot be used (key distribution becomes ours), and support cannot recover data. Ship only where all four costs
are acceptable, and label the tier in the UI with those consequences.

**Key recovery and iCloud key reset:** an account change or end-to-end key reset can make previously synced
encrypted fields unreadable (`CLAUDE.md` § 6). `NSPSync` detects this, enters an explicit
`EncryptedDataUnavailable` state naming the affected meetings, keeps local canonical copies fully usable, and
prompts an export. **A local copy is never deleted because the cloud copy became unreadable.** Envelope keys
have an optional user-held recovery phrase; losing it is unrecoverable, and enrollment says so in one sentence
before the tier turns on.

---

## 5. Access control

- **Baseline identity:** Sign in with Apple / iCloud account. A single-user local install requires no account
  at all beyond the device — capture and on-device intelligence work signed out.
- **Enterprise (optional):** SSO via OIDC/SAML, SCIM for provisioning and deprovisioning. SCIM deprovision
  revokes share grants and sessions within the workspace and is audited.
- **Roles:** `owner`, `admin`, `member`, `guest`, `viewer`. Meeting-level sharing is a `ShareGrant` (`docs/02`
  § 2) with role, scope, expiry, passcode hash, download policy, and revocation state.
- **Authorization before retrieval (hard rule).** Every FTS5, vector, and Spotlight query joins through the
  access filter *before* candidates are fetched, and the index itself excludes `excludedFromMemory` and
  soft-deleted meetings. Filtering after generation is forbidden — by then the content has already entered a
  prompt. Gate `AI-001` asserts that a user with no grant to meeting M cannot cause M's text to appear in any
  retrieval candidate set, not merely in the final answer.

---

## 6. Retention and deletion

Retention is configurable per workspace and per meeting: raw audio `7 / 30 / 90 / 365 days / forever / until
notes approved`; transcripts and notes carry their own clock. The headline option is **"delete raw audio after
approved notes are created"** — when the recap layer reaches `Insight.approvalState == .approved`, a retention
job schedules audio purge, warns that evidence spans become **audio-stale** (transcript anchors survive,
playback does not), and requires one confirmation. Affected spans render as stale rather than vanishing (I4).

**Pipeline:** `soft delete (deletedAt set, hidden, de-indexed) → tombstone (durable, syncs) → purge
(destructive, per destination, receipted)`. Convergence is the point: a tombstone fans out to device files, the
local DB, CloudKit records and assets, processor-side ephemeral copies, and integration destinations we wrote
to. Each returns a `DeletionReceipt {destination, objectRef, requestedAt, completedAt, method, verifierHash}`.
Purge is idempotent and retried with backoff; an unreachable destination stays `pending` and visible — never
silently marked done.

| Deletion covers | Behaviour |
|---|---|
| Local audio segments + manifest + WAL | File removal on every device holding a copy, including the Watch |
| Local DB rows (turns, tokens, notes, insights, actions, evidence) | Deleted; tombstone retained |
| FTS5 + vector index entries | Removed at soft-delete time, before purge |
| CloudKit records and `CKAssets` | Deleted in the zone; asset dedupe refcount respected |
| Processor ephemeral copies and intermediates | Purge request + receipt; retention cap enforced by the grant |
| Share links and recipient caches | Links revoked immediately; recipient-downloaded copies **cannot** be recalled — stated plainly |
| Integration destinations (Reminders, CRM, task tracker) | Best-effort delete or a "no longer backed by a meeting" mark; receipts show which |
| Analytics | Nothing to delete — content-free by construction (§ 10) |
| Audit log entries | **Retained** (hashes and metadata only, no content) — deletion must itself be auditable |
| Backups / snapshots | Aged out on the documented backup cycle; disclosed, not claimed instant |

**Verifiable deletion workflow:** *Settings → Privacy → Deletion status* lists every pending and completed
deletion with per-destination receipts, timestamps, and failures, plus a "re-run purge" action and an
exportable receipt bundle — inspectable without contacting support. `DEL-001` asserts that after purge no
query, index, export, or file scan on any device surfaces the meeting's canaries, and that the receipt set is
complete.

---

## 7. Redaction

Redaction operates on the pair (text, time-aligned audio) — word-level timings are mandatory for exactly this
reason (`docs/02` § 2). The user selects transcript text, a speaker, a time range, or a detected entity class;
the result is a `RedactionSet` referencing turn ranges and sample ranges.

A redacted export **never mutates a segment** (I3). The export pipeline reads canonical segments, applies
muting/removal to the rendered output stream, strips the corresponding transcript tokens, drops any insight or
action whose evidence resolves entirely inside a redacted span, and marks partially-affected claims. The share
preview comes from the same code path (`docs/02` § 7), so what the recipient sees is what was built.

A **redaction certificate** ships in the evidence bundle: export schema version, count and total duration of
redacted spans, their canonical time ranges, reason codes, the SHA-256 of the redacted output, and whether the
export was reversible. It records *what was removed and where* — never the removed content.

**Irreversible export** re-encodes audio with redacted intervals physically absent and renumbers the timeline;
the artifact retains no mapping back to the original. The original stays under separate access control:
viewing an unredacted original requires a permission distinct from viewing the meeting, and each access emits
an audit event.

---

## 8. Sharing controls

Sharing is role-based (§ 5). Every link **expires by default** and is revocable at any time, with an optional
passcode stored as a hash. Download and forwarding are independent toggles — `viewOnly`, `allowDownload`,
`allowExport`, `allowTranscriptDownload` — all off except viewing.

- **Private notes are excluded by default.** `NoteBlock.privacy == .privateToAuthor` never appears in a share,
  preview, export, or recipient-facing retrieval, in any role.
- **The recipient preview is generated from the export code path**, never described separately. It enumerates
  every artifact class leaving the workspace with counts, and is the I6 confirmation surface for the share.
- **Non-participant warning:** when acknowledged participants (from `ConsentRecord`) include people outside the
  grant set, the share sheet shows a prominent warning naming how many, before the confirm button. It states
  the fact and draws no legal conclusion.
- Revocation invalidates the link server-side immediately and is audited. The UI states plainly that already-
  downloaded content cannot be recalled.

---

## 9. Threat model

| # | Threat | Impact | Mitigation | Test that proves it |
|---|---|---|---|---|
| T1 | **Lost unlocked Watch or iPhone** | Attacker reads meetings, exports, shares | Data Protection classes (§ 4); app-level biometric lock with configurable grace; sensitive titles hidden on lock screen, complications, and Live Activity; remote wipe via MDM/Find My; no content in App Group widget state | `SEC-001` locked-device write/read; `SEC-002` asserts no title or transcript text in complication, Live Activity, notification, or App Group payloads |
| T2 | **Malicious share recipient** | Redistributes content beyond intent | Expiring + revocable links, passcode, download/export off by default, private notes excluded, watermarked recipient view, per-access audit | `SHR-001` recipient-preview == export byte equivalence; `SHR-002` revoked link returns 403 and serves no cached asset |
| T3 | **Prompt injection in transcripts / attachments / calendar titles (I7)** | Model emits attacker-chosen text, or triggers an external write | Content is never concatenated into a privileged instruction context; it enters as clearly delimited untrusted data with a separate role; model output can never authorize a tool call — all external writes require the I6 human confirmation and a `ProcessingGrant`; connector payloads are schema-validated, not model-authored free text | `SEC-003` injection corpus (transcripts + attachments + titles carrying imperative payloads) asserts zero tool invocations and zero policy changes; eval suite tracks refusal rate |
| T4 | **Cross-workspace retrieval leak** | Meeting from workspace A cited in workspace B's answer | Authorization filter joins before retrieval and indexing; per-workspace CloudKit zones; embeddings carry `workspaceID` and queries are scoped at the SQL level, not in application code | `AI-001` authorization-before-retrieval; property test fuzzes multi-workspace corpora asserting zero foreign candidates |
| T5 | **Covert capture abuse** | Product used to record people without their knowledge | Indicators cannot be disabled (§ 3.3); platform recording affordance is mandatory on Watch; announcement policy can be workspace-enforced; audit records every start/stop | `PRV-002` asserts recording state is visible on every active device in every UI state; `PRV-003` asserts no build flag or setting suppresses indicators |
| T6 | **Cloud key reset / iCloud account loss** | Previously synced encrypted data unreadable | Local canonical copies unaffected; explicit `EncryptedDataUnavailable` state naming affected meetings; export prompt; local copy never deleted because cloud became unreadable | `SYN-004` simulates key reset and asserts local playback, search, and export still work and no local delete occurred |
| T7 | **Malicious or compromised integration connector** | Exfiltration via an outbound write; poisoned responses | Per-destination `ProcessingGrant`; least-privilege OAuth scopes; payload schema validation and size caps; human-confirmed exact payload (I6); connector responses are untrusted input (I7); per-connector kill switch and audited receipts | `INT-002` asserts no connector call without grant + confirmation; `INT-003` fuzzes hostile connector responses asserting no state change beyond the receipt |
| T8 | **Rogue insider with admin access** | Reads customer content in the processing plane | Content in the private DB is E2E-encrypted under user keys and unreadable by us; processing-plane copies are ephemeral, encrypted at rest, region-pinned, and access-logged; production access requires break-glass with two-person approval and is itself audited; no training on customer content | Backend purge-SLA gate (`docs/05` § 11): ephemeral copies deleted within the grant's `retentionSeconds`; access-log completeness test; break-glass audit test |

---

## 10. Analytics and diagnostics

Default telemetry is **content-free by construction**: no audio, transcript, notes, titles, attendee names,
calendar identifiers, file paths containing user content, or free-text error strings that could embed content.
Permitted: enumerated event names, durations, counts, coded enum values, device class, OS version, coded error
taxonomy IDs. Anything else is a lint failure — telemetry payloads must conform to `ContentFreeTelemetry`,
checked by `Tools/lint/telemetry-audit.swift` (string-valued properties must be a `TelemetryEnum`, not
`String`). Crash reports scrub by the same rule.

**Content-bearing diagnostics require explicit, per-incident opt-in.** The user builds a **diagnostic bundle**
in Settings, sees exactly which files are included, can redact spans, and previews it in full in a local viewer
before an I6 confirmation sends it.

**Experiment guardrail:** no A/B test, remote-config value, or feature flag may vary recording indicators,
consent copy clarity, deletion behaviour, retention defaults, or any security control **toward less
protection**; experiments here may only test *more* clarity or *more* protection. Enforced in code — flags
touching those surfaces are declared `.protective` in `FeatureFlags.swift` and the flag service rejects any
remote value that lowers one. `PRV-004` asserts it.

---

## 11. Compliance posture

**Can claim** (each backed by a green gate): private by default; local-only mode with zero content egress
(`PRV-001`); content-free analytics; end-to-end encrypted iCloud fields for sensitive data; no training on
customer content; per-meeting processing choice; deletion with inspectable receipts; region-pinned processing
where offered.

**Cannot claim** without counsel review and, where relevant, an external audit: any named certification
(SOC 2, ISO 27001, HIPAA, GDPR/CCPA "compliance"), that recording is lawful in any jurisdiction, that a
`ConsentRecord` establishes valid consent, or a single normalized accuracy number.

- **Subprocessors** are disclosed in a public, versioned list (name, purpose, data classes, region) with
  advance notice of changes. `.localOnly` and `.onDevicePreferred` meetings touch none of them.
- **Regional processing:** `ProcessingGrant.region` pins where a job runs. A workspace may restrict regions; a
  grant unsatisfiable in an allowed region is denied (`.regionUnavailable`), never silently rerouted.
- **Enterprise enforcement:** admin-set retention, required announcement, blocked domains/locations, forced
  workspace-wide `.localOnly`, disabled external links, SCIM deprovision. Policies are versioned and a meeting
  keeps the snapshot it froze at Arming.
- **Audit log** (`AuditEvent`: actor, action, object, payload **hash**, result, timestamp — never content)
  covers recording start/stop, consent capture, meeting view, share create/access/revoke, export, redaction,
  integration writes, deletion requests and receipts, policy and admin actions, and break-glass access. Append-
  only, admin-exportable; deleting content never deletes the audit trail.
- **App Review narrative:** background recording exists because a wrist-worn recorder must survive wrist-down
  and screen-off; it uses the platform's sanctioned recording affordance and background audio mode with the
  mandated ongoing system presentation; the app never records other apps' audio or native calls; indicators are
  always active and cannot be disabled; microphone purpose strings are specific. Submissions include a demo
  account and a scripted walkthrough of consent, indicators, local-only mode, and deletion. Privacy nutrition
  labels are regenerated from the actual telemetry schema each release.

---

## 12. Privacy acceptance checklist

Each line is a test ID or a named manual gate. All must be green to ship.

- [ ] `PRV-001` — `.localOnly` fixture meeting produces **zero** outbound requests; no canary in any body, header, URL, analytics sink, crash payload, or diagnostic bundle.
- [ ] `PRV-001b` — `.onDevicePreferred` never issues a cloud ASR/LLM request, even when the on-device model is unavailable.
- [ ] `PRV-002` — Recording state is visible on every active device in every UI state, including locked, backgrounded, and low-power.
- [ ] `PRV-003` — No setting, build flag, or remote config suppresses recording indicators.
- [ ] `PRV-004` — Remote config cannot lower any `.protective` flag.
- [ ] `POL-001` — `ProcessingMode` cannot be loosened after `Arming`; tightening cancels in-flight jobs and enqueues purge.
- [ ] `POL-002` — `ProcessingGrant` cannot be constructed outside `NSPPolicy` (compile-time + reflection test).
- [ ] `POL-003` — `make lint` fails when `URLSession`/`NWConnection`/`CKContainer` is imported outside the allowlist.
- [ ] `POL-004` — `LocalOnly` configuration builds, records, transcribes, summarizes, searches, and exports with `NSPBackendClient` absent.
- [ ] `SEC-001` — Segment write succeeds with the device locked; DB write defers correctly.
- [ ] `SEC-002` — No title or transcript text in complications, Live Activity, notifications, App Group state, or Spotlight for sensitive meetings.
- [ ] `SEC-003` — Prompt-injection corpus triggers zero tool calls, zero policy changes, zero external writes (I7).
- [ ] `AI-001` — Authorization filter runs before retrieval and indexing; zero foreign-workspace candidates.
- [ ] `CON-001` — Arming is blocked when workspace policy requires announcement and none occurred; blocked domain/location produces a named state.
- [ ] `CON-002` — `ConsentRecord` persists method + timestamp + participants acknowledged, and the UI never asserts legal compliance.
- [ ] `DEL-001` — Purge removes content from device, DB, indices, CloudKit, and processor; receipts complete; canaries unfindable.
- [ ] `DEL-002` — "Delete raw audio after approved notes" fires on approval, warns about audio-stale evidence, and leaves transcript anchors resolvable.
- [ ] `DEL-003` — Deletion status screen shows every pending/failed destination and supports re-run.
- [ ] `RED-001` — Redacted export removes both text and audio interval; redaction certificate matches; original requires a separate permission and audits each access.
- [ ] `SHR-001` — Recipient preview is byte-equivalent to the export; private notes absent in every role.
- [ ] `SHR-002` — Revoked or expired link serves nothing, including from cache.
- [ ] `SHR-003` — Non-participant warning appears when acknowledged participants are outside the grant set.
- [ ] `INT-002` / `INT-003` — No connector write without grant + human confirmation; hostile connector responses change no state.
- [ ] `SYN-004` — iCloud key reset leaves local playback, search, and export intact; nothing deleted locally.
- [ ] **Manual gate** — Counsel review of first-run education, consent copy, `ConsentRecord` disclaimer, subprocessor list, and all compliance claims.
- [ ] **Manual gate** — Privacy nutrition labels regenerated from the telemetry schema and diffed against the previous release.
- [ ] **Manual gate** — Hardware validation (`CLAUDE.md` § 7) confirms indicators and haptics on physical Watch hardware, wrist down, screen off.
