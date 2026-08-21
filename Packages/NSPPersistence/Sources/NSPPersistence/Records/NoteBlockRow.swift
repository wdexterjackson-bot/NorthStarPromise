import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `note_block` table (docs/02 §5). `opLog` lives in the
/// sibling `note_operation` table — `NoteBlockRepository` assembles the two
/// into one `NoteBlock`, the same "row owns its own columns, repository
/// owns the join" split as everywhere else in this package.
struct NoteBlockRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "note_block"

    var blockID: String
    var ownerID: String
    var ownerKind: String
    var authorID: String
    var type: String
    var contentKind: String
    var contentText: String?
    var contentAssetPath: String?
    var creationRangeStartSample: Int64
    var creationRangeEndSample: Int64
    var privacy: String
    var mergeState: String
    var mergeStateDiffID: String?
    var mergeStateInsightID: String?
    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int

    enum CodingKeys: String, CodingKey {
        case blockID = "block_id"
        case ownerID = "meeting_id"
        case ownerKind = "owner_kind"
        case authorID = "author_id"
        case type
        case contentKind = "content_kind"
        case contentText = "content_text"
        case contentAssetPath = "content_asset_path"
        case creationRangeStartSample = "creation_range_start_sample"
        case creationRangeEndSample = "creation_range_end_sample"
        case privacy
        case mergeState = "merge_state"
        case mergeStateDiffID = "merge_state_diff_id"
        case mergeStateInsightID = "merge_state_insight_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
    }

    init(block: NoteBlock, createdAt: Date, updatedAt: Date, rowRevision: Int) {
        self.blockID = block.blockID.rawValue.uuidString
        let owner = ContentOwnerRefColumns.encode(block.owner)
        self.ownerID = owner.id
        self.ownerKind = owner.kind
        self.authorID = block.authorID.rawValue.uuidString
        self.type = block.type.rawValue
        let encodedContent = Self.encode(block.content)
        self.contentKind = encodedContent.kind
        self.contentText = encodedContent.text
        self.contentAssetPath = encodedContent.assetPath
        self.creationRangeStartSample = block.creationRange.startSample
        self.creationRangeEndSample = block.creationRange.endSample
        self.privacy = block.privacy.rawValue
        switch block.mergeState {
        case .standalone:
            self.mergeState = "standalone"
            self.mergeStateDiffID = nil
            self.mergeStateInsightID = nil
        case .proposedForRecap(let diffID):
            self.mergeState = "proposedForRecap"
            self.mergeStateDiffID = diffID
            self.mergeStateInsightID = nil
        case .mergedIntoRecap(let insightID):
            self.mergeState = "mergedIntoRecap"
            self.mergeStateDiffID = nil
            self.mergeStateInsightID = insightID.rawValue.uuidString
        }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
    }

    /// `BlockContent`'s encoded column values — a named type in place of a
    /// 3-member tuple (SwiftLint's `large_tuple` rule caps tuples at 2).
    struct EncodedContent {
        let kind: String
        let text: String?
        let assetPath: String?
    }

    static func encode(_ content: BlockContent) -> EncodedContent {
        switch content {
        case .text(let text): return EncodedContent(kind: "text", text: text, assetPath: nil)
        case .assetReference(let path): return EncodedContent(kind: "assetReference", text: nil, assetPath: path)
        }
    }

    static func decodeContent(kind: String, text: String?, assetPath: String?, table: String) throws -> BlockContent {
        switch kind {
        case "text":
            guard let text else { throw PersistenceError.corruptRow(table: table, column: "content_text", value: nil) }
            return .text(text)
        case "assetReference":
            guard let assetPath else {
                throw PersistenceError.corruptRow(table: table, column: "content_asset_path", value: nil)
            }
            return .assetReference(path: assetPath)
        default:
            throw PersistenceError.corruptRow(table: table, column: "content_kind", value: kind)
        }
    }

    func asDomain(opLog: [NSPCore.Operation]) throws -> NoteBlock {
        guard let blockUUID = UUID(uuidString: blockID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "block_id", value: blockID)
        }
        let owner = try ContentOwnerRefColumns.decode(id: ownerID, kind: ownerKind, table: Self.databaseTableName)
        guard let authorUUID = UUID(uuidString: authorID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "author_id", value: authorID)
        }
        guard let blockType = NoteBlockType(rawValue: type) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "type", value: type)
        }
        guard let blockPrivacy = BlockPrivacy(rawValue: privacy) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "privacy", value: privacy)
        }

        let resolvedMergeState: MergeState
        switch mergeState {
        case "standalone": resolvedMergeState = .standalone
        case "proposedForRecap":
            guard let diffID = mergeStateDiffID else {
                throw PersistenceError.corruptRow(
                    table: Self.databaseTableName, column: "merge_state_diff_id", value: nil)
            }
            resolvedMergeState = .proposedForRecap(diffID: diffID)
        case "mergedIntoRecap":
            guard let insightIDString = mergeStateInsightID, let insightUUID = UUID(uuidString: insightIDString) else {
                throw PersistenceError.corruptRow(
                    table: Self.databaseTableName, column: "merge_state_insight_id", value: mergeStateInsightID)
            }
            resolvedMergeState = .mergedIntoRecap(insightID: InsightID(rawValue: insightUUID))
        default:
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "merge_state", value: mergeState)
        }

        return NoteBlock(
            blockID: NoteBlockID(rawValue: blockUUID),
            owner: owner,
            authorID: PersonID(rawValue: authorUUID),
            type: blockType,
            content: try Self.decodeContent(
                kind: contentKind, text: contentText, assetPath: contentAssetPath, table: Self.databaseTableName),
            creationRange: SampleRange(startSample: creationRangeStartSample, endSample: creationRangeEndSample),
            privacy: blockPrivacy,
            mergeState: resolvedMergeState,
            opLog: opLog
        )
    }
}

/// Mirrors the `note_operation` table (docs/02 §5) — one row per
/// `NoteBlock.opLog` entry, ordered by `position` since `Operation` itself
/// carries no ordinal.
struct NoteOperationRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "note_operation"

    var id: Int64?
    var blockID: String
    var position: Int
    var authorID: String
    var timestamp: Int64
    var contentKind: String
    var contentText: String?
    var contentAssetPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case blockID = "block_id"
        case position
        case authorID = "author_id"
        case timestamp
        case contentKind = "content_kind"
        case contentText = "content_text"
        case contentAssetPath = "content_asset_path"
    }

    init(blockID: String, position: Int, operation: NSPCore.Operation) {
        self.id = nil
        self.blockID = blockID
        self.position = position
        self.authorID = operation.authorID.rawValue.uuidString
        self.timestamp = operation.timestamp
        let encodedContent = NoteBlockRow.encode(operation.content)
        self.contentKind = encodedContent.kind
        self.contentText = encodedContent.text
        self.contentAssetPath = encodedContent.assetPath
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func asDomain() throws -> NSPCore.Operation {
        guard let authorUUID = UUID(uuidString: authorID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "author_id", value: authorID)
        }
        return NSPCore.Operation(
            authorID: PersonID(rawValue: authorUUID), timestamp: timestamp,
            content: try NoteBlockRow.decodeContent(
                kind: contentKind, text: contentText, assetPath: contentAssetPath, table: Self.databaseTableName))
    }
}
