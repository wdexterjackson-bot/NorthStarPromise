import Foundation
@preconcurrency import GRDB
import NSPCore

/// Mirrors the `timeline_event` table (docs/02 §5). `TimelineEventType`'s
/// associated values vary per case (a route pair, a single reason, nothing
/// at all), so unlike the fixed one-or-two-column split used elsewhere in
/// this package, they're serialized as a small JSON object in
/// `typeDetailJSON` — see `Migration001InitialSchema`'s file header for why.
struct TimelineEventRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "timeline_event"

    var eventID: String
    var ownerID: String
    var ownerKind: String
    var deviceID: String
    var type: String
    var typeDetailJSON: String?
    var sampleOffset: Int64
    var wallClock: Date
    var payloadJSON: String?
    var createdAt: Date
    var updatedAt: Date
    var rowRevision: Int

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case ownerID = "meeting_id"
        case ownerKind = "owner_kind"
        case deviceID = "device_id"
        case type
        case typeDetailJSON = "type_detail_json"
        case sampleOffset = "sample_offset"
        case wallClock = "wall_clock"
        case payloadJSON = "payload_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case rowRevision = "row_revision"
    }

    init(event: TimelineEvent, createdAt: Date, updatedAt: Date, rowRevision: Int) throws {
        self.eventID = event.eventID.rawValue.uuidString
        let owner = ContentOwnerRefColumns.encode(event.owner)
        self.ownerID = owner.id
        self.ownerKind = owner.kind
        self.deviceID = event.deviceID.rawValue.uuidString
        let (kind, detail) = try Self.encode(event.type)
        self.type = kind
        self.typeDetailJSON = detail
        self.sampleOffset = event.sampleOffset
        self.wallClock = event.wallClock
        self.payloadJSON = try event.payload.map { try Self.jsonString(encoding: $0) }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowRevision = rowRevision
    }

    /// `JSONEncoder` always produces valid UTF-8, so the only way this
    /// fails is a genuine encoding error, which the `try` above already
    /// surfaces — `String(bytes:encoding:)` here is a formality, not a
    /// real failure path.
    private static func jsonString(encoding value: some Encodable) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(bytes: data, encoding: .utf8) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "type_detail_json", value: nil)
        }
        return string
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func encode(_ type: TimelineEventType) throws -> (kind: String, detail: String?) {
        switch type {
        case .start: return ("start", nil)
        case .pause: return ("pause", nil)
        case .resume: return ("resume", nil)
        case .interruptionBegan(let cause):
            return ("interruptionBegan", try jsonString(encoding: ["cause": cause.rawValue]))
        case .interruptionEnded: return ("interruptionEnded", nil)
        case .routeChange(let from, let to):
            return ("routeChange", try jsonString(encoding: ["from": from.rawValue, "to": to.rawValue]))
        case .marker(let kind):
            return ("marker", try jsonString(encoding: ["kind": kind.rawValue]))
        case .levelWarning(let kind):
            return ("levelWarning", try jsonString(encoding: ["kind": kind.rawValue]))
        case .thermal(let state):
            return ("thermal", try jsonString(encoding: ["state": state.rawValue]))
        case .batteryWarning: return ("batteryWarning", nil)
        case .storageWarning: return ("storageWarning", nil)
        case .sealedStop(let reason):
            return ("sealedStop", try jsonString(encoding: ["reason": reason.rawValue]))
        case .stop: return ("stop", nil)
        }
    }

    func asDomain() throws -> TimelineEvent {
        guard let eventUUID = UUID(uuidString: eventID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "event_id", value: eventID)
        }
        let owner = try ContentOwnerRefColumns.decode(id: ownerID, kind: ownerKind, table: Self.databaseTableName)
        guard let deviceUUID = UUID(uuidString: deviceID) else {
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "device_id", value: deviceID)
        }

        let resolvedPayload: JSONValue? =
            try payloadJSON.map { text in
                try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
            }

        return TimelineEvent(
            eventID: TimelineEventID(rawValue: eventUUID),
            owner: owner,
            deviceID: DeviceID(rawValue: deviceUUID),
            type: try resolveType(),
            sampleOffset: sampleOffset,
            wallClock: wallClock,
            payload: resolvedPayload
        )
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func resolveType() throws -> TimelineEventType {
        func detail<T: Decodable>(_ key: String) throws -> T {
            guard let json = typeDetailJSON else {
                throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "type_detail_json", value: nil)
            }
            let dict = try JSONDecoder().decode([String: T].self, from: Data(json.utf8))
            guard let value = dict[key] else {
                throw PersistenceError.corruptRow(
                    table: Self.databaseTableName, column: "type_detail_json", value: json)
            }
            return value
        }

        switch type {
        case "start": return .start
        case "pause": return .pause
        case "resume": return .resume
        case "interruptionBegan":
            let raw: String = try detail("cause")
            guard let cause = InterruptionCause(rawValue: raw) else {
                throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "type_detail_json", value: raw)
            }
            return .interruptionBegan(cause: cause)
        case "interruptionEnded": return .interruptionEnded
        case "routeChange":
            guard let json = typeDetailJSON,
                let dict = try? JSONDecoder().decode([String: String].self, from: Data(json.utf8)),
                let fromRaw = dict["from"], let toRaw = dict["to"],
                let from = AudioRouteEndpoint(rawValue: fromRaw), let to = AudioRouteEndpoint(rawValue: toRaw)
            else {
                throw PersistenceError.corruptRow(
                    table: Self.databaseTableName, column: "type_detail_json", value: typeDetailJSON)
            }
            return .routeChange(from: from, to: to)
        case "marker":
            let raw: String = try detail("kind")
            guard let kind = MarkerKind(rawValue: raw) else {
                throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "type_detail_json", value: raw)
            }
            return .marker(kind: kind)
        case "levelWarning":
            let raw: String = try detail("kind")
            guard let kind = LevelWarningKind(rawValue: raw) else {
                throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "type_detail_json", value: raw)
            }
            return .levelWarning(kind: kind)
        case "thermal":
            let raw: String = try detail("state")
            guard let state = ThermalState(rawValue: raw) else {
                throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "type_detail_json", value: raw)
            }
            return .thermal(state: state)
        case "batteryWarning": return .batteryWarning
        case "storageWarning": return .storageWarning
        case "sealedStop":
            let raw: String = try detail("reason")
            guard let reason = SealedStopReason(rawValue: raw) else {
                throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "type_detail_json", value: raw)
            }
            return .sealedStop(reason: reason)
        case "stop": return .stop
        default:
            throw PersistenceError.corruptRow(table: Self.databaseTableName, column: "type", value: type)
        }
    }
}
