import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD for the `meeting_attendee` join table — the data behind "People"
/// (who was actually in a given meeting), same replace-then-reinsert
/// pattern as `ProjectRepository`'s `meeting_project` join.
public protocol MeetingAttendeeRepository: Sendable {
    func setAttendees(for meetingID: MeetingID, personIDs: Set<PersonID>) async throws
    func fetchAttendeeIDs(for meetingID: MeetingID) async throws -> Set<PersonID>
    func fetchMeetingIDs(for personID: PersonID) async throws -> Set<MeetingID>
}

public struct GRDBMeetingAttendeeRepository: MeetingAttendeeRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func setAttendees(for meetingID: MeetingID, personIDs: Set<PersonID>) async throws {
        let meetingIDString = meetingID.rawValue.uuidString
        try await dbWriter.write { db in
            try MeetingAttendeeRow.filter(Column("meeting_id") == meetingIDString).deleteAll(db)
            for personID in personIDs {
                try MeetingAttendeeRow(meetingID: meetingIDString, personID: personID.rawValue.uuidString).insert(db)
            }
        }
    }

    public func fetchAttendeeIDs(for meetingID: MeetingID) async throws -> Set<PersonID> {
        let meetingIDString = meetingID.rawValue.uuidString
        return try await dbWriter.read { db in
            let rows = try MeetingAttendeeRow.filter(Column("meeting_id") == meetingIDString).fetchAll(db)
            return Set(rows.compactMap { UUID(uuidString: $0.personID) }.map { PersonID(rawValue: $0) })
        }
    }

    public func fetchMeetingIDs(for personID: PersonID) async throws -> Set<MeetingID> {
        let personIDString = personID.rawValue.uuidString
        return try await dbWriter.read { db in
            let rows = try MeetingAttendeeRow.filter(Column("person_id") == personIDString).fetchAll(db)
            return Set(rows.compactMap { UUID(uuidString: $0.meetingID) }.map { MeetingID(rawValue: $0) })
        }
    }
}

struct MeetingAttendeeRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "meeting_attendee"
    var meetingID: String
    var personID: String

    enum CodingKeys: String, CodingKey {
        case meetingID = "meeting_id"
        case personID = "person_id"
    }
}
