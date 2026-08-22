/// What kind of agenda entry a `Meeting` represents (docs/07's "Add to
/// Today's Agenda" flow) — `.recorded` is the default for every meeting
/// captured the ordinary way; `.notesOnly` marks the no-audio-expected
/// shell `AddAgendaItemFormView` can create directly. A third "Action
/// Reminder" type used to live here as `.reminder` — collapsed into a
/// plain, due-dated, no-meeting `Action` instead ("The Spine" recommendation,
/// 2026-08-22, `Migration022CollapseActionReminders`) since a reminder
/// living as a phantom Meeting never showed up on a Person's page, in Needs
/// You, or in any relationship query.
public enum MeetingKind: String, Sendable, Hashable, Codable, CaseIterable {
    case recorded
    case notesOnly
}
