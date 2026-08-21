import Foundation

/// A recording that is explicitly **not** a meeting — no attendees, no
/// calendar linkage, no thread of its own (its individual action
/// items/decisions can each join a thread once extracted, but the Brain
/// Dump itself never does). Still a real, durable audio capture through the
/// same pipeline a meeting uses (`MeetingContainer`/`CaptureEngine`/
/// `Segmenter` — none of which actually depend on the `Meeting` type, only
/// on an id and a container), so it needs the same capture-adjacent fields
/// a `Meeting` does. Reuses `MeetingState` for its lifecycle rather than a
/// parallel enum — the states involved (arming, recording, processing...)
/// are properties of *capturing audio*, not of being a meeting specifically.
public struct BrainDump: Sendable, Hashable, Codable, Identifiable {
    public let brainDumpID: BrainDumpID
    public var id: BrainDumpID { brainDumpID }
    public let workspaceID: WorkspaceID
    public let originDeviceID: DeviceID

    public var startedAt: Date
    public var endedAt: Date?
    public var canonicalDuration: SampleDuration
    public var lifecycleState: MeetingState

    public let policyID: PolicyID
    /// Frozen at Arming, same as `Meeting.processingMode` (Invariant I5).
    public let processingMode: ProcessingMode
    public var consentRecordID: ConsentRecordID?

    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        brainDumpID: BrainDumpID,
        workspaceID: WorkspaceID,
        originDeviceID: DeviceID,
        startedAt: Date,
        endedAt: Date? = nil,
        canonicalDuration: SampleDuration = .zero,
        lifecycleState: MeetingState,
        policyID: PolicyID,
        processingMode: ProcessingMode,
        consentRecordID: ConsentRecordID? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.brainDumpID = brainDumpID
        self.workspaceID = workspaceID
        self.originDeviceID = originDeviceID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.canonicalDuration = canonicalDuration
        self.lifecycleState = lifecycleState
        self.policyID = policyID
        self.processingMode = processingMode
        self.consentRecordID = consentRecordID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
