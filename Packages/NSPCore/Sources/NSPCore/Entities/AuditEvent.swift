import Foundation

/// One entry in the workspace-wide audit ledger `NSPPolicy` owns — every
/// grant issuance, export, and policy change writes one of these
/// (docs/02 §2, docs/01 §3 "NSPPolicy").
public struct AuditEvent: Sendable, Hashable, Codable, Identifiable {
    public let auditEventID: AuditEventID
    public var id: AuditEventID { auditEventID }

    public let actorID: PersonID?
    public let action: String
    public let object: String
    /// Hash of the acted-upon payload, never the payload itself — audit
    /// entries must never carry meeting content (docs/11 §9).
    public let payloadHash: String
    public let result: AuditResult
    public let timestamp: Date

    public init(
        auditEventID: AuditEventID,
        actorID: PersonID?,
        action: String,
        object: String,
        payloadHash: String,
        result: AuditResult,
        timestamp: Date
    ) {
        self.auditEventID = auditEventID
        self.actorID = actorID
        self.action = action
        self.object = object
        self.payloadHash = payloadHash
        self.result = result
        self.timestamp = timestamp
    }
}

/// The outcome of the audited action (docs/02 §2, `AuditEvent.result`).
public enum AuditResult: String, Sendable, Hashable, Codable, CaseIterable {
    case success
    case failure
    case denied
}
