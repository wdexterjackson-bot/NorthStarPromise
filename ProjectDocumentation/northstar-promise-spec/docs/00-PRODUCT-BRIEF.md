# 00 — Product Brief

**Product:** North-Star Promise Meeting Assistant
**Platforms:** watchOS, iOS, iPadOS (macOS out of scope for v1; see § 7)
**Source of record:** this document + the feature design doc it was derived from
**Status:** engineering-ready. Platform behaviours marked ⚠️ require a hardware spike before commitment.

---

## 1. The promise

> Start a meeting from your wrist, capture it reliably without occupying your iPhone, and leave with
> trustworthy notes, decisions, owners, and evidence-linked follow-through.

Every engineering decision in this repo should be traceable to one of five pillars.

| Pillar | Promise to the user | What it forces in the code |
|--------|--------------------|-----------------------------|
| **Capture certainty** | If the UI says recording, recoverable audio exists. | Local-first segmented writes, durable manifests, health telemetry, crash recovery. |
| **Trustworthy intelligence** | You can verify and correct anything the AI says. | Evidence spans on every claim, confidence surfacing, revision history, correction memory. |
| **Apple-native freedom** | Use whichever device is on you, without ceremony. | Watch-first controls, universal SwiftUI app, widgets, App Intents, CloudKit. |
| **Privacy by design** | Private by default; processing is legible. | Per-meeting processing mode, encrypted local storage, retention controls, auditable exports. |
| **Work after the meeting** | Notes cause action, not storage debt. | Action/decision ledgers, owner and date extraction, confirmed idempotent exports. |

---

## 2. The market gap we are attacking

Otter, Notta, and Fireflies have converged on transcript → summary → search → chat. All three are cloud-first
and phone-or-desktop-first. Granola proved bot-free in-person capture is desirable; Goodnotes proved
handwriting-linked-to-audio is delightful; Meeting Intelligence proved lightweight live context has value.

**Nobody owns dependable wrist capture, and nobody has made evidence-linking the product's spine.**

Our two structural differentiators, in priority order:

1. **The Watch is a real recorder.** Not a remote. A meeting that starts on the wrist survives an absent phone,
   no network, and a crash. Competitors either lack Watch capture or treat the Watch as a trigger.
2. **Local-first with an auditable privacy boundary.** The canonical store is the user's devices and their
   private iCloud. Cloud AI is opt-in, per meeting, ephemeral, and verifiable by network inspection.

Everything else is table stakes we must reach parity on — and we should be honest internally that parity on
transcription quality, templates, and integrations is a large amount of the work, even though it is not the
differentiator.

---

## 3. Personas and their critical needs

| Persona | Primary job | Critical needs | Drives which features |
|---|---|---|---|
| **Mobile leader** | Move between rooms without losing commitments. | Two-second Watch start, one-minute recap, delegated actions, confidentiality. | Watch capture, Flash Recap, action ledger, sensitive-title hiding. |
| **Consultant / researcher** | Capture nuanced interviews and retrieve evidence later. | High-fidelity audio, speaker labels, custom vocabulary, citations, export. | Offline capture, diarization, glossary, evidence bundle export. |
| **Sales / CS** | Turn conversations into CRM updates and next steps. | Templates, objection tracking, follow-up drafts, controlled integrations. | Summary templates, action confirmation, idempotent CRM write-back. |
| **Student / educator** | Combine lecture audio with handwritten notes. | Pencil↔audio sync, chapters, glossary, study outputs, accessibility. | iPad canvas, ink timestamping, chapters. |
| **Regulated professional** | Record only when permitted; minimize exposure. | Consent tooling, local-only mode, retention policy, redaction, audit trail. | `NSPPolicy` in full. |

## 4. Jobs to be done (verbatim from research, kept as acceptance framing)

- When a meeting begins unexpectedly, let me capture it in **under two seconds** from the device already on me.
- When I lower my wrist or leave my phone elsewhere, **preserve the entire recording** and show unmistakable status.
- When reviewing, let me **understand the outcome in one minute** and verify any claim instantly.
- When I take a note or mark a moment, treat it as **stronger intent** than an inferred highlight.
- When a commitment is made, help identify **owner, due date, dependency, destination** — then let a human confirm.
- When information is sensitive, let me choose **local-only** capture and delete raw audio while keeping approved notes.

---

## 5. Scope

### In scope — core (must work with no bots, no accessories, no network)

In-person capture on Watch/iPhone/iPad · segmented recovery · transcription · speaker labels · layered summaries ·
typed and handwritten notes · evidence links · CloudKit sync · export · consent tooling.

### In scope — optional, independently permissioned

