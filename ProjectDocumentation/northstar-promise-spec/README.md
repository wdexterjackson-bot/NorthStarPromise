# North-Star Promise Meeting Assistant — Engineering Bootstrap Kit

> Start a meeting from your wrist, capture it reliably without occupying your iPhone, and leave with
> trustworthy notes, decisions, owners, and evidence-linked follow-through.

This repository is the specification bundle for building a privacy-first, local-first meeting capture and
intelligence workspace for **Apple Watch, iPhone, and iPad**. It is written to be handed directly to Claude Code
(or any engineer) as the starting point for implementation.

Nothing here is built yet. This is the plan, at the level of detail where coding can begin immediately.

---

## Start here

1. **`CLAUDE.md`** — the operating manual. Read it fully before the first edit. It contains the seven invariants
   the product cannot violate, the module boundaries, the build commands, and the platform truths you must not
   design around.
2. **`docs/09-BACKLOG.md`** § Appendix B — the first week of work, in order.
3. **`docs/08-MILESTONES.md`** — how the whole thing sequences, and why M0's hardware spikes gate everything.

---

## The document set

| File | What it settles |
|---|---|
| `CLAUDE.md` | Invariants, module graph, commands, definition of done, platform constraints |
| `docs/00-PRODUCT-BRIEF.md` | The promise, the market gap, personas, scope, success metrics, open decisions |
| `docs/01-ARCHITECTURE.md` | Technology choices and their rejected alternatives, module responsibilities, targets, cross-module flows, budgets |
| `docs/02-DATA-MODEL.md` | Entities, lifecycle state machine, on-disk layout, manifest format, SQLite schema, CloudKit mapping, export schema |
| `docs/03-CAPTURE-AND-TRANSFER.md` | The differentiator: audio session, segmenter, timeline math, recovery, WatchConnectivity contract, transfer outbox |
| `docs/04-INTELLIGENCE.md` | Processing ladder, protocol surface, speaker resolution, the evidence system, templates, injection defence, Ask, eval gates |
| `docs/05-BACKEND.md` | The optional cloud processing plane: services, API, streaming, tenancy, model gateway, deployment |
| `docs/06-PRIVACY-AND-SECURITY.md` | ProcessingModes, the NetworkGate choke point, consent, encryption, retention, deletion, redaction, threat model |
| `docs/07-UX-SPEC.md` | Screens and states per platform, entry points, transcript rules, cross-device situations, copy rules, accessibility |
| `docs/08-MILESTONES.md` | Seven phases with exit gates and sequencing risks |
| `docs/09-BACKLOG.md` | 148 numbered tickets with acceptance criteria, plus the functional requirements they close |
| `docs/10-TESTING.md` | Test strategy, per-invariant gates, fault injection, device matrix, release gates, CI |
| `docs/11-CONVENTIONS.md` | Swift style, error handling, concurrency, DI, git, review, logging, feature flags |

---

## What makes this product different

Two things, in priority order. Everything else is table stakes we still have to reach.

**1. The Apple Watch is a real recorder, not a remote.** A meeting started on the wrist survives an absent
iPhone, no network, no iCloud, and an app crash. The Watch writes independently decodable segments locally,
seals a durable manifest, and relays opportunistically. Competitors either lack Watch capture or treat the
Watch as a trigger for the phone.

**2. Evidence is the spine.** Every generated decision, action, and factual bullet resolves to the exact
transcript span and audio range that supports it. Claims that cannot be grounded are labelled suggestions —
never decisions. The transcript is evidence; the summary is a view.

Supporting both: local-first storage with an auditable privacy boundary, where cloud AI is opt-in per meeting,
ephemeral, and verifiable by network inspection.

---

## The seven invariants

Full text in `CLAUDE.md` § 2. In brief:

| | |
|---|---|
| **I1** | Durability before acknowledgement — nothing says "recording" or "saved" before the bytes are safe |
| **I2** | The capturing device owns the truth — never the only copy in flight |
| **I3** | Segments are immutable and content-addressed |
| **I4** | Every generated claim carries evidence |
| **I5** | Local-only means local-only, enforced at one code choke point |
| **I6** | Humans confirm before the world changes |
| **I7** | Meeting content is untrusted input |

Each has enforcing tests that run on every PR, starting before the features they protect exist.

---

## Before writing any capture code

`NSP-002` — the watchOS background-recording spike — must run on physical hardware. Battery cost, process
suspension behaviour, and which recording affordance keeps a long session alive are the largest open risks in
the project, and they can invalidate the marketing claims as well as the architecture. Measure first. If a
spike contradicts a spec, change the spec.

---

## Reading order by role

| If you are… | Read |
|---|---|
| Starting implementation | `CLAUDE.md` → `docs/09` Appendix B → `docs/02` → `docs/03` |
| Designing the AI layer | `docs/04` → `docs/02` § Insight/EvidenceSpan → `docs/05` |
| Building the backend | `docs/05` → `docs/06` → `docs/01` § 2 |
| Doing UI work | `docs/07` → `docs/02` § 3 (state names must match) → `docs/11` § 6 |
| Reviewing security or privacy | `docs/06` → `docs/10` § Invariant gates |
| Planning or staffing | `docs/00` → `docs/08` → `docs/09` |
