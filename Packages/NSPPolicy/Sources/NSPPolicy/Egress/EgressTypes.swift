import Foundation
import NSPCore

/// What kind of content an `EgressRequest` carries (docs/06 §2, verbatim
/// list). `NetworkGate.authorize` checks every requested class is
/// permitted under the meeting's frozen `ProcessingMode` before minting a
/// grant.
public enum ContentClass: String, Sendable, Hashable, Codable, CaseIterable {
    case audio, transcript, notes, title, attendees, attachments, derivedEmbedding
}

/// Which processing-ladder capability a `ProcessingGrant` authorizes
/// (docs/04 §2 — declared there, authoritative here per that section's own
/// note: "see docs/06 §2 for the authoritative declaration").
public enum ProcessingCapability: Sendable, Hashable, CaseIterable {
    case streamingASR, batchASR, diarization, summarization, embedding, entailment
}

/// Where a job may run (docs/05 §3.1, docs/06 §11: "a grant carries
/// `region`... jobs execute only in that region's deployment").
public enum ProcessingRegion: String, Sendable, Hashable, Codable, CaseIterable {
    case unitedStates = "us"
    case europe = "eu"
    case asiaPacific = "apac"
}

/// What a caller wants to send — declared, not inferred (docs/06 §2,
/// verbatim). `.integrationWrite`'s destination is a plain `String` rather
/// than a dedicated enum, matching `IntegrationReceipt.destination`'s
/// existing shape in `NSPCore` (docs/02 §2) — connectors are configured by
/// name, not a closed Swift enum, since new ones (docs/05 §9) ship without
/// a schema migration.
public enum EgressPurpose: Sendable, Hashable {
    case transcription, diarization, summarization, retrievalIndex
    case cloudKitSync, shareLink
    case integrationWrite(destination: String)
    case diagnosticsBundle
}

/// Which network-facing service a request targets — a coarser dimension
/// than `EgressPurpose` (which says *why*; this says *where*).
public enum EgressDestination: Sendable, Hashable {
    case backendProcessingPlane
    case cloudKit
    case shareLinkService
    case integrationConnector(String)
    case diagnostics
}

/// Why an `authorize` call was refused (docs/06 §2, verbatim case list —
/// deliberately not open-ended: every denial fits one of these).
public enum EgressDenial: Sendable, Hashable {
    case localOnlyMeeting
    case classNotPermitted(ContentClass)
    case noConsentRecord
    case workspacePolicyBlocked(reason: String)
    case regionUnavailable
    case userConfirmationRequired
}

/// `NetworkGate.authorize`'s result (docs/06 §2).
public enum EgressDecision: Sendable {
    case allowed(ProcessingGrant)
    case denied(EgressDenial)
}

/// Why `NetworkGate.revokeAll` was called.
public enum RevocationReason: Sendable, Hashable {
    case userRequested
    case policyTightened
    case meetingDeleted
    case consentWithdrawn
}
