import Foundation

/// How consent was obtained for a meeting. Explicitly not a legal
/// certification — it records what the app observed, nothing more
/// (docs/02 §2, docs/06).
public struct ConsentRecord: Sendable, Hashable, Codable, Identifiable {
    public let consentRecordID: ConsentRecordID
    public var id: ConsentRecordID { consentRecordID }
    public let meetingID: MeetingID

    public let method: ConsentMethod
    public let timestamp: Date
    public let participantsAcknowledged: [PersonID]

    public init(
        consentRecordID: ConsentRecordID,
        meetingID: MeetingID,
        method: ConsentMethod,
        timestamp: Date,
        participantsAcknowledged: [PersonID] = []
    ) {
        self.consentRecordID = consentRecordID
        self.meetingID = meetingID
        self.method = method
        self.timestamp = timestamp
        self.participantsAcknowledged = participantsAcknowledged
    }
}

/// How consent was communicated (docs/02 §2, `ConsentRecord.method`).
public enum ConsentMethod: String, Sendable, Hashable, Codable, CaseIterable {
    case verbalAnnouncement
    case checklistConfirmed
    case inviteDisclosure
}
