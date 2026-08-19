# 10 — Testing, Invariant Gates, and Release Criteria

This document defines what "tested" means in this repository. It is binding: the checklists in § 8 are the
ship gate, and the tests named in § 2 are the enforcement mechanism for the seven invariants in `CLAUDE.md` § 2.

---

## 1. The shape of the pyramid (and why it is odd here)

A conventional iOS pyramid puts a large mass of tests in the simulator because that is where the app lives.
Here the app does not live there. `App/**` is deliberately thin — SwiftUI views, `@main`, and view models that
forward to packages (`CLAUDE.md` § 3). Everything with a failure mode that loses a meeting lives in
`Packages/`, which means it is reachable by `swift test` with no simulator, no device, and no signing.

```
                 ┌──────────────────────────────┐
   MANUAL GATE   │  Physical device validation  │   ~2–4 h/milestone, human, mandatory
                 │  (CLAUDE.md § 7)             │   no automation substitutes for it
                 ├──────────────────────────────┤
   THIN          │  Simulator: UI flows,        │   ~8–12 min
                 │  snapshots, integration      │   state machines + file handling only
                 ├──────────────────────────────┤
   THE MASS      │  Package tests: `swift test` │   ~90 s target, run constantly
                 │  unit · property · fuzz ·    │   >85 % of total assertions
                 │  invariant gates · evals     │
                 └──────────────────────────────┘
```

Three consequences you must internalize:

1. **`make test` is the inner loop.** It must stay under ~90 seconds wall-clock for the whole package graph. If
   a suite pushes past that, it is either doing I/O it should be faking or it belongs in the nightly soak job.
2. **The simulator layer is thin by design and is not evidence of anything acoustic.** The watchOS simulator
   provides no microphone input and does not model background audio suspension, battery, or thermal state
   (`CLAUDE.md` § 4). A green simulator suite proves that state machines advance and files land correctly. It
   proves nothing about whether recording works.
3. **The device gate is a real gate, not a smoke test.** The pyramid is inverted at the top: the highest-value,
   least-automatable validation is a human with hardware, and no milestone is complete without it. Results are
   recorded in `docs/reports/hardware-<date>.md` and referenced by the release checklist.

The inversion is intentional: this product's headline claim — the Watch is an authoritative recorder — is a
claim about physics and OS scheduling, not about code paths, and it can only be falsified on a wrist.

---

## 2. Invariant gates

Each invariant has at least one test that fails loudly and specifically when the invariant is broken. These
tests are not refactorable away; changing one requires changing `CLAUDE.md`.

### I1 — Durability before acknowledgement

| Test | Location | Failure mode |
|---|---|---|
| `test_captureSession_startWithSlowFsync_doesNotEnterRecordingBeforeHeaderDurable` | `NSPMediaTests/DurabilityGateTests.swift` | Fails if the state machine emits `.recording` before the fake `FileSystem` records an `fsync` on segment 0's header. |
| `test_stateMachine_ackOrdering_property` | `NSPCoreTests/LifecycleInvariantTests.swift` | Property test over random `arm/start/fail` orderings; asserts the durable-write event always precedes the first `.recording` observation in the emitted event log. |
| `test_watchStartUI_noSavedAffordanceBeforeSeal` | `NorthStarWatchTests` (simulator) | Snapshot + accessibility-tree assertion: no view exposes "Recording" or "Saved" text or haptic while the injected segmenter is blocked. |

The mechanism: `NSPTestSupport.RecordingFileSystem` wraps every write/fsync/rename with a monotonically ordered
event, and `AckOrderingAssertion` diffs the file-event stream against the UI/haptic event stream. Any UI event
whose index precedes its corresponding durability event is a hard failure with both streams printed.

### I2 — The capturing device owns the truth

`test_transfer_reclamation_requiresVerifiedReceipt` and `test_transfer_neverDeletesBeforeVerification`
(`NSPTransferTests/ReclamationTests.swift`) drive the full outbox with the WatchConnectivity fake and assert
that a `Segment` may leave `.verified` for `.reclaimed` only when a verified receipt exists **and** the
retention grace has elapsed. A companion audit test walks `NSPTransfer` and `NSPMedia` sources for any
filesystem delete call not routed through `ReclamationPolicy` and fails on a match.

### I3 — Segments are immutable and content-addressed

