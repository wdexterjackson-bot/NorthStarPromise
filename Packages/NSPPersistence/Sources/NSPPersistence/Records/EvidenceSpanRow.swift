import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `evidence_span` table — shared storage for `Insight.evidence`,
/// `Action.evidence`, and `Decision.evidence` (docs/02 §5: "exactly one
/// owner per span," enforced by a DB check constraint). `EvidenceSpan`
/// itself has no identity of its own; `evidenceSpanID` is a storage-layer
/// autoincrement key only, never exposed to `NSPCore`.
struct EvidenceSpanRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "evidence_span"

    var evidenceSpanID: Int64?
    var insightID: String?
    var actionID: String?
    var decisionID: String?
    var position: Int
    var meetingID: String
    var sampleStart: Int64
    var sampleEnd: Int64
    var quotedText: String
    var transcriptRevision: Int

    enum CodingKeys: String, CodingKey {
        case evidenceSpanID = "evidence_span_id"
        case insightID = "insight_id"
        case actionID = "action_id"
        case decisionID = "decision_id"
        case position
        case meetingID = "meeting_id"
        case sampleStart = "sample_start"
        case sampleEnd = "sample_end"
        case quotedText = "quoted_text"
        case transcriptRevision = "transcript_revision"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        evidenceSpanID = inserted.rowID
    }

    func asDomain() throws -> EvidenceSpan {
        guard let meetingUUID = UUID(uuidString: meetingID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "meeting_id", value: meetingID)
        }
        return EvidenceSpan(
            meetingID: MeetingID(rawValue: meetingUUID), turnIDs: [],
            sampleRange: SampleRange(
                startSample: sampleStart, endSample: sampleEnd),
            quotedText: quotedText, transcriptRevision: transcriptRevision)
    }
}

/// Mirrors `evidence_span_turn` — the exploded form of `EvidenceSpan.turnIDs`.
struct EvidenceSpanTurnRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "evidence_span_turn"
    var evidenceSpanID: Int64
    var turnID: String
    var position: Int

    enum CodingKeys: String, CodingKey {
        case evidenceSpanID = "evidence_span_id"
        case turnID = "turn_id"
        case position
    }
}

/// Which domain type an `evidence_span` row belongs to — the DB enforces
/// "exactly one" via a check constraint; this just names the three options
/// so callers never have to juggle three nullable ID parameters directly.
enum EvidenceSpanOwner {
    case insight(String)
    case action(String)
    case decision(String)
}

/// Shared read/write for the `evidence_span`/`evidence_span_turn` tables —
/// used by `GRDBInsightRepository`, `GRDBActionRepository`, and (once a
/// `Decision` repository exists) its `Decision` counterpart, so the
/// three-owner-column shape only has to be gotten right once.
enum EvidenceSpanPersistence {
    /// Replaces every span for `owner` — same delete-then-reinsert shape
    /// every other exploded-array field in this package uses.
    static func sync(_ db: Database, owner: EvidenceSpanOwner, meetingID: String, spans: [EvidenceSpan]) throws {
        try clear(db, owner: owner)
        let ownerValue = owner.value

        for (position, span) in spans.enumerated() {
            var row = EvidenceSpanRow(
                evidenceSpanID: nil,
                insightID: owner.isInsight ? ownerValue : nil,
                actionID: owner.isAction ? ownerValue : nil,
                decisionID: owner.isDecision ? ownerValue : nil,
                position: position, meetingID: meetingID, sampleStart: span.sampleRange.startSample,
                sampleEnd: span.sampleRange.endSample, quotedText: span.quotedText,
                transcriptRevision: span.transcriptRevision)
            try row.insert(db)
            guard let spanID = row.evidenceSpanID else { continue }
            for (turnPosition, turnID) in span.turnIDs.enumerated() {
                try EvidenceSpanTurnRow(
                    evidenceSpanID: spanID, turnID: turnID.rawValue.uuidString, position: turnPosition
                )
                .insert(db)
            }
        }
    }

    /// Deletes every span for `owner` without inserting replacements — the
    /// freestanding-`Action` path (`meetingID == nil`), since a span always
    /// needs a real meeting's transcript to quote from (Invariant I4) and a
    /// freestanding action has none. `sync` itself calls this first, then
    /// re-inserts.
    static func clear(_ db: Database, owner: EvidenceSpanOwner) throws {
        let ownerColumn = owner.column
        let ownerValue = owner.value
        let existingIDs =
            try Int64.fetchAll(
                db, sql: "SELECT evidence_span_id FROM evidence_span WHERE \(ownerColumn) = ?", arguments: [ownerValue])
        if !existingIDs.isEmpty {
            let placeholders = existingIDs.map { _ in "?" }.joined(separator: ",")
            try db.execute(
                sql: "DELETE FROM evidence_span_turn WHERE evidence_span_id IN (\(placeholders))",
                arguments: StatementArguments(existingIDs))
        }
        try db.execute(sql: "DELETE FROM evidence_span WHERE \(ownerColumn) = ?", arguments: [ownerValue])
    }

    /// Fetches every span for `owner`, in `position` order, with `turnIDs`
    /// reassembled from `evidence_span_turn`.
    static func fetch(_ db: Database, owner: EvidenceSpanOwner) throws -> [EvidenceSpan] {
        let ownerColumn = owner.column
        let ownerValue = owner.value
        let rows =
            try EvidenceSpanRow
            .filter(sql: "\(ownerColumn) = ?", arguments: [ownerValue])
            .order(Column("position"))
            .fetchAll(db)

        return try rows.map { row in
            let base = try row.asDomain()
            guard let spanID = row.evidenceSpanID else { return base }
            let turnIDs =
                try TranscriptTurnID.parsed(
                    from:
                        EvidenceSpanTurnRow
                        .filter(Column("evidence_span_id") == spanID)
                        .order(Column("position"))
                        .fetchAll(db))
            return EvidenceSpan(
                meetingID: base.meetingID, turnIDs: turnIDs, sampleRange: base.sampleRange,
                quotedText: base.quotedText, transcriptRevision: base.transcriptRevision)
        }
    }
}

extension EvidenceSpanOwner {
    fileprivate var isInsight: Bool {
        if case .insight = self { return true }
        return false
    }
    fileprivate var isAction: Bool {
        if case .action = self { return true }
        return false
    }
    fileprivate var isDecision: Bool {
        if case .decision = self { return true }
        return false
    }

    /// The one populated owner column for this case — factored out of
    /// `sync`/`clear`/`fetch`'s own repeated switches.
    fileprivate var column: String {
        switch self {
        case .insight: return "insight_id"
        case .action: return "action_id"
        case .decision: return "decision_id"
        }
    }

    fileprivate var value: String {
        switch self {
        case .insight(let id), .action(let id), .decision(let id): return id
        }
    }
}

extension TranscriptTurnID {
    fileprivate static func parsed(from rows: [EvidenceSpanTurnRow]) throws -> [TranscriptTurnID] {
        try rows.map { row in
            guard let uuid = UUID(uuidString: row.turnID) else {
                throw PersistenceError.corruptRow(
                    table: EvidenceSpanTurnRow.databaseTableName, column: "turn_id", value: row.turnID)
            }
            return TranscriptTurnID(rawValue: uuid)
        }
    }
}
