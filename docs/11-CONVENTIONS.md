# 11 — Coding and Collaboration Conventions

Enforced by `make lint` (SwiftLint strict + swift-format) where mechanical, by review where not. `CLAUDE.md`
wins on any conflict.

---

## 1. Swift style

**Naming.** Typed IDs everywhere — `MeetingID`, `SegmentID`, `PersonID`; a raw `UUID` or `String` in a public
signature is a review block. Protocols are named for capability (`TranscriberProtocol`, `Clock`,
`SegmentStoring`) — never `IManager`, never a `-Impl` suffix on the conformer (`OnDeviceTranscriber`, not
`TranscriberImpl`). No abbreviations except the established set: `ID`, `URL`, `UUID`, `ASR`, `LLM`, `WER`,
`DER`, `SHA`, `WAL`, `FTS`, `NSP`. Booleans read as assertions (`isSealed`, `hasVerifiedReceipt`).

**Files.** One type per file, named for the type. Exceptions: a type and its small nested/associated types
(`Segmenter` + `Segmenter.RotationReason`), and a module's error enum, which lives alone in `Errors.swift`.
Extensions that add a protocol conformance go in `Type+Protocol.swift`. Package layout is
`Sources/<Module>/<Area>/`, mirrored by `Tests/<Module>Tests/<Area>/`.

**Access control.** Default `internal`; write `public` only at package boundaries and only for API another
package actually calls. Everything `public` is `final` unless subclassing is a designed extension point.
`@testable import` is the normal way to test internals — do not widen access for tests.

**struct / class / actor.**

| Use | When |
|---|---|
| `struct` | Default. All domain types in `NSPCore`, all DTOs, all values crossing a boundary. `Sendable`. |
| `actor` | Mutable state with concurrent callers: `CaptureEngine`, `TransferCoordinator`, `SyncCoordinator`, `IntelligenceScheduler`. |
| `final class` | Only when identity matters or a platform API demands a reference type (delegates, `WCSessionDelegate`). Document why in a one-line comment. |

**Force operations are banned outside tests.** No `!`, no `try!`, no `as!`, no implicitly unwrapped optionals
in `Packages/**` or `App/**`. Use `guard let … else { throw }`, a typed default, or a `precondition` with a
message that explains the programmer error. SwiftLint fails the build on a violation.

---

## 2. Error handling

- One typed, exhaustive `Error` enum per module: `CaptureError`, `TransferError`, `SyncError`, `PolicyError`,
  `IntelligenceError`. Cases carry structured payloads (`case diskFull(bytesNeeded: Int64, bytesFree: Int64)`),
  not pre-formatted strings.
- **No `NSError`**, no `Error` existentials in a package's public signature except where a platform API forces
  one — wrap it at the boundary (`SyncError.cloudKit(CKErrorCode, underlying: String)`).
- **No `fatalError` on a recoverable path.** `fatalError` is only for provably-unreachable states, and then
  with a message naming the invariant that was violated.
- **No `try?` in capture, transfer, sync, or policy code.** A swallowed error there is a lost meeting. Handle
  it, or rethrow it. `try?` elsewhere requires a comment stating why the failure is genuinely uninteresting.
- Every error carries a **cause and a remedy** in its `userFacingDescription`: "Storage full — 42 MB needed,
  8 MB free. Free space or stop the recording to seal what has been captured." Every failure also has a
  user-visible state name (`docs/01` § 7). No error appears only in a log.

---

## 3. Concurrency

Swift 6 strict concurrency, repo-wide, no exceptions at the package level.

- Domain types are `Sendable` value types. If a type cannot be `Sendable`, it does not cross a boundary.
- `@unchecked Sendable`, `nonisolated(unsafe)`, and any suppression require: a comment explaining the safety
  argument, the actor or lock that provides it, and an `NSP-xxx` ticket reference on the same line.
- `@MainActor` is for **view models and views only**. Packages are main-actor-free; a package type that needs
  the main actor is a design error — return values, let the view model hop.
- **Never `await` on the audio path.** The render/tap callback communicates through the lock-free ring buffer
  only: no allocation, no locks, no logging, no `MainActor`, no Swift concurrency primitives.
