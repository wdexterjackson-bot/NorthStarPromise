import Foundation

/// A UUIDv7-backed identifier scoped to one entity kind by its phantom `Tag`.
/// Never pass a raw `UUID` across a package boundary — every entity ID in
/// this codebase is a `TypedID` (docs/02 §1, docs/11 §1).
public struct TypedID<Tag>: Sendable, Hashable, Codable, CustomStringConvertible, Identifiable {
    public let rawValue: UUID
    public var id: UUID { rawValue }

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// Parses an existing identifier, e.g. one read back from storage.
    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.rawValue = uuid
    }

    /// Mints a fresh, time-ordered ID. `clock` is required — never wall-clock
    /// implicitly — so tests can produce deterministic, sortable fixtures.
    /// Takes the existential `any Clock` (not `some Clock`) so callers can
    /// store their clock as a plain `let clock: Clock` property, the normal
    /// DI shape (docs/11 §4), without that generic parameter propagating.
    public static func generate(
        clock: any Clock,
        randomSource: inout some RandomNumberGenerator
    ) -> TypedID<Tag> {
        TypedID(rawValue: UUIDv7.generate(timestamp: clock.now(), using: &randomSource))
    }

    public static func generate(clock: any Clock) -> TypedID<Tag> {
        var generator = SystemRandomNumberGenerator()
        return generate(clock: clock, randomSource: &generator)
    }

    public var description: String { rawValue.uuidString }
}
