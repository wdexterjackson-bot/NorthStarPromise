/// One uninhabited tag enum per entity kind, plus the `TypedID` alias that
/// uses it. Keeps every entity's identifier its own type even though all are
/// UUIDv7 underneath (docs/02 §2).
public enum MeetingIDTag: Sendable {}
public typealias MeetingID = TypedID<MeetingIDTag>

public enum WorkspaceIDTag: Sendable {}
public typealias WorkspaceID = TypedID<WorkspaceIDTag>

public enum DeviceIDTag: Sendable {}
public typealias DeviceID = TypedID<DeviceIDTag>

public enum PolicyIDTag: Sendable {}
public typealias PolicyID = TypedID<PolicyIDTag>

public enum ConsentRecordIDTag: Sendable {}
public typealias ConsentRecordID = TypedID<ConsentRecordIDTag>

public enum SegmentIDTag: Sendable {}
public typealias SegmentID = TypedID<SegmentIDTag>

public enum TimelineEventIDTag: Sendable {}
public typealias TimelineEventID = TypedID<TimelineEventIDTag>

public enum TranscriptTurnIDTag: Sendable {}
public typealias TranscriptTurnID = TypedID<TranscriptTurnIDTag>

public enum PersonIDTag: Sendable {}
public typealias PersonID = TypedID<PersonIDTag>

public enum NoteBlockIDTag: Sendable {}
public typealias NoteBlockID = TypedID<NoteBlockIDTag>

public enum InsightIDTag: Sendable {}
public typealias InsightID = TypedID<InsightIDTag>

public enum ActionIDTag: Sendable {}
public typealias ActionID = TypedID<ActionIDTag>

public enum DecisionIDTag: Sendable {}
public typealias DecisionID = TypedID<DecisionIDTag>

public enum GlossaryEntryIDTag: Sendable {}
public typealias GlossaryEntryID = TypedID<GlossaryEntryIDTag>

public enum ShareGrantIDTag: Sendable {}
public typealias ShareGrantID = TypedID<ShareGrantIDTag>

public enum IntegrationReceiptIDTag: Sendable {}
public typealias IntegrationReceiptID = TypedID<IntegrationReceiptIDTag>

public enum AuditEventIDTag: Sendable {}
public typealias AuditEventID = TypedID<AuditEventIDTag>

public enum GrantIDTag: Sendable {}
public typealias GrantID = TypedID<GrantIDTag>