`test_segment_afterClose_isNeverReopenedForWriting` uses the recording file system to assert no write handle is
ever opened on a path that has been renamed to its final name. `test_segment_hashStability_acrossRepair`
asserts a repaired tail produces a *new* `segmentID` and hash rather than mutating the original.

### I4 — Every generated claim carries evidence

`test_evidenceCoverage_allActions_resolve` (`NSPIntelligenceTests/EvidenceCoverageTests.swift`) runs the full
summarize→bind→verify pipeline over every fixture meeting and asserts:
- 100 % of `Action` and `Decision` rows leaving `Proposed` carry ≥ 1 `EvidenceSpan`;
- every span resolves to a live transcript turn range **and** a playable sample range, or is explicitly marked
  stale;
- any `Insight` with empty evidence has `claimKind == .aiSuggests`.

Failure output names the offending insight ID, layer, and the unresolvable span. The same assertion runs as a
gating metric in the eval harness (§ 6) against the full corpus, not just fixtures.

### I5 — Local-only means local-only

Two independent gates, because one is a code-shape check and the other is a behavioural check.

1. **Architecture test** — `test_architecture_networkImportsRestricted` (`NSPCoreTests/ArchitectureTests.swift`)
   parses every source file in `Packages/` and `App/` and fails the build if `URLSession`, `Network`,
   `CloudKit`, or a third-party HTTP symbol is imported outside the allow-list (`NSPBackendClient`, `NSPSync`,
   and `NSPPolicy.NetworkGate`). It also fails on any import that would create a cycle or violate the
   left-to-right dependency direction in `CLAUDE.md` § 3.
2. **Network-content audit** — `PRV-001`, in `NorthStarPhoneTests/NetworkAuditTests.swift`, launches the app
   with `ProcessingMode` forced to `.localOnly`, points it at a recording HTTP/HTTPS proxy with a trusted test
   root, drives a full record→process→review→export cycle against a fixture whose audio contains unique
   watermark tokens and whose title/attendees are unique sentinel strings, then asserts **zero** occurrences of
   any watermark or sentinel in the complete request corpus (bodies, headers, query strings, DNS names) and
   zero requests to non-allow-listed hosts. Crash reporter and analytics endpoints are included in the capture.

The `LocalOnly` build configuration compiles `NSPBackendClient` out entirely; `make test LOCAL_ONLY=1` runs the
whole package suite in that configuration to prove the local path has no cloud dependency.

### I6 — Humans confirm before the world changes

`test_actionOutbox_requiresExplicitConfirmation` asserts an `Action` cannot be enqueued while any field is
`.unresolved` or `.inferred` without a confirmation record naming the exact payload hash.
`test_actionOutbox_replayIsIdempotent` replays every outbox message 1–5 times in random order and asserts a
single `IntegrationReceipt` and a single external write per `(actionID, destination, revision)` key.

### I7 — Meeting content is untrusted input

`NSPIntelligenceTests/PromptInjectionTests.swift` runs a corpus of injection payloads embedded in transcript
turns, note blocks, calendar titles, attachment filenames, and glossary terms. Assertions: content is never
placed in the privileged instruction region of a rendered prompt (verified structurally against the composed
prompt object, not by string search); no model output can reach a connector without passing through the
confirmation gate; and tool-call requests originating from model output are rejected with a typed error.

---

## 3. Suites by area

