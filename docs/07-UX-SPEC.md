# 07 — UX Specification (screens, states, interactions, accessibility)

This is the document an engineer implements screens from. It specifies **structure, states, interactions, copy
rules, and accessibility** — not visual design. No colour palettes, no pixel values, no typography scales;
those live in `NSPDesignSystem` tokens.

Every state name the user sees must be one of the lifecycle states in `docs/02-DATA-MODEL.md` § 3 or a
`TransferState`/`Availability` case from § 2. Invented UI-only state names are a bug. Invariants are referenced
by ID (`I1`–`I7`) from `CLAUDE.md` § 2.

---

## 1. Information architecture

**Updated 2026-08-22** — this section drifted well behind the real `AppTab` case set as Projects, People,
Threads, Calendar, and now My Work shipped; rewritten against current code rather than left stale. Eleven
areas today (`AppTab`): My Work, Dashboard, Today, Library, Ask, Actions, Projects, People, Threads, Settings,
Calendar. **My Work** replaced **Dashboard** as the first, default area 2026-08-22 ("The Spine" recommendation)
— Dashboard is unchanged and fully reachable, still hosting the capture controls and Today's Agenda sidebar on
iPad; My Work is the new "what am I actually managing" lens, organized by active Thread rather than by date.
Today narrowed to "what do I need to do today" and is reached *from* Dashboard's own Today card, not as a peer
top-level area (Watch is unaffected — it never had a Today/Dashboard distinction; its root stays the Ready
screen).

| Area | Contains | Not allowed here |
|---|---|---|
| **My Work** | One card per open Thread — next meeting, open action count, people count, a "gone quiet" badge past 14 days — sourced through `RelationshipGraph`, not a bespoke query. A toolbar link to the Weekly Brief | Calendar/date-scoped views (that's Today's Agenda / Calendar) |
| **Dashboard** | Start capture, cross-meeting "needs attention," a Library preview, every open action regardless of due date, an explicit Today card, an explicit Ask entry point, Today's Agenda (iPad sidebar) | Content scoped to only today (that's Today) |
| **Today** *(reached from Dashboard, not a top-level area)* | The active/next recording, calendar-linked events happening today, Scheduled Recording's "Upcoming" list, meetings needing review, actions due specifically today | Historical browse, every-open-action-ever (those live in Dashboard) |
| **Library** | Every artifact the app holds — Meetings, Brain Dumps, and Notes, day-grouped with lifecycle-state filters (a Brain Dump/Note reuses `MeetingState`, so one filter set already covers all three) | Live capture controls |
| **Meeting** | One meeting's tabs: Overview, Notes, Transcript, Audio, Actions, Insights, Attachments, Sharing, Processing log. Insights merges `Insight` and `Decision` into one chronological list — "things learned or decided" is one category, not two sections | Cross-meeting search |
| **Ask** | Cross-meeting question answering with a **mandatory** scope selector and citations | Ungrounded answers (I4) |
| **Actions** | Action + decision ledgers across meetings, owner/date review, export queue, unanswered questions. Freestanding, due-dated "Action Reminder" items (no `Meeting` — collapsed from a phantom-Meeting design 2026-08-22) render here and on the agenda by date | Silent sends (I6) |
| **Projects** | Real entity, not a placeholder — meetings, notes, open actions, and (2026-08-22) people grouped by project, independent of Thread membership | — |
| **People** | Every tracked `Person` — relationship tags, notes, what's owed each way, meetings/threads/projects they're linked to, "Add to Thread"/"Add to Project" | — |
| **Threads** | Storylines spanning meetings — open/closed status, linked people (2026-08-22), open actions/decisions | — |
| **Calendar** | Month grid over this workspace's meetings/scheduled recordings, including recurring-series virtual occurrences (2026-08-22) — iPad only, no EventKit integration | — |
| **Settings** | Capture defaults, processing mode default, consent + policy, storage, sync/iCloud, integrations, accessibility, diagnostics | Per-meeting overrides (those live in Meeting → Sharing / Overview) |

### 1.1 Platform mapping

| Area | Watch | iPhone | iPad |
|---|---|---|---|
| My Work | Not present | Tab 1 (default) | Header area 1 (default) |
| Dashboard | Not present — Watch root stays the Ready screen | Tab | Header area, hosts Today's Agenda sidebar |
| Today | Not present | Pushed from Dashboard's Today card | Set via Dashboard's Today card (not its own header area) |
| Library | Compressed to **History** (recent 20, local-first) | Tab | Header area, list column |
| Meeting | Read-only glance: state, duration, transfer state | Tab-bar detail with 9 tabs | Split canvas + transcript workspace |
| Ask | Not present | Tab | Header area |
| Actions, Projects, People, Threads | Not present | Tabs | Reachable from `PadDashboardSidebar`'s restricted nav list, not the top header |
| Calendar | Not present | Not present (v1, iPad only) | Reachable from `PadDashboardSidebar`'s restricted nav list |
| Settings | Minimal: haptics, mic check, storage, reclaim | Tab | Header area |

**Compression rule (Watch):** the Watch shows only what a wrist glance must answer (§ 3.1). It never shows
transcript text, summaries, attendee lists, or calendar titles marked `isTitleSensitive`.

**Expansion rule (iPad):** iPad presents three columns (sidebar → list → detail) and splits the Meeting detail
into a canvas/transcript workspace (§ 6). Tabs that are peers on iPhone become panes that can be open
simultaneously on iPad.

---

## 2. Capture entry points

