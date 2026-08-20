# 08 — Milestones and Sequencing

**Planning unit:** engineering-weeks for a team of roughly 5–7 (2 iOS/watchOS, 1 iPadOS/UI, 1 backend/ML, 1 ML
evaluation, 1 design, part-time security/legal review). Adjust durations to your actual team; **do not reorder
the phases** — the dependency logic is what matters, and M0 gates everything.

**Strategy:** M1 is a deliberate *vertical slice through every pillar* — capture, transcript, summary, actions,
notes, sharing, privacy — thin but real, end to end, on all three devices. That validates the product shape and
the module boundaries early. M2 onward deepens each layer against a foundation that already proved it fits
together. The risk of a vertical slice is shallow foundations, so M2 (capture hardening) is scheduled
immediately after and is non-negotiable before any feature breadth work.

---

## Phase map

| Phase | Theme | Weeks (indicative) | Exit gate |
|---|---|---|---|
| **M0** | Foundations and spikes | 1–3 | Every platform assumption is measured, not assumed |
| **M1** | Vertical slice, all pillars | 4–11 | One real meeting travels Watch → phone → iPad → recap → confirmed action → export, offline-capable |
| **M2** | Capture hardening and recovery | 12–16 | Survival targets met under fault injection and on hardware |
| **M3** | Intelligence depth + cloud plane | 15–22 | Eval gates green; cloud opt-in path complete and auditable |
| **M4** | iPad canvas and Pencil | 20–26 | Ink↔audio linkage and merge-into-recap shipped |
| **M5** | Follow-through, sharing, integrations | 24–30 | Idempotent confirmed exports to Reminders/Calendar + 3 connectors |
| **M6** | Privacy, enterprise, launch readiness | 28–34 | All release gates in `docs/10` § 8 green |

M3 overlaps M2 and M4 overlaps M3 because they are largely different people. M1 does not overlap anything.

---

## M0 — Foundations and spikes (weeks 1–3)

**Purpose:** replace every assumption in this spec with a measurement, and make the repo productive.

Deliverables:

- Repo skeleton: `project.yml`, `Makefile`, all eleven packages compiling empty, CI running `make check`.
- `NSPCore` domain types and the meeting lifecycle state machine with property tests (no I/O yet).
- **Spike `NSP-002` — watchOS background recording.** On physical hardware across at least two Watch
  generations: 60- and 120-minute recording, wrist down, screen off, app backgrounded, phone powered off.
  Measure battery delta, thermal state, whether the process is suspended or terminated, and exactly which
  recording affordance (audio session configuration + recording intent + ongoing presentation) keeps it alive.
- **Spike `NSP-003` — codec and segment length.** Measure battery, file size, transfer overhead, ASR accuracy,
  and repair-loss window across the candidate matrix (AAC-LC vs HE-AAC × 16/24 kHz × 30/45/60 s).
- **Spike `NSP-004` — WatchConnectivity throughput.** Measure `transferFile` latency distribution, queue depth
  behaviour after long disconnection, delivery ordering, and behaviour across unpair/re-pair.
- **Spike `NSP-005` — on-device ASR and on-device summarization availability**, by OS version, language, and
  device class, including thermal behaviour on a long meeting.
- **Decision output:** minimum OS floor, codec, segment length, and the supported-device matrix, written into
  `docs/00` § 8 and `docs/reports/hardware-<date>.md`.

**Exit gate:** if a spike contradicts this spec, the spec is edited before M1 begins. No M1 ticket starts on an
unmeasured assumption about platform behaviour.

---

## M1 — Vertical slice (weeks 4–11)

**Definition of the slice:** a single user records one 30-minute in-person meeting from the Apple Watch with the
iPhone in another room; the meeting arrives on the iPhone and then the iPad; it gets a transcript, a Flash
Recap and an Executive Summary with working evidence links; the user types a note, confirms one action item
into Apple Reminders, and exports a Markdown recap. The whole path works with `ProcessingMode == .localOnly`.

Thin-but-real means: one summary template, one language, on-device ASR only, no diarization beyond
"speaker 1/2", no Pencil, no share links, no cloud plane, no third-party connectors.

