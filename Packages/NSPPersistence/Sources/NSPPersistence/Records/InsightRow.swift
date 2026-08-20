import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `insight` table (docs/02 §5). `Insight.evidence` rounds
/// through the shared `evidence_span` table via `EvidenceSpanPersistence`,
/// same as `Action.evidence` — `asDomain` takes it as a parameter rather
/// than reading it itself, matching `ActionRow`'s shape.
struct InsightRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "insight"

    var insightID: String
    var meetingID: String
    var layer: String
    var text: String
    var claimKind: String
    var confidence: Double
    var provenanceModelID: String
    var provenanceModelVersion: String
    var provenancePromptVersion: String
    var provenanceTemplateID: String?
    var provenanceTemplateVersion: String?
    var provenanceGeneratedAt: Date
    var provenanceProcessingPlane: String
    var approvalState: String
    var supersedes: String?
    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int
    var cloudRecordChangeTag: String?

    enum CodingKeys: String, CodingKey {
        case insightID = "insight_id"
        case meetingID = "meeting_id"
        case layer
        case text
        case claimKind = "claim_kind"
        case confidence
        case provenanceModelID = "provenance_model_id"
        case provenanceModelVersion = "provenance_model_version"
        case provenancePromptVersion = "provenance_prompt_version"
        case provenanceTemplateID = "provenance_template_id"
        case provenanceTemplateVersion = "provenance_template_version"
        case provenanceGeneratedAt = "provenance_generated_at"
        case provenanceProcessingPlane = "provenance_processing_plane"
        case approvalState = "approval_state"
        case supersedes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
        case cloudRecordChangeTag = "cloud_record_change_tag"
    }

    init(insight: Insight, createdAt: Date, updatedAt: Date, rowRevision: Int, cloudRecordChangeTag: String?) {
        self.insightID = insight.insightID.rawValue.uuidString
        self.meetingID = insight.meetingID.rawValue.uuidString
        self.layer = insight.layer.rawValue
        self.text = insight.text
        self.claimKind = insight.claimKind.rawValue
        self.confidence = insight.confidence
        self.provenanceModelID = insight.provenance.modelID
        self.provenanceModelVersion = insight.provenance.modelVersion
        self.provenancePromptVersion = insight.provenance.promptVersion
        self.provenanceTemplateID = insight.provenance.templateID
        self.provenanceTemplateVersion = insight.provenance.templateVersion
        self.provenanceGeneratedAt = insight.provenance.generatedAt
        self.provenanceProcessingPlane = insight.provenance.processingPlane.rawValue
        self.approvalState = insight.approvalState.rawValue
        self.supersedes = insight.supersedes?.rawValue.uuidString
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
        self.cloudRecordChangeTag = cloudRecordChangeTag
    }

    func asDomain(evidence: [EvidenceSpan]) throws -> Insight {
        guard let insightUUID = UUID(uuidString: insightID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "insight_id", value: insightID)
        }
        guard let meetingUUID = UUID(uuidString: meetingID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "meeting_id", value: meetingID)
        }
        guard let insightLayer = InsightLayer(rawValue: layer) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "layer", value: layer)
        }
        guard let kind = ClaimKind(rawValue: claimKind) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "claim_kind", value: claimKind)
        }
        guard let plane = ProcessingPlane(rawValue: provenanceProcessingPlane) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "provenance_processing_plane", value: provenanceProcessingPlane)
        }
        guard let approval = ApprovalState(rawValue: approvalState) else {
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "approval_state", value: approvalState)
        }
        let resolvedSupersedes: InsightID? =
            try supersedes.map {
                guard let uuid = UUID(uuidString: $0) else {
                    throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "supersedes", value: $0)
                }
                return InsightID(rawValue: uuid)
            }

        let provenance = Provenance(
            modelID: provenanceModelID, modelVersion: provenanceModelVersion, promptVersion: provenancePromptVersion,
            templateID: provenanceTemplateID, templateVersion: provenanceTemplateVersion,
            generatedAt: provenanceGeneratedAt, processingPlane: plane)

        return Insight(
            insightID: InsightID(rawValue: insightUUID), meetingID: MeetingID(rawValue: meetingUUID),
            layer: insightLayer, text: text, claimKind: kind, evidence: evidence, confidence: confidence,
            provenance: provenance, approvalState: approval, supersedes: resolvedSupersedes)
    }
}