Every entry point resolves to the same `NSPMedia` start path (`docs/01` § 5.1). **No entry point may show
`Recording` before the durable write (I1).** Between invocation and the durable acknowledgement the user sees
`Arming` with an indeterminate indicator and the label "Preparing…".

| Entry point | On invocation | What the user sees within 2 s |
|---|---|---|
| Watch app | Ready → `Arming` → `Recording` | `Arming` immediately; `Recording` + start haptic only after durable write (≤ 2 s p95) |
| Watch complication | Launches app directly into `Arming`, skipping Ready | Same as above; complication itself flips to `Recording` only on durable ack |
| Smart Stack widget | Same as complication; widget shows live elapsed time once `Recording` | Widget shows "Preparing…" then elapsed time |
| Action button / `AudioRecordingIntent` | Starts capture without foregrounding the app; system's mandated ongoing recording presentation appears | System recording presentation + our haptic on durable ack; app not required to be visible |
| Siri ("start a meeting") | Runs the same intent; confirms verbally **after** durable ack | Spoken + haptic confirmation; if the durable write fails, Siri reports the specific cause, never "started" |
| iPhone/iPad app | Today → Start | `Arming` sheet with mic level and cause-specific failure copy; then active-session view |
| Lock Screen widget | Launches intent from the Lock Screen without unlock where the platform allows | `Arming`, then Live Activity on the Lock Screen |
| Control Center control | Toggles capture via the intent | Control shows `Arming`, then `Recording`; Live Activity appears |
| Home Screen widget | Tap = start; a second tap opens the active session (never stops) | Widget flips to elapsed time + "Open" affordance |
| Shortcuts | `Start Meeting`, `Add Marker`, `Stop Meeting`, `Export Recap` intents; each returns a typed result | Shortcut result string states the actual state reached, never an optimistic one |
| Calendar notification | Notification with **Start** and **Skip** actions; title suppressed when `isTitleSensitive` | Tapping Start begins `Arming` in the background; Live Activity replaces the notification |
| Live Activity | Displays elapsed time, capture device, marker button, and Open; Stop lives in the app only | Updates within one refresh cycle of state change |
| Share sheet / Files import | Creates a meeting with `captureMode == .import`; goes `Ready → Finalizing → Processing` (never `Recording`) | Import progress with byte count and a cancel that leaves no partial meeting |

A second start request while a meeting is active never creates a silent duplicate: the UI surfaces
"Already recording on <device>" with the four canonical choices: **Keep recording on Watch**, **Take over on iPhone**, **Record separately**, **Cancel**.

