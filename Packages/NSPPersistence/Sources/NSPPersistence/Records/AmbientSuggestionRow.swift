import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `ambient_suggestion` table (NSP-161, "Overheard").
/// `AmbientEvidence` (excerpt + timestamp) is flat enough to live as two
/// plain columns rather than a child table.
struct AmbientSuggestionRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "ambient_suggestion"

    var ambientSuggestionID: String
    var workspaceID: String
    var kind: String
    var text: String
    var threadID: String?
    var counterpartyID: String?
    var evidenceExcerpt: String
    var evidenceCapturedAt: Date
    var status: String
    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int

    enum CodingKeys: String, CodingKey {
        case ambientSuggestionID = "ambient_suggestion_id"
        case workspaceID = "workspace_id"
        case kind
        case text
        case threadID = "thread_id"
        case counterpartyID = "counterparty_id"
        case evidenceExcerpt = "evidence_excerpt"
        case evidenceCapturedAt = "evidence_captured_at"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
    }

    init(suggestion: AmbientSuggestion, createdAt: Date, updatedAt: Date, rowRevision: Int) {
        self.ambientSuggestionID = suggestion.ambientSuggestionID.rawValue.uuidString
        self.workspaceID = suggestion.workspaceID.rawValue.uuidString
        self.kind = suggestion.kind.rawValue
        self.text = suggestion.text
        self.threadID = suggestion.threadID?.rawValue.uuidString
        self.counterpartyID = suggestion.counterpartyID?.rawValue.uuidString
        self.evidenceExcerpt = suggestion.evidence.excerpt
        self.evidenceCapturedAt = suggestion.evidence.capturedAt
        self.status = suggestion.status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
    }

    func asDomain() throws -> AmbientSuggestion {
        guard let idUUID = UUID(uuidString: ambientSuggestionID) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "ambient_suggestion_id", value: ambientSuggestionID)
        }
        guard let workspaceUUID = UUID(uuidString: workspaceID) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "workspace_id", value: workspaceID)
        }
        guard let kindValue = AmbientSuggestionKind(rawValue: kind) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "kind", value: kind)
        }
        guard let statusValue = AmbientSuggestionStatus(rawValue: status) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "status", value: status)
        }
        let resolvedThreadID = try threadID.map { string -> NSPThreadID in
            guard let uuid = UUID(uuidString: string) else {
                throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "thread_id", value: string)
            }
            return NSPThreadID(rawValue: uuid)
        }
        let resolvedCounterpartyID = try counterpartyID.map { string -> PersonID in
            guard let uuid = UUID(uuidString: string) else {
                throw PersistenceError.corruptRow(
                    table: Self.databaseTableName, column: "counterparty_id", value: string)
            }
            return PersonID(rawValue: uuid)
        }

        return AmbientSuggestion(
            ambientSuggestionID: AmbientSuggestionID(rawValue: idUUID), workspaceID: WorkspaceID(rawValue: workspaceUUID),
            kind: kindValue, text: text, threadID: resolvedThreadID, counterpartyID: resolvedCounterpartyID,
            evidence: AmbientEvidence(excerpt: evidenceExcerpt, capturedAt: evidenceCapturedAt), status: statusValue,
            createdAt: createdAt, updatedAt: updatedAt)
    }
}