- Long-running work lives on an actor with a serial job queue and explicit backoff, not on detached tasks.
- Structured concurrency by default: `async let` / `TaskGroup`. A `Task { }` that outlives its scope must be
  stored and cancelled by its owner.

---

## 4. Dependency injection

- **Protocol-first at package boundaries.** ASR, LLM, storage, clock, filesystem, network, WatchConnectivity,
  and CloudKit are protocols in `NSPCore` or the owning package. `NSPTestSupport` has a fake for each.
- Each app target has one **composition root** (`App/Phone/Composition/PhoneComposition.swift`,
  `App/Watch/Composition/WatchComposition.swift`) that constructs the graph once at launch and passes it down.
  It is plain initializer injection — no DI framework.
- **No service locators, no singletons.** The only permitted globals are platform-forced ones
  (`WCSession.default`, `CKContainer.default()`, `UNUserNotificationCenter.current()`), and each is wrapped in
  a protocol at its first use so nothing downstream depends on the global.
- **No `Date()` in domain logic.** Inject `Clock` from `NSPCore`. Timeline math uses monotonic sample counts,
  never wall-clock arithmetic; wall clock is display and cross-device anchoring only. A `Date()` outside a view
  or a composition root is a review block.

---

## 5. Testing conventions

- Name tests `test_<subject>_<condition>_<expectation>`:
  `test_segmenter_pauseDuringRotation_producesOneOrderedSegment`.
- Arrange / act / assert, separated by blank lines, in that order. One behaviour per test; a test with two
  unrelated assertions is two tests.
- Use the fakes in `NSPTestSupport` — `FakeClock`, `RecordingFileSystem`, `FakeWatchConnectivity`,
  `FakeCloudKit`, `MockTranscriber`, `FaultInjector`. Never touch the real network, filesystem outside a temp
  dir, or hardware from a package test.
- **A property test is required** for: any state machine, any merge or reconciliation algorithm, any parser or
  serializer, and any idempotency claim. Generators and shrinkers live in `NSPTestSupport`.
- **Every bug fix ships with a regression test** that fails before the fix, in the same PR, named after the
  ticket in a trailing comment.
- Tests are deterministic. Seeded randomness only; a seed is printed on failure. No `sleep`, no wall-clock
  waits — advance `FakeClock`.

---

## 6. SwiftUI

- `@Observable` view models, `@MainActor`, one per screen. No Combine in new code.
- **No business logic in views.** A view may format for display and dispatch intent; anything else moves to the
  view model, and anything with a rule in it moves to a package.
- Decompose when a `body` exceeds ~60 lines, nests more than 3 container levels, or has more than 2
  conditionals. Extract to a named subview, not a `@ViewBuilder` computed property soup.
- **Previews are required for every screen, covering every state** it can be in — empty, loading, populated,
  partial, failed, plus Dynamic Type AX3 and dark mode. Preview data comes from `NSPTestSupport` fixtures.
- **All colours, spacing, typography, iconography, animation curves, and haptics come from `NSPDesignSystem`.**
  A literal `Color(...)`, `.padding(13)`, or `UIImpactFeedbackGenerator` outside that package fails review.
  Status is never colour-only — every recording state has a shape/label/text equivalent.

---

## 7. Git and review

- Branches: `nsp-<ticket>-<slug>` — `nsp-014-segment-rotation`.
- Commits: Conventional Commit prefixed with the ticket — `NSP-014: feat(media): rotate segment on pause`.
  Imperative mood, body explains *why*.
- **Small PRs.** Target under 400 changed lines; over 800 needs a stated reason. One ticket per PR.
- A PR description must contain: the ticket link, what changed and why, **which invariants (I1–I7) it affects
  and how they stay satisfied**, the tests added, how it was verified (including device runs if relevant),
  spec/doc updates, and any feature flag introduced.
- **A PR touching capture, transfer, sync, policy, or intelligence must name the affected invariants
  explicitly.** "None" is an acceptable answer only if it is true; reviewers check.

**Review checklist.** New logic is in a package, not `App/` · typed errors, no `try?`/force-unwrap on the
critical paths · `Clock` injected, no `Date()` · `Sendable`, no unexplained suppression · tests present, and a
property test where § 5 requires one · accessibility labels, state announcements, Dynamic Type · no
content-bearing logging or telemetry · no network call bypassing `NSPPolicy` · docs updated in the same PR ·
`make check` green.

