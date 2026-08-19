import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `segment` table exactly (docs/02 §5 / NSP-011's
/// `Migration001InitialSchema`). Kept separate from `Segment` (`NSPCore`)
/// because the row carries bookkeeping columns — `rowRevision`,
/// `cloudRecordChangeTag` — that aren't part of the domain type, and splits
/// `transferState`'s `.failed(reason:)` payload into its own column.
struct SegmentRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "segment"

    var segmentID: String
    var meetingID: String
    var deviceID: String
    var sequence: Int
    var codec: String
    var sampleRate: Int
    var channels: Int
    var bitRate: Int
    var startSample: Int64
    var sampleCount: Int64
    var sha256: String?
    var localURL: String?
    var cloudAssetRef: String?
    var transferState: String
    var transferStateFailureReason: String?
    var isRepairedTail: Bool
    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int
    var cloudRecordChangeTag: String?

    // GRDB's `.convertFromSnakeCase`/`.convertToSnakeCase` don't recognize
    // `ID` as an acronym (`segment_id` → `segmentId`, not `segmentID`), so
    // every Row type in this package spells out its columns explicitly
    // rather than relying on that heuristic.
    enum CodingKeys: String, CodingKey {
        case segmentID = "segment_id"
        case meetingID = "meeting_id"
        case deviceID = "device_id"
        case sequence
        case codec
        case sampleRate = "sample_rate"
        case channels
        case bitRate = "bit_rate"
        case startSample = "start_sample"
        case sampleCount = "sample_count"
        case sha256
        case localURL = "local_url"
        case cloudAssetRef = "cloud_asset_ref"
        case transferState = "transfer_state"
        case transferStateFailureReason = "transfer_state_failure_reason"
        case isRepairedTail = "is_repaired_tail"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
        case cloudRecordChangeTag = "cloud_record_change_tag"
    }

    init(segment: Segment, createdAt: Date, updatedAt: Date, rowRevision: Int, cloudRecordChangeTag: String?) {
        self.segmentID = segment.segmentID.rawValue.uuidString
        self.meetingID = segment.meetingID.rawValue.uuidString
        self.deviceID = segment.deviceID.rawValue.uuidString
        self.sequence = segment.sequence
        self.codec = segment.codec.rawValue
        self.sampleRate = segment.sampleRate
        self.channels = segment.channels
        self.bitRate = segment.bitRate
        self.startSample = segment.startSample
        self.sampleCount = segment.sampleCount
        self.sha256 = segment.sha256?.map { String(format: "%02x", $0) }.joined()
        self.localURL = segment.localURL?.absoluteString
        self.cloudAssetRef = segment.cloudAssetRef
        switch segment.transferState {
        case .local: transferState = "local"
        case .queued: transferState = "queued"
        case .inFlight: transferState = "inFlight"
        case .receivedUnverified: transferState = "receivedUnverified"
        case .verified: transferState = "verified"
        case .reclaimed: transferState = "reclaimed"
        case .failed(let reason):
            transferState = "failed"
            transferStateFailureReason = reason
        }
        self.isRepairedTail = segment.isRepairedTail
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
        self.cloudRecordChangeTag = cloudRecordChangeTag
    }

    // swiftlint:disable:next cyclomatic_complexity
    func asDomain() throws -> Segment {
        guard let segmentUUID = UUID(uuidString: segmentID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "segment_id", value: segmentID)
        }
        guard let meetingUUID = UUID(uuidString: meetingID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "meeting_id", value: meetingID)
        }
        guard let deviceUUID = UUID(uuidString: deviceID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "device_id", value: deviceID)
        }
        guard let codecValue = AudioCodec(rawValue: codec) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "codec", value: codec)
        }

        let resolvedTransferState: TransferState
        switch transferState {
        case "local": resolvedTransferState = .local
        case "queued": resolvedTransferState = .queued
        case "inFlight": resolvedTransferState = .inFlight
        case "receivedUnverified": resolvedTransferState = .receivedUnverified
        case "verified": resolvedTransferState = .verified
        case "reclaimed": resolvedTransferState = .reclaimed
        case "failed": resolvedTransferState = .failed(reason: transferStateFailureReason ?? "unknown")
        default:
            throw PersistenceError.corruptRow(
                table: Self.databaseTableName, column: "transfer_state", value: transferState)
        }

        return Segment(
            segmentID: SegmentID(rawValue: segmentUUID),
            meetingID: MeetingID(rawValue: meetingUUID),
            deviceID: DeviceID(rawValue: deviceUUID),
            sequence: sequence,
            codec: codecValue,
            sampleRate: sampleRate,
            channels: channels,
            bitRate: bitRate,
            startSample: startSample,
            sampleCount: sampleCount,
            sha256: sha256.flatMap { Data(hexString: $0) },
            localURL: localURL.flatMap { URL(string: $0) },
            cloudAssetRef: cloudAssetRef,
            transferState: resolvedTransferState,
            isRepairedTail: isRepairedTail
        )
    }
}

extension Data {
    /// Round-trips `SegmentRow.sha256`'s lowercase-hex encoding.
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}
