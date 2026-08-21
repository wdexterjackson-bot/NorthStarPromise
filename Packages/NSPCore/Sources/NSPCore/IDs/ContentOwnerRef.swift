/// The one thing a `Segment`, `TranscriptTurn`, or `NoteBlock` can belong to
/// — a `Meeting`, a `BrainDump`, or a `Note`. All three are real recordable/
/// annotatable containers with their own top-level identity (none is a
/// disguised `Meeting`), but they share one durable capture/storage
/// pipeline (`MeetingContainer`, `CaptureEngine`, `Segmenter`) rather than
/// each having a parallel copy of it — this type is what lets that sharing
/// happen without pretending a Brain Dump or a Note "is" a meeting anywhere
/// in the domain model. Persistence maps this to an `owner_kind` column
/// alongside the existing owner-id column, not a SQL foreign key (a single
/// column can't conditionally reference three different tables) — integrity
/// is enforced by each owner's own deletion path explicitly removing its
/// children instead.
public enum ContentOwnerRef: Sendable, Hashable, Codable {
    case meeting(MeetingID)
    case brainDump(BrainDumpID)
    case note(NoteID)
}