| Suite | Lives in | Covers | Runs |
|---|---|---|---|
| **Media unit** | `NSPMediaTests` | Segment rotation at boundary and on pause/interrupt/stop, atomic close ordering, SHA-256 and stream hash, manifest write/seal/replay/`.bak` fallback, pause-gap accounting, sample↔time conversion at 16/44.1/48 kHz, truncated-tail repair, gapless playback seek accuracy | PR |
| **State / property** | `NSPCoreTests` | Random sequences of `start/pause/resume/interrupt/routeChange/stop/crash` against the § 3 lifecycle invariants; idempotency of replayed commands; `Σ sampleCount + gaps == canonicalDuration` | PR |
| **Persistence** | `NSPPersistenceTests` | Migration up/down for every numbered migration, FTS trigger exclusion for `excluded_from_memory`/`deleted_at`, tombstone and purge, crash-safe write helpers, 100 K-meeting paged query budgets | PR |
| **Connectivity** | `NSPTransferTests` | Duplicate, out-of-order, delayed (minutes), and dropped file/message delivery; re-pair and session invalidation; multi-Watch activation; receipt loss; outbox persistence across relaunch | PR |
| **Sync** | `NSPSyncTests` | Offline concurrent edits on two device fakes, field-level and op-log merge, CloudKit quota-exceeded, account signed-out, end-to-end key reset, zone deletion, partial availability, asset dedupe by hash | PR |
| **Policy / security** | `NSPPolicyTests` | Tenant and workspace isolation, share-grant escalation attempts, expiry and revocation, redaction leakage (text *and* audio interval), export authorization, audit ledger completeness, authorization-before-retrieval | PR |
| **AI evals** | `Tools/evals` | WER, DER, entity accuracy, evidence entailment, hallucinated decision/action rate, multilingual and code-switching | Nightly + pre-release |
| **Accessibility** | `NorthStar*Tests` | Full VoiceOver workflows (start, pause, mark, stop, review, confirm action, export) on Watch/phone/pad; Dynamic Type to AX5 without truncation or clipping; contrast; haptic↔visual↔spoken state equivalence for every recording state | PR (static) / nightly (full) |
| **Performance** | `PerformanceTests` | Budgets in `docs/01` § 8: start→ack ≤ 2 s p95, meeting open ≤ 1 s p95, seek ≤ 300 ms, 60 fps on a 3-hour transcript, cold launch ≤ 1.5 s, Watch memory ceiling | Nightly |
| **Soak** | `Tools/soak` | 8-hour import, 10 000+ segment meeting, week-long simulated transfer queue with intermittent reachability, 30-day retention/purge clock | Nightly (long) |

---

## 4. Fault injection

`NSPTestSupport.FaultInjector` is a deterministic, seed-driven harness. Every injectable fault is addressed by a
named **injection point** that production code declares once (`#faultPoint("segment.close.preRename")`) and
which compiles to a no-op in Release.

| Class | Injectable | Example point |
|---|---|---|
| Process | `crash`, `SIGKILL`, background suspension, low-memory kill | `segment.close.preFsync`, `manifest.seal.midRename` |
| Storage | disk-full at write/fsync/rename, read-only volume, corrupted byte range, missing file, Data Protection unavailable (locked) | `segment.write.frame`, `manifest.wal.append` |
| System | thermal `.serious`/`.critical`, Low Power Mode entry, battery threshold, audio interruption, route change, permission revocation mid-session | `capture.tick` |
| Connectivity | delay (0 s–7 d), drop, duplicate ×N, out-of-order, corrupt payload, session deactivate/reactivate, counterpart app not installed | `transfer.file.deliver` |
| CloudKit | `quotaExceeded`, `notAuthenticated`, `zoneNotFound`, `changeTokenExpired`, `serverRecordChanged`, `limitExceeded`, partial failure, throttle with retry-after | `sync.batch.submit` |

A fault schedule is `[(injectionPoint, occurrence, fault)]` plus a seed, so any failing scenario is reproduced
by pasting the seed into `test_replay(seed:)`.

**Property-based fuzzing of the capture state machine.** `CaptureCommandGenerator` produces random command
sequences drawn from `{start, pause, resume, mark, interrupt(cause), routeChange, thermal, stop, crash, relaunch}`
with weighted lengths of 1–500, interleaved with a random fault schedule. After each run the harness performs
full recovery from disk and asserts the lifecycle invariants from `docs/02` § 3 hold — in particular that every
crash leaves the meeting **recoverable with a disclosed missing tail**, never silently short and never with a
corrupt manifest. Shrinking reduces a failure to a minimal command+fault sequence before reporting.

---

## 5. Golden fixtures

Fixtures live in `Packages/NSPTestSupport/Fixtures/` and `Tools/fixtures/` (generators).

- **Generated tone audio.** Deterministic WAV/M4A with a distinct tone burst at every 100 ms boundary and an
  encoded sample index. Timestamp math, segment-boundary alignment, gapless playback, pause-gap accounting, and
  evidence-span resolution are all verified by decoding the tone and comparing the recovered sample index to
  the claimed one. Tolerance is asserted in samples, never in seconds.
- **Consented speech corpus,** organized by tier so failures are attributable:
  `t1-quiet` · `t2-conference-room` · `t3-cafe-noise` · `t4-far-field` · `t5-accents` · `t6-overlap` ·
  `t7-bilingual`. Every clip carries a signed consent record and a licence file; provenance is in
  `CORPUS.md`.