**Actual sequencing as of 2026-08-20 diverged from this table** — worth knowing before trusting it at a glance.
Real work went iPhone-first and breadth-first rather than following the pillar order below: Today/Library/
Meeting-detail/Notes/Audio/Actions/Settings are all real and wired on iPhone (including a full cross-meeting
Actions dashboard and calendar-event creation — both listed as "deferred" in the table below, which is now
stale for iPhone specifically), markers are real editable notes, there's a live input-level meter, and a first
iPad shell (`PadRootView` + a v1 `PadRecordingCanvas`, see `docs/09-BACKLOG.md` M4's status note) exists. None
of Watch capture, transcription, summaries, diarization, sync, or sharing/export are built — the table's
sequencing logic (capture → transcript → recap → actions → export, across all three devices before going deep
on any one) was not what actually happened. Treat the table below as the intended shape, and `docs/09-BACKLOG.md`'s
per-milestone status notes as the source of truth for what's actually done.

| Slice component | What ships in M1 | What is deferred |
|---|---|---|
| Watch capture | Start/pause/resume/stop/marker, segments, manifest, durable ack | Complications, Smart Stack, recovery repair, battery preflight polish |
| Transfer | `transferFile` outbox, receipts, hash verify, dedupe | Reclamation policy tuning, multi-Watch, preview channel |
| Persistence | GRDB schema v1, repositories, FTS5 over transcript | Vector index, migrations beyond v1 |
| Sync | CloudKit private zone, meeting + segment + transcript records, assets | Sharing, partial-availability UX polish, key-reset handling |
| Transcription | On-device ASR, word timings, tap-to-audio | Diarization, multilingual, editing history, custom vocabulary |
| Summaries | Flash Recap + Executive Summary + actions, each with `EvidenceSpan`s | Templates, regeneration, Detailed Notes, chapters, Live Lens |
| Notes | Typed blocks with `creationRange`, private flag | Pencil, photos, merge-into-recap diff |
| Actions | Proposed → Confirmed → Sent to Reminders, idempotent | Owners/dates inference, dashboard, third-party destinations |
| Sharing | Markdown + JSON export with share preview | Links, roles, expiry, passcode |
| Privacy | `NSPPolicy` + `NetworkGate` + `.localOnly` enforced and audited | Redaction, retention jobs, enterprise policy |
| UX | Watch Ready/Recording/Paused/Finalizing; iPhone Today/Meeting/Transcript; iPad read-only meeting view | Ask, Library filters, Actions dashboard |

**Exit gate (all must be demonstrable on hardware, not simulator):**

1. Watch records 30 minutes with the paired iPhone powered off; nothing is lost.
2. No UI state shows `Recording` or "Saved" before the durable write (I1 test green).
3. Every action item in the recap resolves to playable audio and readable transcript (I4 test green).
4. `.localOnly` mode passes the network-content audit with zero meeting bytes egressing (I5 test green).
5. Confirmed action reaches Reminders exactly once, even when the export is retried (I6 test green).
6. `make check` green; package test suite runs in under two minutes.

---

## M2 — Capture hardening and recovery (weeks 12–16)

The slice proved the path exists. This phase makes it trustworthy.

- Full fault-injection harness: crash/kill at arbitrary points, disk-full, thermal throttle, permission
  revocation, delayed/dropped/duplicated WC delivery, CloudKit errors.
- Recovery algorithm complete: manifest validation, WAL replay, `.tmp` inspection, playable-boundary repair,
  `Recoverable` state with a disclosed missing tail.
- Preflight (storage estimate, battery threshold, permission and consent state) with warn-vs-block semantics.
- Sealed stop on thermal/battery/storage critical, with a final manifest transfer attempt.
- Reclamation policy in full (verified receipt ∧ (cloud policy satisfied ∨ local copy confirmed) ∧ grace).
- Multi-device arbitration: microphone-owner lease, explicit handoff, "control existing vs record separately".
- Route changes, interruptions, AirPods mid-meeting, incoming call, Low Power Mode.
- Live preview channel (explicitly labelled, never authoritative).
- Import path with provenance and original-timestamp handling.
- Complications, Smart Stack, Lock Screen widget, Control Center control, Siri and Shortcuts entry points.

**Exit gate:** survival targets from `docs/00` § 6 met under the fault-injection suite and the full soak run;
`TC-CAP-001` … `TC-CAP-014` and `TC-XFER-001` … `TC-XFER-008` green; hardware matrix results published.

---

## M3 — Intelligence depth and the cloud plane (weeks 15–22)

- Canonical batch transcription pass, word timings, punctuation, language spans, confidence.
- Diarization + speaker resolution (roster, self-voice enrollment, manual labels, rename scopes with preview).
- Transcript editing with revision history and confidence surfacing; find/replace; custom vocabulary.
- Layered outputs complete: Detailed Notes, chapters, takeaways, risks, decisions, open questions.
- Template library + custom templates + section regeneration with locked blocks + length/tone/audience.
- `EntailmentChecker` and the claim-downgrade rule wired into generation.
- Correction memory with inspect-and-forget.
- Multilingual and bilingual support with the separate translation view.
- Ask: single meeting and cross-meeting, mandatory scope selector, authorization-before-retrieval, citations.
- Backend: gateway, ASR/summarize/embed workers, grants, ephemeral processing copies, deletion receipts,
  streaming ASR over WebSocket, contract tests against `NSPBackendClient`.
- `Tools/evals` running in CI with the release-gating metrics.

**Exit gate:** eval gates in `docs/04` § 12 green; Stop → draft summary < 45 s median for a 60-minute English
meeting; cloud path fully opt-in, per meeting, with a deletion receipt the user can inspect.

---

## M4 — iPad canvas and Pencil (weeks 20–26)

- Split canvas/transcript workspace; all content block types; `creationRange` on every block.
- PencilKit ink capture, stroke-group timestamping, tap-a-stroke-to-seek within tolerance.
- Handwriting recognition and search; convert-to-text preserving ink.
- Private margin notes; merge-into-recap with an approved diff.
- Whiteboard/document photography with perspective correction and OCR.
- Stage Manager, multiwindow, keyboard shortcuts, external display presentation mode.
- Handoff and deep links; conflict-resilient note operation logs.

**Exit gate:** `NOT-002` stroke-seek tolerance test green; a full lecture scenario passes end to end; AI never
mutates a `NoteBlock` (enforced by test).

---

## M5 — Follow-through, sharing, and integrations (weeks 24–30)

- Action dashboard (mine, assigned by me, due, overdue, exported status); dependencies and status.
- Owner and due-date detection with inference labelling; unanswered-question queue; decision ledger with
  rationale, alternatives, and supersession.
- Follow-up email/message drafts that stay drafts until confirmed.
- Share modes: recap link with roles, expiry, revocation, optional passcode, download controls; section,
  action-only, and soundbite sharing; recipient preview generated from the export code path.
- Exports: PDF, DOCX, SRT/VTT, CSV, M4A, ZIP evidence bundle.
- Integration plane: OAuth broker + idempotent outbox + receipts; ship Reminders and Calendar (on-device) plus
  three server-brokered connectors chosen by demand (recommended: Slack, Notion, Linear).
- Public API and signed webhooks (beta).

**Exit gate:** `INT-002` idempotency test green (retry creates no duplicate); share preview provably equals the
recipient-visible payload; every external write audited.

---

## M6 — Privacy, enterprise, and launch readiness (weeks 28–34)

- Retention jobs, delete-raw-audio-after-approval, verifiable deletion workflow with cross-surface convergence.
- Redaction of text and time-aligned audio; redaction certificate; irreversible export option.
- Enterprise: SSO/SCIM, RBAC, workspace policy engine (required announcement, blocked domains/locations,
  forced local-only), admin audit views, retention policy enforcement.
- Sensitive-title protection; consent-event documentation; abuse reporting.
- Accessibility completion pass: full VoiceOver workflows, Dynamic Type on Watch, haptic equivalence, captions.
- Localization and RTL.
- Performance and battery sign-off against the published support matrix.
- App Review materials: recording intent narrative, background behaviour, privacy indicators, user value.
- Security review, threat-model verification tests, and external penetration test.

**Exit gate:** every item in `docs/10` § 8 release gates is green, on hardware, with results recorded.

---

## Cross-phase practices

- **Every phase ends with a hardware run.** Simulator-green is not phase-complete (`CLAUDE.md` § 7).
- **Every phase updates the docs it invalidated**, in the same PR that invalidated them.
- **Feature flags default off.** Incomplete work ships dark rather than living on a long branch.
- **The invariant gates run on every PR from M0 onward**, even before the features they protect exist — they
  start as failing-by-absence tests that turn green as the subsystem lands.

## Sequencing risks to watch

| Risk | Signal it is happening | Response |
|---|---|---|
| M0 spikes come back worse than assumed | Background recording is unreliable or battery cost is untenable | Re-scope the Watch promise *before* M1, and change the marketing claims with it. This is the single largest project risk. |
| M1 slice becomes M1 product | Tickets appear for templates, connectors, or Pencil during M1 | Cut them back to M3/M4/M5. The slice's value is that it is thin. |
| M2 gets compressed to reach feature demos | Fault-injection suite is "mostly" green | Do not proceed to M4/M5 breadth. Capture reliability is the product. |
| Eval quality plateaus in M3 | WER or evidence coverage stalls below gate | Escalate to model/provider change or scope reduction; do not ship an ungated AI claim. |
| iCloud quota complaints in beta | Users hit quota with a few dozen meetings | Bring audio-retention controls and bitrate optimization forward from M6. |
