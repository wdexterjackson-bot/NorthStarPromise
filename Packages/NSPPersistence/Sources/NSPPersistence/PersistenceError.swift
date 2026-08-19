import Foundation

/// Typed, exhaustive error enum for `NSPPersistence` (docs/11 §2). No
/// `NSError`, no `try?` anywhere in this module — a swallowed error here
/// means a lost meeting or a silently missing row.
public enum PersistenceError: Error, Sendable, Hashable {
    /// A row expected to exist (usually the target of an `update`) was not
    /// found. Carries the table and the primary key that was looked up.
    case notFound(table: String, key: String)

    /// A stored value could not be decoded back into its domain type — e.g.
    /// an enum discriminator column held a string that matches no case.
    /// This is a schema/data corruption signal, never expected in normal
    /// operation.
    case corruptRow(table: String, column: String, value: String?)
}

extension PersistenceError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notFound(let table, let key):
            return "No row in \(table) with key \(key)"
        case .corruptRow(let table, let column, let value):
            return "Could not decode \(table).\(column) = \(value ?? "NULL")"
        }
    }
}
