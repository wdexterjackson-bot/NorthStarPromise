import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `person` table (docs/02 §5). `Person.aliases` lives in the
/// sibling `person_alias` table — same "row owns its own columns,
/// repository owns the join" split `NoteBlockRow`/`opLog` uses.
struct PersonRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "person"

    var personID: String
    var workspaceID: String
    var name: String
    var role: String?
    var organization: String?
    var voiceEnrollmentRef: String?
    var contactLink: String?
    var notes: String?
    var ambientListeningOptOut: Bool
    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int

    enum CodingKeys: String, CodingKey {
        case personID = "person_id"
        case workspaceID = "workspace_id"
        case name
        case role
        case organization
        case voiceEnrollmentRef = "voice_enrollment_ref"
        case contactLink = "contact_link"
        case notes
        case ambientListeningOptOut = "ambient_listening_opt_out"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
    }

    init(person: Person, createdAt: Date, updatedAt: Date, rowRevision: Int) {
        self.personID = person.personID.rawValue.uuidString
        self.workspaceID = person.workspaceID.rawValue.uuidString
        self.name = person.name
        self.role = person.role
        self.organization = person.organization
        self.voiceEnrollmentRef = person.voiceEnrollmentRef
        self.contactLink = person.contactLink
        self.notes = person.notes
        self.ambientListeningOptOut = person.ambientListeningOptOut
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
    }

    func asDomain(aliases: [String], tags: [String]) throws -> Person {
        guard let personUUID = UUID(uuidString: personID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "person_id", value: personID)
        }
        guard let workspaceUUID = UUID(uuidString: workspaceID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "workspace_id", value: workspaceID)
        }
        return Person(
            personID: PersonID(rawValue: personUUID), workspaceID: WorkspaceID(rawValue: workspaceUUID), name: name,
            aliases: aliases, role: role, organization: organization, voiceEnrollmentRef: voiceEnrollmentRef,
            contactLink: contactLink, tags: tags, notes: notes, ambientListeningOptOut: ambientListeningOptOut)
    }
}

/// Mirrors the `person_tag` table — one row per `Person.tags` entry,
/// ordered by `position`. Same "row owns its own columns, repository owns
/// the join" split `person_alias` uses.
struct PersonTagRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "person_tag"

    var personID: String
    var position: Int
    var tag: String

    enum CodingKeys: String, CodingKey {
        case personID = "person_id"
        case position
        case tag
    }
}

/// Mirrors the `person_alias` table — one row per `Person.aliases` entry,
/// ordered by `position`.
struct PersonAliasRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "person_alias"

    var personID: String
    var position: Int
    var alias: String

    enum CodingKeys: String, CodingKey {
        case personID = "person_id"
        case position
        case alias
    }
}
