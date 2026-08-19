import Foundation
import NSPCore
import NSPPersistence
import NSPPolicy

/// In-memory `AuditEventRecorder` so tests never touch a real database
/// (docs/11 §4, NSP-016). Records every event it receives, in call order,
/// so tests can assert both content and count.
public actor FakeAuditEventRecorder: AuditEventRecorder {
    public private(set) var recordedEvents: [AuditEvent] = []
    private let failing: Bool

    public init(failing: Bool = false) {
        self.failing = failing
    }

    public func record(_ event: AuditEvent) async throws {
        if failing {
            throw PersistenceError.notFound(table: "audit_event", key: event.auditEventID.description)
        }
        recordedEvents.append(event)
    }
}

/// In-memory `ConsentRecordLookup` (docs/11 §4, NSP-016). Answers `true` for
/// any meeting explicitly added via `grantConsent`.
public actor FakeConsentRecordLookup: ConsentRecordLookup {
    private var meetingsWithConsent: Set<MeetingID> = []

    public init(meetingsWithConsent: Set<MeetingID> = []) {
        self.meetingsWithConsent = meetingsWithConsent
    }

    public func grantConsent(for meetingID: MeetingID) {
        meetingsWithConsent.insert(meetingID)
    }

    public func hasConsentRecord(for meetingID: MeetingID) async -> Bool {
        meetingsWithConsent.contains(meetingID)
    }
}

/// In-memory `PolicySnapshotLookup` (docs/11 §4, NSP-016).
public actor FakePolicySnapshotLookup: PolicySnapshotLookup {
    private var policies: [MeetingID: Policy] = [:]

    public init() {}

    public func setPolicy(_ policy: Policy, for meetingID: MeetingID) {
        policies[meetingID] = policy
    }

    public func policy(for meetingID: MeetingID) async -> Policy? {
        policies[meetingID]
    }
}