- **Fixture meeting packages** at each shipped `manifest.version` and each DB schema version, used to test
  migrations forward and export-schema stability. A new migration ships with a new fixture and keeps the old
  ones.
- **Injection corpora** for prompt-injection and redaction-leakage tests.

**Rule: no real customer audio, transcript, title, or attendee data is ever committed to this repository, in
any branch, for any reason.** Reproducing a customer issue means constructing a synthetic fixture that
exhibits the same shape. A commit containing audio outside `Fixtures/` fails the pre-commit hook and CI.

---

## 6. The AI eval harness (`Tools/evals`)

Run with `make evals`. The harness is a Python driver over the same Swift interfaces the app uses, executed
against both the on-device path and (when a grant is present) the processing plane.

```
Tools/evals/
├── datasets/<dataset>/<case-id>/   audio.m4a · reference.json · expectations.json
├── suites/                          transcription.yml · diarization.yml · summarization.yml · safety.yml
├── pins.lock                        model IDs+versions, promptVersion, templateVersion, decoding params, seed
├── runner/
└── reports/<run-id>/                metrics.json · per-case.jsonl · diff-vs-baseline.md
```

`reference.json` holds ground-truth transcript with word timings, speaker turns, entities, and the accepted set
of decisions/actions. `expectations.json` holds per-case thresholds where a case is deliberately harder than
the suite default.

**Gating metrics** (suite-level, compared against the stored baseline):

