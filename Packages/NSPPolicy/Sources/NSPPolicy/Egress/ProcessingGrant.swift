import Foundation
import NSPCore

/// Proof that `NetworkGate.authorize` allowed one specific egress. Deliberately
/// unforgeable (docs/06 §2, POL-002): `init` is `internal`, so only code inside
/// `NSPPolicy` can construct one, and it does not conform to `Codable` — a
/// grant is a capability that exists for the lifetime of one call chain, not
/// a value meant to be serialized, stored, or reconstructed from bytes a
/// caller controls. `NSPPolicy/Tests/ArchitectureTests.swift` proves POL-002
/// by source-scanning for construction sites outside this module.
public struct ProcessingGrant: Sendable, Hashable, Identifiable {
    public let grantID: GrantID
    public var id: GrantID { grantID }

    public let meetingID: MeetingID
    public let policyID: PolicyID
    public let mode: ProcessingMode
    public let allowedClasses: Set<ContentClass>
    public let capabilities: Set<ProcessingCapability>
    public let expiresAt: Date
    public let region: ProcessingRegion
    public let retentionSeconds: Int
    public let auditEventID: AuditEventID

    init(
        grantID: GrantID,
        meetingID: MeetingID,
        policyID: PolicyID,
        mode: ProcessingMode,
        allowedClasses: Set<ContentClass>,
        capabilities: Set<ProcessingCapability>,
        expiresAt: Date,
        region: ProcessingRegion,
        retentionSeconds: Int,
        auditEventID: AuditEventID
    ) {
        self.grantID = grantID
        self.meetingID = meetingID
        self.policyID = policyID
        self.mode = mode
        self.allowedClasses = allowedClasses
        self.capabilities = capabilities
        self.expiresAt = expiresAt
        self.region = region
        self.retentionSeconds = retentionSeconds
        self.auditEventID = auditEventID
    }

    /// Whether this grant may still be presented to the processing plane.
    /// Expiry is the only thing a holder can check locally — revocation
    /// (docs/06 §2 `NetworkGate.revokeAll`) is enforced server-side, not
    /// observable from a `ProcessingGrant` value alone.
    public func isExpired(asOf now: Date = Date()) -> Bool {
        now >= expiresAt
    }
}
