import Foundation

/// One immutable, content-addressed slice of audio (Invariant I3, docs/02 §2).
/// Once closed it is never rewritten, re-encoded in place, or renamed.
public struct Segment: Sendable, Hashable, Codable, Identifiable {
    public let segmentID: SegmentID
    public var id: SegmentID { segmentID }
    public let owner: ContentOwnerRef
    public let deviceID: DeviceID

    /// Monotonic per device, gapless. A gap means a lost segment and must be
    /// surfaced, never silently skipped.
    public let sequence: Int

    public let codec: AudioCodec
    public let sampleRate: Int
    public let channels: Int
    public let bitRate: Int

    /// Offset from meeting sample zero, for this device.
    public let startSample: Int64
    /// Authoritative duration — the only source of truth for this segment's
    /// length.
    public let sampleCount: Int64

    /// Computed after close, before rename.
    public var sha256: Data?
    /// Nil once reclaimed.
    public var localURL: URL?
    public var cloudAssetRef: String?

    public var transferState: TransferState
    public var isRepairedTail: Bool

    public init(
        segmentID: SegmentID,
        owner: ContentOwnerRef,
        deviceID: DeviceID,
        sequence: Int,
        codec: AudioCodec,
        sampleRate: Int,
        channels: Int,
        bitRate: Int,
        startSample: Int64,
        sampleCount: Int64,
        sha256: Data? = nil,
        localURL: URL? = nil,
        cloudAssetRef: String? = nil,
        transferState: TransferState = .local,
        isRepairedTail: Bool = false
    ) {
        self.segmentID = segmentID
        self.owner = owner
        self.deviceID = deviceID
        self.sequence = sequence
        self.codec = codec
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitRate = bitRate
        self.startSample = startSample
        self.sampleCount = sampleCount
        self.sha256 = sha256
        self.localURL = localURL
        self.cloudAssetRef = cloudAssetRef
        self.transferState = transferState
        self.isRepairedTail = isRepairedTail
    }
}