Calendar context · templates · team spaces · task ledger · share links · iPad Pencil canvas · custom vocabulary ·
bilingual transcription · Live Lens · third-party integrations · online-meeting assistant · conversation
intelligence · enterprise policy · public API and webhooks.

### Explicitly not supported

- Recording arbitrary native iOS phone calls or other apps' audio.
- Covert capture, or any flow that hides the recording state.
- Unbounded autonomous external actions (sending, assigning, or writing to third-party systems without confirmation).

### Deferred past v1

macOS botless desktop capture · in-app VoIP dialer · Android/web clients · real-time multi-user co-editing of
the note canvas (v1 is last-writer-wins per block with operation logs, not full CRDT co-presence).

---

## 6. Success definition

These are the numbers that decide whether v1 shipped or merely launched.

| Metric | Target | Notes |
|---|---|---|
| Recording survival, normal stop | ≥ 99.95 % | Sessions ended normally produce a complete playable package. |
| Recording survival, after interruption/crash | ≥ 99.5 % | Recoverable with disclosed gap; never silently discarded. |
| Stop → draft summary (60-min English, networked) | < 45 s median | Transcript preview begins < 5 s when live processing enabled. |
| Evidence coverage | ≥ 90 % of summary bullets, **100 % of actions** | Valid, resolvable evidence anchor. |
| Watch-started meeting completion rate | within 2 pp of iPhone-started | The differentiator must not be the flaky path. |
| Week-8 retained team behaviour | ≥ 3 meetings/user/week reaching approved recap or confirmed actions | The north-star engagement metric. |
| Watch Start acknowledgement | ≤ 2 s p95 **after durable write** | Never acknowledge earlier (Invariant I1). |

Guardrails that must not regress: crash-free recording rate, battery drain per Watch generation, false
decision/action rate, accidental-share reports, cost per processed hour.

---

## 7. Architectural decisions already made (do not relitigate without data)

1. **Watch records locally to independent segments.** No design where the only copy streams to the phone.
2. **CloudKit private database + CKAssets is the canonical sync layer.** Not iCloud Drive folders.
3. **Transcript is evidence; summary is a view.** Generated prose is never the only durable artifact.
4. **Human notes are a separate, priority channel.** AI proposes merges with a diff; it never overwrites ink or typed text.
5. **Cloud AI is per-meeting opt-in with ephemeral processing copies and no training on customer content.**
6. **Approval-first automation.** Rules and automation come after trust, always with preview, log, and rollback.

## 8. Open decisions (need data before locking)

| Decision | Working default | What resolves it |
|---|---|---|
| Minimum OS versions | Set after the recording spike; prefer the floor that gives consistent recording-intent + Live Activity behaviour. | `NSP-002` spike + App Store device coverage. |
| Watch codec and segment length | Speech-optimized compressed audio, 30–60 s segments. | Battery, transfer overhead, ASR accuracy, and repair-loss-window measurements. |
| On-device LLM for summaries | Offer where the on-device model is available; cloud opt-in for quality/languages. | Model availability, thermal, quality evals. |
| External sharing model | CloudKit sharing for Apple-native collaboration; service-hosted links for external recipients. | External identity UX + enterprise requirements. |
| Application-layer encryption tier | Only for the high-sensitivity tier if compatible with search and sharing. | Key recovery, retrieval, support burden. |
| Business model | Free capture + limited processing; Pro intelligence; Team admin/integrations. | Cloud cost per processed hour, pricing research. |

---

## 9. Advertised claims → the code that must back them

Marketing has already committed to these. Each maps to a hard acceptance test; if the test is not green, the
claim comes down.

| Advertised claim | Backing requirement |
|---|---|
| "Record complete meetings from Apple Watch — without your iPhone." | `CAP-001`, `CAP-002`, hardware gate with phone powered off. |
| "Phone-free, offline recording; recoverable local recording." | `CAP-003` crash/kill recovery test. |
| "Every summary backed by the exact words that were spoken." | `SUM-001` evidence coverage gate (100 % of actions). |
| "Private by default. Stored locally or securely in your iCloud." | `PRV-001` network-content audit in local-only mode. |
| "Works offline and transfers automatically when devices reconnect." | `SYN-001` + transfer dedupe/idempotency tests. |
| "Write with Apple Pencil while every note stays connected to the audio." | `NOT-002` stroke-group seek tolerance test. |
| "Search every meeting like a document — and ask questions across them." | `AI-001` authorization-before-retrieval + citation coverage. |
| "One meeting workspace across Watch, iPhone, and iPad." | `SYN-001`; iPad must clearly communicate Watch-relay latency. |

> **Copy discipline:** no marketing surface may claim call recording, live Watch→iPad streaming, or a single
> normalized accuracy number. See `CLAUDE.md` § 6.
