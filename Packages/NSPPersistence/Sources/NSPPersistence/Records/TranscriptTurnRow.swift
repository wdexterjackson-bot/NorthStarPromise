import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `transcript_turn` table (docs/02 §5). `tokens`,
/// `languageSpans`, and `segmentRefs` are arrays, exploded into their own
/// child tables (`transcript_token`, `transcript_language_span`,
/// `transcript_turn_segment`) the same way `PolicyRow` explodes
/// `blockedDomains`.
struct TranscriptTurnRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "transcript_turn"

    var turnID: String
    var ownerID: String
    var ownerKind: String
    var revision: Int
    var isProvisional: Bool
    var speakerClusterID: String?
    var personID: String?
    var editState: String
    var editStateRevisionOf: Int?
    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int
    var cloudRecordChangeTag: String?

    enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case ownerID = "meeting_id"
        case ownerKind = "owner_kind"
        case revision
        case isProvisional = "is_provisional"
        case speakerClusterID = "speaker_cluster_id"
        case personID = "person_id"
        case editState = "edit_state"
        case editStateRevisionOf = "edit_state_revision_of"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
        case cloudRecordChangeTag = "cloud_record_change_tag"
    }

    init(turn: TranscriptTurn, createdAt: Date, updatedAt: Date, rowRevision: Int, cloudRecordChangeTag: String?) {
        self.turnID = turn.turnID.rawValue.uuidString
        let owner = ContentOwnerRefColumns.encode(turn.owner)
        self.ownerID = owner.id
        self.ownerKind = owner.kind
        self.revision = turn.revision
        self.isProvisional = turn.isProvisional
        self.speakerClusterID = turn.speakerClusterID
        self.personID = turn.personID?.rawValue.uuidString
        switch turn.editState {
        case .machine:
            self.editState = "machine"
            self.editStateRevisionOf = nil
        case .userEdited(let revisionOf):
            self.editState = "userEdited"
            self.editStateRevisionOf = revisionOf
        case .userConfirmed:
            self.editState = "userConfirmed"
            self.editStateRevisionOf = nil
        }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
        self.cloudRecordChangeTag = cloudRecordChangeTag
    }

    func asDomain(tokens: [Token], languageSpans: [LanguageSpan], segmentRefs: [SegmentID]) throws -> TranscriptTurn {
        guard let turnUUID = UUID(uuidString: turnID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "turn_id", value: turnID)
        }
        let owner = try ContentOwnerRefColumns.decode(id: ownerID, kind: ownerKind, table: Self.databaseTableName)
        let resolvedPersonID: PersonID? =
            try personID.map {
                guard let uuid = UUID(uuidString: $0) else {
                    throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "person_id", value: $0)
                }
                return PersonID(rawValue: uuid)
            }
        let resolvedEditState: EditState
        switch editState {
        case "machine": resolvedEditState = .machine
        case "userEdited": resolvedEditState = .userEdited(revisionOf: editStateRevisionOf ?? 0)
        case "userConfirmed": resolvedEditState = .userConfirmed
        default:
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "edit_state", value: editState)
        }

        return TranscriptTurn(
            turnID: TranscriptTurnID(rawValue: turnUUID), owner: owner,
            revision: revision, isProvisional: isProvisional, speakerClusterID: speakerClusterID,
            personID: resolvedPersonID, tokens: tokens, languageSpans: languageSpans, segmentRefs: segmentRefs,
            editState: resolvedEditState)
    }
}

/// Mirrors `transcript_token` — the exploded form of `TranscriptTurn.tokens`.
struct TranscriptTokenRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "transcript_token"
    var id: Int64?
    var turnID: String
    var position: Int
    var text: String
    var startSample: Int64
    var endSample: Int64
    var confidence: Double
    var languageTag: String?

    enum CodingKeys: String, CodingKey {
        case id
        case turnID = "turn_id"
        case position
        case text
        case startSample = "start_sample"
        case endSample = "end_sample"
        case confidence
        case languageTag = "language_tag"
    }

    init(turnID: String, position: Int, token: Token) {
        self.id = nil
        self.turnID = turnID
        self.position = position
        self.text = token.text
        self.startSample = token.startSample
        self.endSample = token.endSample
        self.confidence = token.confidence
        self.languageTag = token.languageTag
    }

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    func asDomain() -> Token {
        Token(
            text: text, startSample: startSample, endSample: endSample, confidence: confidence, languageTag: languageTag
        )
    }
}

/// Mirrors `transcript_language_span` — the exploded form of
/// `TranscriptTurn.languageSpans`.
struct TranscriptLanguageSpanRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "transcript_language_span"
    var id: Int64?
    var turnID: String
    var position: Int
    var languageTag: String
    var startSample: Int64
    var endSample: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case turnID = "turn_id"
        case position
        case languageTag = "language_tag"
        case startSample = "start_sample"
        case endSample = "end_sample"
    }

    init(turnID: String, position: Int, span: LanguageSpan) {
        self.id = nil
        self.turnID = turnID
        self.position = position
        self.languageTag = span.languageTag
        self.startSample = span.range.startSample
        self.endSample = span.range.endSample
    }

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    func asDomain() -> LanguageSpan {
        LanguageSpan(languageTag: languageTag, range: SampleRange(startSample: startSample, endSample: endSample))
    }
}

/// Mirrors `transcript_turn_segment` — the exploded form of
/// `TranscriptTurn.segmentRefs`.
struct TranscriptTurnSegmentRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "transcript_turn_segment"
    var turnID: String
    var segmentID: String
    var position: Int

    enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case segmentID = "segment_id"
        case position
    }

    func asDomain() throws -> SegmentID {
        guard let uuid = UUID(uuidString: segmentID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "segment_id", value: segmentID)
        }
        return SegmentID(rawValue: uuid)
    }
}
