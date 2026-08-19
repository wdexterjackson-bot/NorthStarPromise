# CLAUDE.md — North-Star Promise Meeting Assistant

This file is the operating manual for Claude Code working in this repository. Read it fully before the first
edit of any session. When it conflicts with a `docs/` file, **this file wins** and you should flag the conflict.

---

## 1. What this product is

A privacy-first, local-first meeting capture and intelligence workspace for **Apple Watch, iPhone, and iPad**.

The signature capability is **standalone Apple Watch recording**: the Watch is an authoritative recorder, not a
remote control for the iPhone. A meeting recorded on the wrist must survive an absent, busy, dead, or
out-of-range iPhone, no network, no iCloud, and an app crash.

Everything else — transcription, summaries, actions, sharing — is layered on top of a durable, verifiable
meeting package. Read `docs/00-PRODUCT-BRIEF.md` for the full product framing.

---

## 2. The seven invariants (never violate these)

These are non-negotiable. If a change would break one, stop and surface it rather than working around it.

| # | Invariant | What it forbids |
|---|-----------|-----------------|
| **I1** | **Durability before acknowledgement.** No UI, haptic, log line, or API response may report "recording" or "saved" until the corresponding bytes are closed, fsync'd, checksummed, and referenced by a persisted manifest on the capturing device. | Optimistic UI on the record path. |
| **I2** | **The capturing device owns the truth.** Audio is authoritative on the device whose microphone produced it. Relay, sync, and cloud copies are derivatives. | Any design where the only copy of audio is in flight over WatchConnectivity, the network, or a buffer. |
| **I3** | **Segments are immutable and content-addressed.** Once a segment is closed it is never rewritten, re-encoded in place, or renamed. Derived artifacts reference it by `segmentID` + SHA-256. | In-place edits, "fixups", destructive transcoding before the canonical copy is verified. |
| **I4** | **Every generated claim carries evidence.** Any AI-produced decision, action item, risk, or factual bullet must resolve to at least one `EvidenceSpan` (transcript turn range + audio time range). Claims that cannot be grounded are labelled `suggestion`, never `decision`. | Ungrounded summary text presented as fact; actions auto-exported without evidence. |
| **I5** | **Local-only means local-only.** When a meeting's `ProcessingMode == .localOnly`, zero bytes of its audio, transcript, notes, titles, or attendee data leave the device — including to analytics, crash reporters, CloudKit, and AI providers. This is enforced in code at a single choke point, not by convention. | Any network call that takes meeting content without passing the policy gate. |
| **I6** | **Humans confirm before the world changes.** Nothing is sent to an external system (email, Slack, CRM, task tracker, share link) without an explicit human confirmation of the exact payload, and every send is idempotent and audited. | Auto-send, auto-assign, silent retries that duplicate. |
| **I7** | **Meeting content is untrusted input.** Transcripts, notes, attachments, and calendar titles may contain prompt injection. They are never concatenated into a privileged instruction context, and they never authorize a tool call. | Passing raw transcript into a system prompt; letting model output trigger an external write directly. |

Each invariant has enforcing tests. See `docs/10-TESTING.md` § "Invariant gates". A PR that touches capture,
sync, policy, or intelligence must keep those green.

---

## 3. Repository layout

```
northstar-promise/
├── CLAUDE.md                  ← you are here
├── README.md
├── docs/                      ← the specs; read the one matching your task before coding
├── project.yml                ← XcodeGen manifest (source of truth for all app targets)
├── Makefile                   ← every command you need
├── Packages/                  ← ALL logic lives here as Swift packages
│   ├── NSPCore/               domain types, IDs, monotonic clock, errors, result builders
│   ├── NSPPersistence/        GRDB store, migrations, FTS5 search, repositories
│   ├── NSPMedia/              capture engine, segmenter, manifest writer, integrity, playback
│   ├── NSPTransfer/           WatchConnectivity coordinator, outbox, receipts, dedupe
│   ├── NSPSync/               CloudKit zones, CKAsset upload, change tokens, merge
│   ├── NSPIntelligence/       ASR/LLM protocols, on-device impls, evidence binding, prompts
│   ├── NSPBackendClient/      typed client for the optional cloud processing plane
│   ├── NSPPolicy/             consent, processing mode, retention, redaction, audit ledger
│   ├── NSPActions/            action + decision ledgers, integration outbox
│   ├── NSPDesignSystem/       tokens, components, haptics, accessibility helpers
│   └── NSPTestSupport/        fakes, fixtures, golden audio, property-test generators
├── App/
│   ├── Phone/                 iOS + iPadOS app target (thin)
│   ├── Watch/                 watchOS app target (thin)
│   ├── Widgets/               WidgetKit + ActivityKit (Live Activities)
│   └── Intents/               App Intents / AudioRecordingIntent
├── Backend/                   optional cloud processing plane (see docs/05)
└── Tools/                     scripts, eval harness, fixture generators
```