---

## 8. Documentation

- Doc comments (`///`) are required on every `public` symbol: what it does, what it throws, what it guarantees
  about durability or ordering if anything.
- **A behaviour change updates the spec in the same PR.** Drift between `docs/` and code is a defect; the docs
  are the contract (`CLAUDE.md` § 5).
- Architectural decisions get an ADR in `docs/adr/NNNN-<slug>.md`:

```markdown
# ADR-0007: Fragmented M4A segments on watchOS
Status: Accepted            Date: 2026-08-19          Ticket: NSP-003
## Context      — forces at play, constraints, what we measured
## Decision     — what we are doing, stated in the active voice
## Consequences — what this makes easy, what it makes hard, what it forecloses
## Alternatives — considered and why rejected
```

- Hardware spike results go in `docs/reports/hardware-<date>.md` with device model, OS build, exact procedure,
  raw numbers, and the conclusion. **If a spike contradicts a spec, the spike wins and the spec changes in the
  same PR.** Never build on a hope.

---

## 9. Logging

- Structured only: `OSLog`/`Logger` with a per-module subsystem and a category, key-value metadata, no string
  interpolation of variable content.
- Levels: `debug` (dev loop, compiled out of Release) · `info` (state transitions, lifecycle) · `notice`
  (user-visible state changes) · `error` (typed error surfaced to a user) · `fault` (invariant violation).
- Correlation IDs on every log line touching a meeting: `meetingID`, `segmentID`, `jobID`, `transferKey`.
  IDs are opaque UUIDs and are safe; they are the only meeting-linked value permitted.
- **Absolute rule: no meeting content ever reaches a log, breadcrumb, crash report, analytics event, or error
  message.** Not audio, not transcript text, not note text, not the title (titles come from calendars and are
  routinely confidential), not attendee names or emails, not filenames derived from any of these. Log counts,
  durations, sizes, state names, and error codes. Content-bearing fields are marked `@Redacted` in
  `NSPCore` and the log formatter refuses them; a test asserts the refusal.

---

## 10. Feature flags

- Declared in `NSPCore/FeatureFlags.swift`, one enum case per flag, `lowerCamelCase` and descriptive of the
  capability: `watchLiveTranscriptPreview`, `iPadPencilCanvas`, `cloudSummarization`.
- **Default off for anything incomplete.** Half-built features ship dark, not on a long-lived branch that rots.
- Every flag records its owner, ticket, and target removal milestone in the declaration comment.
- Cleanup is part of the shipping ticket: a flag that has been fully on for one release is removed, along with
  the dead branch. A flag older than two releases is a bug and appears in the backlog.

---

## 11. Localization and accessibility (everyday, not a final pass)

- All user-facing strings go into the String Catalog at write time, with a comment giving context for
  translators. No literal user-facing string in a view.
- **Never concatenate sentences or build them from fragments.** Use full localized formats with named
  arguments; use `AttributedString` markdown for inline emphasis; pluralize with the catalog's plural rules,
  never with `if count == 1`.
- Layout is RTL-safe by construction: leading/trailing, never left/right; no hard-coded text direction; mirrored
  chevrons and directional icons.
- Accessibility identifiers, labels, values, hints, and traits are written **with** the view, not retrofitted.
  Every recording-state indicator announces its state change. Every screen must be operable end-to-end with
  VoiceOver, at AX5 Dynamic Type, without colour perception.

---

## 12. When in doubt

1. **Durability over latency.** A slower acknowledgement is always better than an acknowledgement that is not
   yet true (I1).
2. **Explicit state over inferred state.** Record the event; do not reconstruct it later from a heuristic.
3. **Disclosure over silent degradation.** A named, actionable failure beats a spinner, a guess, or a quietly
   shorter meeting.
4. **A spike over an assumption about platform behaviour.** Measure it on hardware, write it in
   `docs/reports/`, then design.
5. **The user's device over the cloud.** If it can be done locally, do it locally.
6. **Evidence over eloquence.** An ungrounded claim is a `suggestion`, never a decision (I4).
7. **Confirmation over convenience.** Nothing leaves the workspace without a human approving the exact payload
   (I6).
8. **The doc over the adjacent code.** If they disagree, the doc is the contract — and if the doc is wrong,
   fix the doc in the same PR.
