import NSPCore

/// What `DefaultNetworkGate` needs in order to satisfy "every grant issuance
/// writes an AuditEvent" (docs/06 §2, NSP-016 acceptance) without `NSPPolicy`
/// taking a dependency on `NSPPersistence` — the dependency graph runs
/// `NSPPersistence` → ... → `NSPPolicy`-consuming modules, never the reverse
/// (docs/01 §4), so `NSPPolicy` can only declare what it needs and let a
/// composition root elsewhere (a module that already depends on both) supply
/// the adapter backed by a real `AuditEventRepository`.
public protocol AuditEventRecorder: Sendable {
    func record(_ event: AuditEvent) async throws
}

/// What `DefaultNetworkGate` needs to check `EgressDenial.noConsentRecord`
/// (docs/06 §2). Same dependency-inversion reasoning as `AuditEventRecorder`.
public protocol ConsentRecordLookup: Sendable {
    func hasConsentRecord(for meetingID: MeetingID) async -> Bool
}

/// What `DefaultNetworkGate` needs to read a meeting's frozen `Policy`
/// snapshot (`ProcessingMode`, `PolicyID`) — `EgressRequest` itself carries
/// neither, since the gate is the thing that looks them up, not the thing
/// trusted with a caller-declared mode (docs/06 §1.1: the mode a meeting
/// runs under is never a request parameter). Same dependency-inversion
/// reasoning as `AuditEventRecorder`.
public protocol PolicySnapshotLookup: Sendable {
    func policy(for meetingID: MeetingID) async -> Policy?
}