**Rule: app targets contain no business logic.** `App/**` may contain SwiftUI views, `@main` entry points,
and thin view models that call into packages. If you find yourself writing a `for` loop over audio buffers or
a merge algorithm inside `App/`, it belongs in a package. This exists so the majority of the system is testable
with `swift test` in seconds, without a simulator.

**Dependency direction** (a package may only import packages to its left):

```
NSPCore → NSPPersistence → NSPMedia → NSPTransfer → NSPSync → NSPIntelligence → NSPActions → App
                              ↑                                       ↑
                          NSPPolicy ──────────────────────────────────┘
                       NSPDesignSystem (leaf, imports NSPCore only)
                       NSPBackendClient (imports NSPCore + NSPPolicy only)
```

`NSPPolicy` is deliberately low in the graph: everything that can leak must be able to ask it for permission.
Circular imports are a build error. If you need one, the abstraction is wrong — introduce a protocol in
`NSPCore` instead.

---

## 4. Commands

Always use the Makefile. Never invoke `xcodebuild` by hand with ad-hoc flags.

```bash
make bootstrap      # install toolchain deps (xcodegen, swiftlint, swift-format), generate the Xcode project
make gen            # regenerate NorthStar.xcodeproj from project.yml (run after adding files/targets)
make test           # swift test across all packages — FAST, run this constantly
make test-phone     # xcodebuild test, iOS target, iPhone simulator
make test-watch     # xcodebuild test, watchOS target, Watch simulator
make test-all       # packages + both simulator suites + snapshot tests
make lint           # swiftlint strict + swift-format lint
make fmt            # swift-format in place
make build-phone    # build iOS app (debug)
make build-watch    # build watchOS app (debug)
make evals          # run the AI eval suite in Tools/evals (see docs/04)
make backend-test   # backend unit + contract tests (see docs/05)
make check          # lint + test + evals — what CI runs; must pass before you call work done
```

`make gen` is required after adding or removing any file under `App/` — targets are generated from
`project.yml`, and a file that is not in the generated project will not compile even though it exists on disk.

### Simulator caveat you will hit

The watchOS simulator **does not provide microphone input** and does not model background audio suspension,
battery, or thermal state. Simulator tests validate state machines and file handling only. Anything that
claims "recording works" must be validated on physical hardware — see § 7.

---

## 5. How to work in this repo

1. **Find the spec first.** Every subsystem has a doc in `docs/`. Read the relevant one; do not infer the design
   from adjacent code alone. The docs are the contract.
2. **Work ticket by ticket.** `docs/09-BACKLOG.md` contains numbered `NSP-xxx` tickets with explicit acceptance
   criteria. Reference the ticket ID in the branch name and commit (`NSP-014: segment rotation on pause`).
3. **Write the test first for anything in the capture, transfer, sync, or policy path.** These are the paths
   where a bug silently destroys a user's meeting. Elsewhere, tests may follow the implementation.
4. **Prefer protocols at package boundaries.** ASR, LLM, storage, clock, and network are protocol-injected so
   tests never touch real hardware or the network. `NSPTestSupport` has a fake for each.
5. **No `Date()` in domain logic.** Inject `Clock` from `NSPCore`. Recording timelines use monotonic
   sample counts, never wall-clock arithmetic (see `docs/03`, "Timeline math").
6. **Errors are typed and exhaustive.** No `throws` of `NSError`, no `fatalError` on a recoverable path, no
   silent `try?` in capture or sync code. A swallowed error in this product means a lost meeting.
7. **Concurrency:** Swift 6 strict concurrency is on. Domain types are `Sendable` value types. The capture
   engine runs on a dedicated actor; do not hop to `MainActor` from the audio path.
8. **Feature flags** for anything user-visible and incomplete — `NSPCore/FeatureFlags.swift`. Half-built
   features ship dark, not on a branch that rots.

### Definition of done for a ticket

