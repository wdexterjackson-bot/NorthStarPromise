import Foundation
@preconcurrency import GRDB
import NSPCore

/// CRUD for the `project_person` join table — the people tracked against a
/// Project (People plan phase 2, 2026-08-22), same replace-then-reinsert
/// pattern `MeetingAttendeeRepository`/`ThreadParticipantRepository` use.
public protocol ProjectPersonRepository: Sendable {
    func setPeople(for projectID: ProjectID, personIDs: Set<PersonID>) async throws
    func fetchPersonIDs(for projectID: ProjectID) async throws -> Set<PersonID>
    func fetchProjectIDs(for personID: PersonID) async throws -> Set<ProjectID>
}

public struct GRDBProjectPersonRepository: ProjectPersonRepository {
    private let dbWriter: any DatabaseWriter

    public init(dbWriter: any DatabaseWriter) {
        self.dbWriter = dbWriter
    }

    public func setPeople(for projectID: ProjectID, personIDs: Set<PersonID>) async throws {
        let projectIDString = projectID.rawValue.uuidString
        try await dbWriter.write { db in
            try ProjectPersonRow.filter(Column("project_id") == projectIDString).deleteAll(db)
            for personID in personIDs {
                try ProjectPersonRow(projectID: projectIDString, personID: personID.rawValue.uuidString).insert(db)
            }
        }
    }

    public func fetchPersonIDs(for projectID: ProjectID) async throws -> Set<PersonID> {
        let projectIDString = projectID.rawValue.uuidString
        return try await dbWriter.read { db in
            let rows = try ProjectPersonRow.filter(Column("project_id") == projectIDString).fetchAll(db)
            return Set(rows.compactMap { UUID(uuidString: $0.personID) }.map { PersonID(rawValue: $0) })
        }
    }

    public func fetchProjectIDs(for personID: PersonID) async throws -> Set<ProjectID> {
        let personIDString = personID.rawValue.uuidString
        return try await dbWriter.read { db in
            let rows = try ProjectPersonRow.filter(Column("person_id") == personIDString).fetchAll(db)
            return Set(rows.compactMap { UUID(uuidString: $0.projectID) }.map { ProjectID(rawValue: $0) })
        }
    }
}

struct ProjectPersonRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "project_person"
    var projectID: String
    var personID: String

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case personID = "person_id"
    }
}