| Metric | Gate |
|---|---|
| WER, tiers t1–t2 | ≤ baseline + 1.0 pp absolute |
| WER, tiers t3–t5 | ≤ baseline + 2.0 pp absolute |
| DER (diarization error rate) | ≤ baseline + 2.0 pp |
| Entity accuracy (names, dates, amounts, decisions' owners) | ≥ baseline − 1.0 pp |
| Evidence entailment pass rate | ≥ 98 %, and never below baseline |
| Hallucinated decision/action rate | ≤ 1.0 % and ≤ baseline |
| Evidence coverage: actions | **100 %** (hard, non-negotiable — I4) |
| Bilingual/code-switch WER (t7) | ≤ baseline + 2.0 pp |

**Comparability.** Every run pins model ID and version, prompt version, template ID and version, decoding
parameters, and the RNG seed in `pins.lock`, and stamps them into `metrics.json`. A run whose pins differ from
the baseline's pins is reported as *incomparable*, not as a pass or a regression: the operator must re-baseline
deliberately, which is a reviewed commit to `pins.lock` with the new `reports/<run-id>/` attached. This is why
provenance is a first-class field on `Insight` (`docs/02` § 2).

**Regression handling.** `make evals` exits non-zero on any gate breach and writes `diff-vs-baseline.md` with
the worst 20 per-case regressions. CI blocks the merge. The only ways forward are fix the regression, or
re-baseline with an explicit reviewer sign-off recorded in the PR description.

---

## 7. Device and environment matrix

Physical validation (`CLAUDE.md` § 7) sweeps this matrix. Not every cell every milestone; the **bold** cells
are mandatory each milestone, the rest rotate.

| Axis | Values |
|---|---|
| Watch | **Current gen (cellular)**, current gen (GPS-only), current − 1, **oldest supported gen**, Ultra variant |
| iPhone | **Current gen**, current − 2, **oldest supported**, one Pro and one non-Pro |
| iPad | Compact (mini/Air) and full-size Pro; **with Pencil**, with Magic Keyboard, **Stage Manager on**, external display attached |
| Acoustic | Quiet office · conference room at 1 m and 4 m · café · car · large hall · HVAC hum |
| Speakers | **1, 2, 4**, 8, 12 — with overlapping speech, cross-talk, and mixed accents; at least one bilingual session |
| Connectivity | Paired+reachable · **iPhone out of range** · **iPhone powered off for the full session** · airplane on/off transitions mid-recording · Wi-Fi only · cellular Watch without phone · CloudKit reachable/unreachable |
| System state | **Screen locked / wrist down for ≥ 60 min** · app switched away · incoming call · Siri invoked · alarm/timer · **Low Power Mode** · low storage approaching exhaustion · thermal pressure to `.serious` · OS point-update migration with an in-progress meeting |
| Duration | 5 min · **60 min** · **120 min** · 8 h import |

Every run records: recording survival, disclosed vs. undisclosed gaps, battery delta per generation, thermal
peak, transfer latency and completion for the queued backlog, memory high-water mark, and any user-visible
state that was wrong or absent. Results go in `docs/reports/hardware-<date>.md`. A contradiction between a
spike result and a spec changes the spec (`CLAUDE.md` § 7).

---

## 8. Release gates

Every item must be green, with a named artifact (test run, report, or signed checklist), before a build ships.

- [ ] **G1 — Watch standalone.** `TC-CAP-001`/`TC-CAP-002` green, plus a device run of a ≥ 60-minute Watch recording
      with the paired iPhone **powered off** for the entire session, producing a complete playable package.
- [ ] **G2 — No premature acknowledgement.** I1 gates green on package and simulator suites; manual sweep
      confirms no surface (UI text, haptic, complication, Live Activity, log line, App Intent response) says
      recording or saved before the corresponding durable write.
- [ ] **G3 — Recovery.** `TC-CAP-003` green: force-quit, low-memory kill, and disk-full mid-recording each recover
      on next launch with a *disclosed* missing tail and a playable output.
- [ ] **G4 — Cross-device workspace.** `SYN-001` green: iPad receives a Watch-originated meeting via CloudKit,
      shows `Partial` with the exact missing segments and the device that holds them, and states relay latency
      honestly. No surface implies a Watch↔iPad direct link.
- [ ] **G5 — Local-only network audit.** `PRV-001` green: zero meeting bytes, titles, or attendee data egress in
      `.localOnly`, including analytics and crash reporting. Architecture test green.
- [ ] **G6 — Evidence and confirmation.** 100 % of actions and decisions carry resolvable evidence; every
      inferred field is visibly labelled; ambiguous owner/date/destination blocks export until confirmed;
      outbox replay produces no duplicates.
- [ ] **G7 — Consent and state visibility.** Recording state is visible and non-colour-only on every surface;
      consent tooling reachable; full VoiceOver workflow passes on Watch, iPhone, and iPad; Dynamic Type to AX5
      without loss.
- [ ] **G8 — Sync failure honesty.** Quota exceeded, signed-out, and end-to-end key reset each produce an
      explicit, actionable state that preserves the local copy and explains recoverability and export.
- [ ] **G9 — Export and deletion completeness.** Export enumerates exactly what leaves the workspace, generated
      from the export code path itself; deletion covers audio, derived artifacts, indexes, embeddings, cloud
      records and assets, processor copies, **and pending device transfer queues**, each producing a receipt.
- [ ] **G10 — Physical results within the published support matrix.** Battery delta, thermal peak, storage
      behaviour, and 60/120-minute session results per Watch generation meet the numbers we publish. If they
      do not, the support matrix changes before the build ships.
- [ ] **G11 — Eval gates.** `make evals` green against the current pins, with no incomparable-run ambiguity.
- [ ] **G12 — App Review materials.** Recording intent, background audio usage, ongoing system presentation,
      microphone and speech purpose strings, and consent copy are current and match observed behaviour.

---

## 9. CI configuration

| Stage | Runs | Target duration |
|---|---|---|
| **Pre-commit (local hook)** | `make lint`, changed-package `swift test`, fixture-audio guard | < 30 s |
| **Every PR** | `make lint` · `make test` · `make test LOCAL_ONLY=1` · architecture + invariant gates · `make test-phone` · `make test-watch` on the latest OS simulator · snapshot tests · `LocalOnly` configuration build · `make backend-test` if `Backend/**` touched | **≤ 15 min** |
| **Merge to `main`** | PR set + previous-OS simulator matrix + performance budget assertions | ≤ 25 min |
| **Nightly** | Full matrix (latest and previous iOS/watchOS) · `make evals` full corpus · fuzz campaign with a fresh seed budget (10 000 sequences) · soak: 8-hour import, 10 000-segment meeting, week-long simulated transfer queue · memory/leak instrumentation | ≤ 6 h |
| **Pre-release** | Nightly set + extended fuzz (100 000 sequences) · migration matrix across every shipped schema and manifest version · accessibility full sweep · localization pseudo-loc and RTL pass · export/deletion completeness audit · release-gate checklist § 8 | ≤ 12 h + manual device gate |

Flake policy: a test that fails non-deterministically is quarantined with a ticket within 24 hours and either
fixed or deleted within one sprint. Quarantine is not a parking lot — a quarantined invariant gate (§ 2) blocks
release outright.