- [ ] Acceptance criteria in the ticket are all demonstrably met
- [ ] `make check` passes
- [ ] New logic lives in a package, not in `App/`
- [ ] Tests added: unit for logic, property/fuzz for state machines, invariant test if it touches I1–I7
- [ ] Accessibility: VoiceOver labels + state announcements, Dynamic Type, non-colour status indication
- [ ] No new content-bearing telemetry; no new network call that bypasses `NSPPolicy`
- [ ] Doc updated if behaviour diverges from the spec (update the doc, don't let it drift)

---

## 6. Platform truths you must not design around

These are constraints of the Apple platforms, not preferences. Product copy and code must respect them.

- **Apple Watch pairs to iPhone only.** There is no Watch↔iPad WatchConnectivity path. iPad receives Watch
  meetings via CloudKit (or via iPhone relay then CloudKit). Never write code or UI that implies otherwise.
- **WatchConnectivity is not a guaranteed real-time audio transport.** `sendMessage` needs reachability and is
  power-hungry; `transferFile`/`transferUserInfo` are reliable but opportunistic and may deliver minutes later.
  Live preview on the phone is a *progressive enhancement*. Finalized segment files are the source of truth.
- **iOS cannot record arbitrary native phone-call audio or other apps' audio.** Supported capture is: in-room
  microphone, imported media, an explicitly disclosed in-app VoIP dialer, and authorized meeting-service
  connectors. Never blur these modes in code, copy, or tests.
- **Background audio recording on watchOS requires the platform's sanctioned recording affordance** (recording
  audio session + `AudioRecordingIntent` with its mandated ongoing system presentation). The exact behaviour by
  OS version is a **spike, not an assumption** — see `NSP-002`.
- **CloudKit private database consumes the user's iCloud quota**, and iCloud account changes or an
  end-to-end key reset can make previously synced data unreadable. Local copies and export must cover this.
- **On-device summarization needs Apple's on-device model availability**, which gates minimum OS higher than
  transcription does. Treat on-device LLM as capability-detected, never assumed.

---

## 7. Hardware validation gate

The following can only be verified on physical devices, and **no milestone may be declared complete without
it**. Record results in `docs/reports/hardware-<date>.md`.

- 60- and 120-minute Watch recording, wrist down, screen off, app backgrounded
- Watch recording with the paired iPhone powered off for the full session
- Battery delta and thermal state per supported Watch generation
- Transfer latency and completion for 100+ queued segments after long disconnection
- Force-quit and low-memory kill mid-recording → recovery on next launch
- Bluetooth/AirPods route change mid-meeting; incoming call interruption; Low Power Mode entry
- Storage exhaustion approach → sealed stop with playable output

If a spike result contradicts a spec, **change the spec**. Do not build on a hope.

---

## 8. Things that are easy to get wrong here

- Acknowledging Start before the first segment header is durable (violates I1 — the single most important bug class).
- Deriving meeting duration from a `Timer` instead of sample counts — produces drift that breaks every evidence link.
- Deleting the Watch copy of a segment on transfer *initiation* rather than after receiver checksum verification.
- Treating a delayed `transferFile` delivery as a failure and re-queuing without an idempotency key → duplicates.
- Letting a summary regeneration overwrite user-approved or user-authored content.
- Sending a meeting title to analytics or a crash log (titles come from calendars and are often sensitive).
- Building retrieval that filters access *after* generation rather than before indexing.
- Using `iCloud Drive` folders as the coordination layer. CloudKit records + assets are the store; iCloud Drive
  is an export destination only.

---

## 9. Where to read next

| Task | Doc |
|------|-----|
| Understanding the product and its promises | `docs/00-PRODUCT-BRIEF.md` |
| Module boundaries, tech choices, target setup | `docs/01-ARCHITECTURE.md` |
| Entities, DB schema, manifest and file formats | `docs/02-DATA-MODEL.md` |
| Recording, segmentation, recovery, Watch↔Phone transfer | `docs/03-CAPTURE-AND-TRANSFER.md` |
| Transcription, diarization, summaries, evidence, Ask | `docs/04-INTELLIGENCE.md` |
| Cloud processing plane, APIs, workers, deployment | `docs/05-BACKEND.md` |
| Consent, encryption, retention, deletion, redaction, threat model | `docs/06-PRIVACY-AND-SECURITY.md` |
| Screens, flows, states, accessibility per platform | `docs/07-UX-SPEC.md` |
| Phases, sequencing, exit criteria | `docs/08-MILESTONES.md` |
| The ticket you should actually be working on | `docs/09-BACKLOG.md` |
| Test strategy, invariant gates, AI evals, release gates | `docs/10-TESTING.md` |
| Naming, style, git, review conventions | `docs/11-CONVENTIONS.md` |