**Brain Dump and standalone Note are separate entry points, not a `Meeting` flavor.** Dashboard's capture
control (iPhone: a long-press menu; iPad: three buttons in `PadDashboardSidebar`) offers three distinct starts:
a real Meeting (red mic, table above), a Brain Dump (purple brain icon — real audio capture through the same
`Arming → Recording` path, but a `BrainDump` row, never a `Meeting`), and a standalone Note (blue pencil icon —
creates a bare `Note` row with no capture yet, docs/02 § 2's "notes before recording" shape). Only iPhone/iPad
have these two entry points today — no Watch, widget, Siri, or Shortcuts path starts a Brain Dump/Note yet.

### 2.1 Scheduled Recording

Formalizes the **Calendar notification** entry point above into a standalone feature: the user pre-schedules a
recording — a name, a start time, and a stop time — either typed in manually or imported from an existing
calendar event they pick from a list, so they don't have to remember to start it later.

- **Creation.** Today's *Upcoming* section (§ 4) lists pending schedules and offers "Schedule a Recording":
  manual entry (title, start, stop) or "Import from Calendar" (a bounded near-future list of the user's
  existing events — a materially broader EventKit grant than the write-only one Settings' post-recording
  calendar-export uses, and its own consent surface, not a silent upgrade of that grant).
- **Start is a mandatory notification, never silent.** At the scheduled start time, a **Start**/**Skip**
  notification fires — this *is* the "Calendar notification" row in § 2's table, now with a per-schedule
  **alert style** the user picks at setup (sound / vibrate / silent-banner, same mental model as the Clock
  app's alarms). Tapping Start enters the same `Arming` path every other entry point uses, including any
  workspace-required announcement (§ 7) — a schedule never bypasses that gate. Tapping the notification body
  (not a button) opens the app without starting anything; only Start starts it.
- **Stop is fully unattended.** Once recording is live, it stops automatically at the scheduled stop time with
  no interaction required — unlike start, there is no platform obstacle here, since the app is already alive in
  an active audio session.
- **Platform-imposed limits, stated plainly rather than implied away**: iOS/watchOS give third-party apps no
  way to silently launch and start capture with zero interaction at the trigger moment, which is why start is
  notification-gated rather than truly automatic. "Vibrate" is best-effort — `UNUserNotificationCenter` has no
  independent "vibrate without sound" toggle; whether a sound-less notification vibrates is governed by the
  device's own Settings/Focus state, not a per-request flag. True alarm-class behavior (rings through the mute
  switch) exists via AlarmKit on iOS/watchOS 26+, which this app's 18.0/11.0 floor doesn't reach yet — a
  deliberate, scoped fast-follow, not a silent gap.

### 2.2 Recurring events (added 2026-08-22)

`AddAgendaItemFormView` (the "+" flow on Today's Agenda and Calendar) gains a **"Make Event Recurring"**
button under "When," hidden for the Action Reminder Meeting Type (a plain `Action` has no recurrence field).
Tapping it opens `RecurrenceConfigurationView`, an Outlook-style secondary sheet: Daily/Weekly/Monthly/Yearly
segmented control, pattern-specific controls (interval stepper, weekday multi-select, day-of-month vs.
Nth-weekday), and a Range-of-recurrence section (Never / After N occurrences / On date). "Done" hands an
in-memory rule back to the parent form, not persisted until the whole event saves — same deferred-commit
pattern the color and Meeting Type pickers already use there. Once configured, the button's label becomes a
human-readable summary ("Weekly on Mon, Wed, Fri").

A recurring row shows a small ⟳ badge next to its title on both Today's Agenda and Calendar. Its "…" menu's
Modify/Cancel actions gain a three-way scope prompt — Outlook's "This event is part of a series" dialog:
**This occurrence**, **This and following occurrences**, **All occurrences**. Future occurrences with no real
row yet render as a distinct, badge-marked row with only Start/Skip in its menu (no Modify — starting it is how
you get something to modify). See `docs/02-DATA-MODEL.md`'s RecurrenceRule/RecurrenceException section for the
two disclosed v1 simplifications ("this and following" doesn't spin up a continuation series; "all occurrences"
cancel doesn't cascade-delete other already-promoted rows in the series).

---

## 3. Apple Watch — the signature surface

### 3.1 What a glance must answer

Within one second of raising the wrist, in this priority order: **(1)** is it recording, **(2)** elapsed time,
**(3)** mic health, **(4)** Watch battery, **(5)** storage headroom, **(6)** transfer state. Items 3–6 are
compressed into a single status row and expand on Digital Crown scroll.

### 3.2 Screens

| Screen | Elements | Interactions |
|---|---|---|
| **Ready** | Large Record control; last meeting summary line (title suppressed if sensitive); status row (battery, storage-hours-remaining, pending transfers); History affordance | Tap Record → `Arming`. Crown scrolls to status detail and History. Swipe right = system back |
| **Arming** | "Preparing…", indeterminate indicator, Cancel | Cancel aborts and returns to Ready with no meeting row persisted |
| **Recording** | Elapsed time (from sample counts, never a `Timer`), live mic level meter, Marker button, Pause, Stop, status row | Tap Marker → `.marker(kind:)` timeline event + confirm haptic. Crown scrolls to health detail. Double-tap gesture = **Add marker** (never Stop) |
| **Paused** | "Paused", frozen elapsed time, paused-duration counter, Resume, Stop | Resume opens a **new** segment (never reopens the closed one). Double-tap = Resume |
| **Interrupted** | "Interrupted — <cause>", last durable time, Resume, Stop | Auto-resume attempted; the UI states whether audio is currently being captured |
| **Finalizing** | "Finalizing… n of m segments sealed", non-cancellable, no Stop | On completion → `SavedRaw` confirmation card: "Saved on Watch — n segments" with transfer state |
| **History** | Last 20 meetings: relative time, canonical duration, `Availability`, `TransferState` badge, storage used | Tap a row → read-only detail (state, duration, segment count, transfer state, Retry transfer, Delete). Swipe = Delete, gated by § 8 rules |

**Remote-control mode.** When the iPhone owns the mic, the Watch's `Recording`/`Paused` screens above render
identically but are captioned "Controlling iPhone" instead of "Recording" — the Watch is not capturing audio
in this mode, and the caption must never imply it is (I1's display-honesty spirit, `docs/03` § 11). Marker,
Pause, and Stop send the command to the phone rather than acting locally, and only update the Watch's own
state display after the phone acknowledges. There is no equivalent for an iPad-owned recording — the Watch
cannot control iPad (`docs/03` § 11).

### 3.3 Stop rule (normative)

Stop is a **visible, labelled control** on `Recording`, `Paused`, and `Interrupted`. Tapping it presents a
confirmation with two explicit buttons — **Stop & save** and **Keep recording** — and the elapsed time. It is
never a hidden gesture, never a long-press-only affordance, never bound to double-tap, and never destructive by
default. Confirmation must be reachable in one additional tap and dismissible by swipe-back (which cancels
Stop, keeping the recording). Force-quit and low-battery shutdown take the `sealedStop(reason:)` path and are
disclosed on next launch.

### 3.4 Haptic vocabulary

| Event | Haptic | Rule |
|---|---|---|
| Recording started | `.success`, single | Fires **only** after the segment-0 header is durable (I1) |
| Marker added | `.click`, single | After the timeline event is appended and fsync'd |
| Paused / Resumed | `.directionDown` / `.directionUp` | After the segment close / open is durable |
| Stop confirmed, sealed | `.success`, double | After the manifest seal, not on button press |
| Failure (any) | `.failure` | Always paired with an on-screen cause + action |
| Health warning (level, storage, battery, thermal) | `.notification`, at most one per warning class per meeting | Never during the last 10 s before a confirmed Stop |

Silent mode and Taptic settings are respected; when haptics are disabled the same events must produce a
persistent visual state change (§ 11).

### 3.5 Complication / Smart Stack

Idle: app glyph plus the count of meetings pending transfer. Active: elapsed time and a recording indicator
that is **not colour-only** (glyph shape change plus text). Complication timelines are updated from durable
state only; a complication may never render `Recording` optimistically. Smart Stack widget adds a Marker
button and an Open button; it never carries Stop.

---

## 4. iPhone screens

**Dashboard.** The default tab. Sections in order: header (date + greeting), a stats strip (meetings this
week, open actions, overdue count), *Attention Required* (meetings in `ReadyForReview` or `PartialFailure`,
across all time — not just today), a Today card (meeting count for today, opens Today) alongside a Quick Start
recording shortcut, an Ask entry card, *Recent Meetings* (a Library preview), *All Actions* (every open action
regardless of due date), and an explicit *Projects* placeholder — no project/tag data model exists yet, so this
section names what's coming rather than fabricating a grouping. Sections with nothing to show are simply
absent.

**Today.** Reached from Dashboard's Today card, not its own tab. Sections in fixed order: *Now* (active session
card, or nothing), *Needs review* (meetings in `ReadyForReview` or `PartialFailure`), *Upcoming* (pending
Scheduled Recordings — § 2.1 — manual or calendar-imported, not calendar-derived entries alone), *Due Today*
(actions whose due date falls today — Dashboard's *All Actions* is the unfiltered, cross-time version of this
same list). Each attention row names a cause and an action.

**Active session view.** Elapsed time, waveform-free level meter, Marker, Pause, Stop (same confirmation rule
as § 3.3), capture-device attribution ("Recording on Apple Watch — this iPhone is not capturing"), live
provisional transcript if enabled (rendered per § 7), and a processing-mode chip showing the frozen
`ProcessingMode`. The Live Activity mirrors elapsed time, device, and marker count; it never offers Stop.

**Markers are notes, not just timestamps.** iPhone has no ruled-paper canvas to write on mid-meeting (§ 5's
iPad-only capability), so a Marker is the iPhone equivalent: dropping one immediately shows it in a dismissible
in-session list the user can rename with a short label right there, or leave untitled and fill in later from
the Meeting → Notes tab. Every marker is a `NoteBlock` (`type == .action` or `.richText` depending on what the
user picked at creation) anchored to the marker's `creationRange`, editable and deletable the same as any note
(§ 4's Notes tab) — never a bare, unlabeled timeline dot the user can't later explain. Marker-originated notes
are ordinary evidence input to summary and action-item generation (`docs/04`): a marker labelled "follow up
with Legal" is exactly the kind of human-authored signal `NSP-048`'s action extraction should weight alongside
transcript spans, not a separate, second-class annotation.

**Meeting detail tabs.**

| Tab | Contents | Notes |
|---|---|---|
| Overview | Flash recap, chapters, participants, duration, `Availability`, processing mode, consent record summary | Every bullet carries an evidence affordance (I4) |
| Notes | `NoteBlock` list by type, private blocks marked, merge proposals inline | AI never edits blocks; it proposes (§ 7.3) |
| Transcript | § 7 in full | |
| Audio | Player, chapters, markers, silence map, export | Redaction entry point |
| Actions | Proposed/Confirmed ledger for this meeting | Export gate per I6 |
| Insights | Layered insights by `InsightLayer`, with `claimKind` and `approvalState` shown | `.aiSuggests` visually distinct from `.said`/`.agreed` |
| Attachments | Photos, scans, imported files, OCR text | |
| Sharing | Share grants, share preview (§ 7.4), redaction state, revocation | |
| Processing log | Job history, model/prompt versions from `Provenance`, failures with cause, retry | Read-only, always available even in `PartialFailure` |

**Library.** Search field, filter chips (date, workspace, `captureMode`, `Availability`, processing mode,
has-actions, has-unresolved-owner, `excludedFromMemory`), sort, and **saved searches** created from any active
filter set. Rows: title (or "Untitled meeting" when sensitive/absent), date, duration, state badge, action
count. Paged; never loads transcripts.

**Ask.** The scope selector is **mandatory and always visible** — the query field is disabled until a scope is
chosen (this meeting / selected meetings / workspace / date range). Answers render as claims with inline
citations that open the source turn; an answer with no resolvable citation is labelled a suggestion, never an
answer (I4). Retrieval is authorization-filtered before indexing, so out-of-scope meetings are not merely
hidden from results — they are never retrieved.

**Actions dashboard.** Grouped by status (`Proposed`, `Confirmed`, `Sent`, `InProgress`, `Done`, `Dismissed`),
with owner and due-date columns that mark inferred values. Bulk confirm is allowed; bulk **send** is not
exempt from the per-payload confirmation gate (I6).

**Settings.** Capture (format, segment length where exposed, markers, haptics), Processing (default
`ProcessingMode`, on-device availability status), Calendar (an opt-in toggle to create a calendar event after
each recording, plus the destination calendar — off by default; see "Calendar events for recordings" below),
Privacy (consent defaults, announcement text, retention, redaction defaults, memory exclusion), Storage
(per-device usage, reclamation policy), Sync (iCloud account state, quota, last change token time),
Integrations, Accessibility, Diagnostics (content-free by default).

**Calendar events for recordings.** With the Settings toggle on, stopping a recording offers to add a calendar
event to the user's chosen calendar — the event's exact title, start, and end are shown and the user must
explicitly confirm before anything is created (I6; EventKit access itself is write-only, so the app never reads
the user's existing calendar). The event title is the meeting's title as recorded. Start time defaults to the
15-minute increment *before* the recording actually started (a 2:11pm start defaults to 2:00pm) and is the one
field the user can adjust; end time is the recording's actual end and isn't user-editable at this step. The
created event's identifier is stored on the meeting (`Meeting.calendarEventID`).

---

## 5. iPad workspace

**Layout.** Sidebar → meeting list → detail. Detail is a split canvas: **note canvas** on the leading side,
**transcript** on the trailing side, with a draggable divider, a swap control, and a full-width mode for each.
Audio transport is a persistent bar spanning both panes.

**Note-taking mode — college-ruled paper.** iPad's defining advantage over iPhone/Watch is notetaking during
capture, so the note canvas becomes the primary view — "note-taking mode" — the moment a meeting is opened for
notes, whether or not recording has started yet (below). A reference mockup is checked in developer-side at
`~/Downloads/IMG_0121.PNG` (not part of the repo — describe it here so the spec doesn't depend on that file
surviving); the description below is normative, the file is illustrative.

- **Header bar.** A dark, full-width toolbar, not the light chrome used elsewhere in this app. Left to right:
  transport controls for the meeting's audio (a red Record indicator/button, skip-back-10s, Play/Pause,
  skip-forward-10s — lets the user scrub already-recorded audio without leaving the page); a centered tool
  palette (Selection/pointer, Text, Pen, Highlighter, Camera/insert-photo) with the active tool visibly
  highlighted; trailing utility icons (Share/export, New page, Settings). The pen and highlighter each need a
  colour picker — the mockup shows ink in at least green and black, highlighter in yellow.
- **Title area.** A large, non-ruled band at the top of the page for the meeting's name — a bold large title
  line plus an optional smaller bold subtitle line (the mockup: "Concentrix" / "Onsite Visit and QBR"). Free
  text, not bound to the ruled grid below it.
- **The ruled page.** White background, thin blue horizontal ruled lines below the title area. A red vertical
  margin line inset from the leading edge separates a timestamp gutter (to its left, right-aligned) from the
  writing area (to its right). Typed text and Apple Pencil ink coexist freely in the writing area — ink is not
  confined to its own zone or page; it can be drawn anywhere, including across multiple ruled-line heights, the
  same way a real notebook page mixes handwriting and diagrams. A camera tool inserts photos onto the page the
  same way.
- **Notes taken before recording starts.** The canvas is available before the user taps Record, not only
  during `Recording` — this is a real, intended flow ("pre-brief" notes, agenda jotted down while waiting for
  the meeting to start). Any content created before recording begins is stamped `--:--` in the margin, exactly
  that literal placeholder, not `0:00` or blank. Once recording starts, new content gets real `mm:ss` stamps;
  content already stamped `--:--` is never retroactively rewritten once recording begins — it stays `--:--`
  permanently, an honest record that it predates the recording.
- **Timestamp anchoring.** Every margin stamp is a `NoteBlock.creationRange` start on the canonical monotonic
  sample-count timeline — never wall-clock arithmetic (`docs/03`, "Timeline math") — captured the moment a new
  piece of content (a typed line, or an ink stroke group) is created. A typed line's first character stamps
  it; a new line gets its own stamp only once it receives its own first character. Ink strokes close together
  in time and position are grouped into one shared stamp rather than one per stroke — the grouping tolerance
  is governed by the `NOT-002` acceptance test. Palm rejection, Scribble for text blocks, and double-tap/
  squeeze mapped to the system tool switch. Ink is never rasterized into the recap.
- **Playback from the page.** After the meeting is saved, tapping any word, any margin timestamp, or any ink
  stroke seeks audio to that block's `creationRange` start and highlights the overlapping transcript turns —
  the same tap-a-stroke-to-seek mechanism below, extended to typed text and to the margin column itself as an
  equally valid tap target. Seeking never modifies the note. A `--:--`-stamped block has no meaningful seek
  target (it predates the recording) — tapping it is a no-op, not an error.

**Implementation status (updated 2026-08-20, v3):** `PadRootView` and `PadRecordingCanvas` are wired end to end
with real `NoteBlock`s and real sample-accurate anchoring: a dark two-row header (`PadCanvasHeader`) with real
recording controls and a tool palette (Pointer/Text/Pen are functional; Highlighter/Camera/Share/New page/
Settings are drawn to match the mockup's shape but are honestly disabled, not fake-functional), an editable
large title band bound to `Meeting.title`, a red margin rule over ruled lines, and real Apple Pencil ink via
`PKCanvasView` (`PadInkCanvas`). **`NSP-101` (stroke-group timestamping) is now built:** `StrokeGroupTracker`
(`NSPMedia`) groups newly-drawn strokes by time and position (`NOT-002`'s tolerance — unit-tested), and each
closed group persists as its own `.sketch` `NoteBlock` with an accurate `creationRange`, referencing its own
`.drawing` asset under the meeting container's `ink/` directory via `InkAssetFileSystem` (atomic write, also
unit-tested) — ink is no longer one page-wide block. **Pre-recording availability is also built:**
`RecordingSession` has a `.draft` state (`prepareDraft`) that creates a real, notes-capable `Meeting` before
capture starts; Today's "New Note (before recording)" button (iPad only) enters it, `PadRootView` shows the
canvas for a drafting meeting the same as a recording one, and `PadCanvasHeader` swaps in a plain "Start
Recording" control while drafting. Content created pre-recording is permanently stamped `--:--` (a synthetic
negative sample-offset timeline distinguishes it from a real `0:00`, since `NoteBlock` has no dedicated field
for this) and is never rewritten once recording begins, matching this section's wording exactly. **Still not
matching the spec:** no visible per-ink-group margin stamp on the page itself (the data is correct and
seekable once `NSP-102` exists; there's just no UI chip next to each group yet); no photo insertion; no
multi-page. See `docs/09-BACKLOG.md` M4 (`NSP-099`–`NSP-110`) — `NSP-102` (tap-a-stroke-to-seek) is the
biggest gap left.

**Content block types available on the canvas:** `.richText`, `.checklist`, `.decision`, `.action`, `.quote`,
`.question`, `.code`, `.table`, `.sketch`, `.photo`, `.linkPreview`, `.file`, `.transcriptExcerpt`.

**Tap-a-stroke-to-seek.** Tapping any ink stroke or block seeks audio to the start of that block's
`creationRange` and highlights the transcript turns overlapping it. Tolerance and stroke-grouping behaviour are
governed by the `NOT-002` acceptance test. Seeking never modifies the block.

**Private margin notes.** A margin gutter creates blocks with `privacy == .privateToAuthor` by default. Private
blocks are visually marked, excluded from every share and export payload, and excluded from the share preview's
contents list — the preview instead states the count of private blocks withheld.

**Merge into recap.** A block with `mergeState == .proposedForRecap(diffID)` shows a **Review merge** control
that opens a side-by-side diff of the current recap text and the proposed result. The user approves, edits, or
rejects. Approval transitions the block to `.mergedIntoRecap(insightID)` and the target insight to
`approvalState == .edited` or `.approved`. Nothing merges without approval.

**Whiteboard capture.** Camera sheet → automatic quadrilateral detection → perspective correction preview with
draggable corners → OCR → a `.photo` block with searchable OCR text and a `creationRange` anchored to capture
time. The user can always keep the uncorrected original.

**Stage Manager and multiwindow.** Supported scenes: Meeting, Ask, Actions, Library. Two meetings may be open
in separate windows; a single meeting open twice shares one editing session (last-writer-wins per block, op-log
merged). Window state restores on relaunch.

**Keyboard shortcuts.**

| Shortcut | Action | Shortcut | Action |
|---|---|---|---|
| ⌘R | Start capture | Space | Play / pause |
| ⌘. | Stop (opens confirmation) | ← / → | Seek −10 s / +10 s |
| ⌘M | Add marker | ⌥← / ⌥→ | Previous / next turn |
| ⌘F | Find in transcript | ⌘⌥F | Find and replace |
| ⌘G / ⇧⌘G | Find next / previous | ⌘0…⌘8 | Jump to meeting tab |
| ⌘⌥→ / ⌘⌥← | Playback rate up / down | ⌘⇧S | Skip silence toggle |
| ⌘N | New note block | ⌘⇧N | New private margin note |
| ⌘E | Export (opens confirm gate) | ⌘⇧E | Share preview |
| ⌘L | Focus Library search | ⌘K | Focus Ask |
| ⌘⇧P | Presentation mode | Esc | Exit presentation / dismiss sheet |

**External display presentation mode.** Mirrors only: title (suppressed when `isTitleSensitive`), chapters,
approved insights, confirmed actions and decisions, and shared-privacy note blocks. It **never** renders
transcript text, provisional text, private blocks, participant contact details, or the processing log. Entering
presentation mode shows a one-time sheet enumerating what will and will not appear. Toggling any pane on the
iPad does not change what the external display shows.

---

## 6. Transcript UX rules

1. **Provisional vs finalized.** `isProvisional == true` renders with a distinct non-colour treatment (italic
   plus a leading provisional glyph and a "Provisional" section header). A "Provisional" legend is always
   visible while any provisional turn exists.
2. **Revisions never move the reader.** When a revision replaces provisional text, the scroll anchor is the
   topmost visible turn's `turnID`, not a pixel offset. Content above may reflow; the anchored turn stays put.
   If the anchored turn is deleted by the revision, anchor to its nearest surviving predecessor.
3. **Tap to play.** Tapping any word seeks to that token's `startSample`; tapping the turn gutter seeks to the
   turn start. Word-level timing is required (`docs/02` § 2).
4. **Playback highlighting.** The active turn and the active word are both highlighted, using weight/underline
   in addition to any colour. Auto-scroll follows playback and disengages the moment the user scrolls, showing
   a **Resume following** control.
5. **Rate and transport.** 0.5×–3× in 0.1 steps with a preset ring (0.75, 1, 1.25, 1.5, 2); skip-silence toggle
   with the threshold surfaced; 10-second back/forward.
6. **Speaker rename.** Renaming a `speakerClusterID` opens a preview listing affected turn count and three
   sample turns, with **Apply to this turn only** / **Apply to all turns in this cluster**. Applying sets
   `personID` and `editState == .userEdited`; it never rewrites token text. A rename that would assign an
   identity without evidence is blocked with an explanation.
7. **Confidence.** Low-confidence tokens carry a non-colour marker (dotted underline) and a per-turn confidence
   affordance. Confidence is never rendered as a single accuracy percentage for the meeting.
8. **Find / replace.** Find is incremental with match count and next/previous. Replace operates only on
   user-editable text, requires a confirmation listing the number of turns affected, records `editState ==
   .userEdited(revisionOf:)`, and never alters `quotedText` snapshots inside existing `EvidenceSpan`s — those
   become *stale* and are labelled as such, never silently dropped.
9. **Redaction.** Select a range → **Redact** → a preview showing the transcript text removed and the
   corresponding audio interval that will be muted → confirm. Redaction is a versioned edit; the original
   remains until retention purge, and exports state that redactions were applied.

---

## 7. Review and approval

**7.1 Proposed vs confirmed.** `Proposed` items are rendered in a "Proposed" group with a distinct container
treatment, a "Proposed" text label, and no destination shown. `Confirmed` and later statuses show owner, date,
destination, and the confirming user. The two must be distinguishable without colour, at the smallest Dynamic
Type size, and in a screenshot.

**7.2 Inference labelling.** Any owner or date that was inferred rather than stated carries an explicit
"Inferred" tag and an evidence affordance. `.unresolved` owners show "Owner not identified" and block export.
Insights show `claimKind`: `.said` and `.agreed` are attributable; `.aiSuggests` is labelled "AI suggestion"
and can never be exported as a decision.

**7.3 Merge proposals.** Every AI proposal to alter user content is a diff the user approves (§ 5). Regeneration
never touches an insight with `approvalState == .locked` or any user-authored block.

**7.4 Confirm-before-export gate (I6).** Export and any external send present a **share preview generated by
the export code path itself** (`docs/02` § 7), enumerating: destination, recipients, each artifact included,
transcript inclusion yes/no, audio inclusion and duration, attachments by name, redactions applied, private
blocks withheld (count only), and expiry/passcode for share grants. Confirmation is per payload. The button
reads "Send to <destination>", never "Done". After sending, an `IntegrationReceipt` row appears with the
external ID; retry is idempotent and states "Already sent" rather than duplicating.

**7.5 Decision ledger.** Decisions show statement, approver, decided-at, rationale, alternatives considered,
evidence, and `supersedes` chain with a "Superseded by" link. A decision may not enter `Approved` without ≥ 1
evidence span.

**7.6 Unanswered-question queue.** `.openQuestion` insights and `.question` note blocks collect into a queue in
Actions with **Answer**, **Convert to action**, **Ask** (pre-scoped to this meeting), and **Dismiss**.
Answering stores the answer as a note block linked to the question; it does not edit the transcript.

---

## 8. Cross-device state communication

| Situation | Required UI response |
|---|---|
| Meeting started on Watch, user opens iPad | iPad shows the meeting as `Recording` on `originDeviceID`, with "Audio is on the Apple Watch. It will appear here after the meeting, once it transfers." No live audio, no live transcript, no progress bar implying streaming. |
| User starts iPhone recording while Watch is recording | Blocking sheet: "Already recording on Apple Watch." Options (canonical, see `docs/03` § 11): **Keep recording on Watch** (opens the Watch meeting for control), **Take over on iPhone** (sealed stop on Watch, new linked continuation meeting), **Record separately** (distinct `meetingID`, later offered as a merge candidate), **Cancel**. Never silently join or stop the Watch. |
| AirPods connect mid-meeting | `.routeChange(from,to)` timeline event; non-modal banner "Input changed to AirPods" with **Undo** where the platform allows; audio continues; the transcript timeline shows a route marker. |
| Participant asks to be removed | Meeting → Sharing → **Remove a participant's audio**: guided range selection, redaction preview (§ 6.9), a `ConsentRecord` note, and a redaction certificate option. Copy describes what the product does; it makes no legal claim. |
| AI names the wrong owner | One-tap **Wrong owner** on the action; corrected owner stored in correction memory; a "Corrected by you" tag persists; existing exports are not retroactively changed but are flagged "Owner changed after export". |
| Summary contradicts the transcript | `EntailmentChecker` failure downgrades the claim to `.aiSuggests` and shows "Could not verify against the transcript" with a **See evidence** link and **Regenerate**. The claim is never silently deleted. |
| Calendar title is sensitive | `isTitleSensitive` hides the title everywhere except the unlocked in-app Meeting detail: notifications, widgets, complication, Live Activity, presentation mode, and Spotlight show "Meeting". Never sent to analytics or crash reports. |
| User tries to delete the Watch copy before transfer | Deletion is refused with: "These n segments have not reached your iPhone yet. Deleting now would lose them." Options: **Retry transfer**, **Keep**, and an explicitly destructive **Delete anyway** requiring a typed confirmation. Automatic reclamation requires `TransferState == .verified` plus retention grace. |
| Watch battery critical | Persistent warning at the first threshold; at the critical threshold, `sealedStop(reason:)` is initiated **before** shutdown, with "Recording sealed — battery critical. n segments saved." No unattended data loss without a disclosed reason. |
| No iCloud account | Meetings remain fully usable locally. Sync surfaces state "Not signed in to iCloud — meetings stay on this device." Actions: **Sign in**, **Export**, **Dismiss**. No sync spinner, no retry loop. |
| iCloud quota full | Per-meeting badge "Not backed up — iCloud storage full", with the exact pending byte count, plus **Manage storage**, **Export**, **Switch this meeting to local-only**. Uploads back off; local data is never trimmed to make room. |
| Partial meeting with missing segments | `Availability == .partial(missing:)`. The timeline renders the exact gap ranges, the device that last held them, and the segment sequence numbers. Actions: **Search other devices**, **Request retransfer**. Summaries generated over a partial meeting carry a persistent "Generated from a partial recording" banner. |

---

## 9. Copy rules

1. Never describe the product as recording phone calls or other apps' audio. Supported sources are named
   explicitly: in-room microphone, imported media, disclosed in-app dialer, authorized connector.
2. Never imply Watch→iPad live streaming or live audio relay. Use "will appear after transfer".
3. Never say "Saved", "Recording", or "Backed up" before the corresponding durable write or verified receipt
   (I1, and `TransferState == .verified` for backup claims).
4. User-visible state names match `docs/02` § 3 exactly: `Arming` → "Preparing", `Recording`, `Paused`,
   `Interrupted`, `Finalizing`, `Processing`, `SavedRaw` → "Saved on <device>", `ReadyForReview` → "Ready for
   review", `PartialFailure` → "Partly processed". A mapping table lives in `NSPDesignSystem`; no ad-hoc
   strings.
5. Every error names a **cause** and an **action**: "Couldn't start — microphone in use by another app. Try
   again." Never "Something went wrong."
6. Consent copy describes behaviour and offers tools; it states no legal conclusion, gives no jurisdictional
   advice, and never says a recording "is legal" or "is compliant".
7. No single accuracy percentage for transcription. Confidence is per-token and per-turn.
8. AI output is labelled by `claimKind`; "decision" is reserved for grounded, approved decisions (I4).
9. Never present meeting content as an instruction the app followed — content is untrusted input (I7), so no
   copy of the form "your notes asked me to…".

---

## 10. Accessibility (implementable rules)

| Requirement | Rule |
|---|---|
| VoiceOver labels | Every control has a label, a value where stateful, and a hint where the outcome is non-obvious. Record control: label "Record", value = current lifecycle state. |
| State announcements | Lifecycle transitions post `.announcement` (Watch and phone): "Preparing", "Recording", "Paused", "Interrupted", "Finalizing", "Saved on Apple Watch". Announcements fire on the same durable event as the haptic, never earlier (I1). |
| Dynamic Type | All text, including Watch and complications, scales to the largest accessibility sizes. Layouts reflow vertically; no truncation of state names, causes, or actions. Buttons grow; icon-only controls are prohibited for Stop, Confirm, and Send. |
| Non-colour status | Every state uses shape/glyph/text in addition to colour: recording indicator, provisional text, confidence, proposed vs confirmed, transfer state. Verified by a greyscale snapshot test per surface. |
| Reduced Motion | Level meters become numeric readouts; auto-scroll becomes stepwise; transitions become cross-fades; no parallax or looping pulse. |
| Haptic alternatives | Every haptic has a persistent visual equivalent, and every visual-only confirmation has an optional haptic. When haptics are off, Start/Stop confirmations use a dwell state that remains until dismissed. |
| Captions | All in-app instructional media is captioned; VTT/SRT export uses the canonical transcript. |
| Switch Control / Full Keyboard Access | Stop, Confirm, and Send are reachable without gestures; no action is gesture-only (§ 3.3). |
| Test coverage | Automated VoiceOver-driven tests cover full workflows end to end: start on Watch → marker → stop → review → confirm action → export. A workflow that cannot be completed with VoiceOver is a release blocker (`docs/10`). |

---

## 11. Empty, loading, error, and partial states

| Surface | Empty | Loading | Error | Partial |
|---|---|---|---|---|
| Today | "No meetings yet" + Start + a one-line explanation of Watch capture | Skeleton rows, ≤ 1 s budget | Attention row with cause + action | Active session card plus a pending-transfer count |
| Library | "No meetings match these filters" + **Clear filters** | Paged skeletons; never blocks search input | "Couldn't load meetings — database locked. Retry." | Rows show `Availability` badges |
| Meeting → Transcript | "No transcript yet" + reason (queued / on-device unavailable / local-only) + **Transcribe now** | Provisional turns stream in per § 6 | "Transcription failed — <cause>" + **Retry** + audio still playable | "Transcript covers 42 of 58 minutes" with gap markers |
| Meeting → Insights | "No summary yet" + processing mode explanation | Per-layer placeholders | Failed layer named individually; other layers still shown | "Generated from a partial recording" banner |
| Meeting → Actions | "No actions found. Add one." | — | Export failure with receipt + **Retry (safe)** | Actions with `.unresolved` owners grouped as "Needs your input" |
| Ask | Scope selector with "Choose a scope to ask" | Streaming answer with citations appearing as they resolve | "Couldn't answer — no meetings in scope." | "Answered from 3 of 5 meetings; 2 are still processing." |
| Watch Ready | "No meetings on this Watch" | Never a bare spinner: show "Checking storage…" with a timeout | Cause + action within the small screen, scrollable | Pending-transfer count in the status row |
| Sync | "Everything is up to date" with last-checked time | Progress with item counts, not a bare spinner | Explicit account/quota states (§ 8) | "3 meetings partly uploaded" |

No spinner may run without a timeout and a subsequent cause-bearing state (`docs/01` § 7).

---

## 12. Onboarding

**12.1 Permission sequence and rationale.** Permissions are requested in the order the user will hit them, each
preceded by a one-screen explanation of what breaks without it:

1. **Microphone** — required; nothing works without it. Requested first so the first-run success can be real.
2. **Watch app install / notifications for capture state** — required to communicate `Recording` off-screen.
3. **Speech recognition** (on-device) — requested at first transcription, not at launch.
4. **Calendar** — optional, requested when the user first taps *Upcoming*.
5. **Contacts** — optional, requested at first owner assignment.
6. **Siri / Shortcuts** — optional, offered after the first successful recording.

iCloud is never a gate: the app must be fully usable signed out.

**12.2 Consent education.** After the microphone grant and before the first recording, a single screen explains
that participants should be informed, offers a configurable announcement line, and lets the user set whether
the app should prompt to record consent per meeting. It states no legal conclusion (§ 9.6). Its choices write a
`Policy` snapshot, and the per-meeting `ConsentRecord` links back to it.

**12.3 Default processing mode.** The user chooses once, with plain descriptions and a clear default of
`.onDevicePreferred`:

| Choice | Described as | Consequence shown |
|---|---|---|
| `.localOnly` | "Nothing leaves this device" | No cloud processing, no iCloud sync for those meetings (I5) |
| `.onDevicePreferred` | "Process on device when possible" | Some summaries may be unavailable on older hardware |
| `.cloudAllowed` | "Allow cloud processing per meeting" | Named cloud steps, ephemeral copies, deletion receipts |

The mode is changeable per meeting before `Arming` freezes it, and the frozen value is shown in the active
session view.

**12.4 First-session success criteria.** The user must, in the first session: (1) start a recording from the
Watch or iPhone and see `Recording` acknowledged after the durable write, (2) add one marker, (3) stop via the
confirmation, and (4) open the resulting meeting and play audio from a tapped transcript word or marker. The
first-run flow ends only when all four have occurred; incomplete onboarding resumes on next launch from the
step that failed, with a cause. A one-minute test recording is offered explicitly as the safe way to do this.
