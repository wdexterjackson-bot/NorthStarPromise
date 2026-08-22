import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD for the `thread_participant` join table — the people tracked
/// against a Thread (People plan phase 2, 2026-08-22), same replace-then-
/// reinsert pattern `MeetingAttendeeRepository`/`ProjectRepository`'s
/// `meeting_project` join use.
public protocol ThreadParticipantRepository: Sendable {
    func setParticipants(for threadID: NSPThreadID, personIDs: Set<PersonID>) async throws
    func fetchParticipantIDs(for threadID: NSPThreadID) async throws -> Set<PersonID>
    func fetchThreadIDs(for personID: PersonID) async throws -> Set<NSPThreadID>
}

public struct GRDBThreadParticipantRepository: ThreadParticipantRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func setParticipants(for threadID: NSPThreadID, personIDs: Set<PersonID>) async throws {
        let threadIDString = threadID.rawValue.uuidString
        try await dbWriter.write { db in
            try ThreadParticipantRow.filter(Column("thread_id") == threadIDString).deleteAll(db)
            for personID in personIDs {
                try ThreadParticipantRow(threadID: threadIDString, personID: personID.rawValue.uuidString).insert(db)
            }
        }
    }

    public func fetchParticipantIDs(for threadID: NSPThreadID) async throws -> Set<PersonID> {
        let threadIDString = threadID.rawValue.uuidString
        return try await dbWriter.read { db in
            let rows = try ThreadParticipantRow.filter(Column("thread_id") == threadIDString).fetchAll(db)
            return Set(rows.compactMap { UUID(uuidString: $0.personID) }.map { PersonID(rawValue: $0) })
        }
    }

    public func fetchThreadIDs(for personID: PersonID) async throws -> Set<NSPThreadID> {
        let personIDString = personID.rawValue.uuidString
        return try await dbWriter.read { db in
            let rows = try ThreadParticipantRow.filter(Column("person_id") == personIDString).fetchAll(db)
            return Set(rows.compactMap { UUID(uuidString: $0.threadID) }.map { NSPThreadID(rawValue: $0) })
        }
    }
}

struct ThreadParticipantRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "thread_participant"
    var threadID: String
    var personID: String

    enum CodingKeys: String, CodingKey {
        case threadID = "thread_id"
        case personID = "person_id"
    }
}
